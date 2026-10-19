import Foundation
import IrohLib

public enum P2PTransportError: Error { case invalidAddress, frameBounds, busy, closed, unexpectedPeer }

public struct P2PAddress: Codable, Equatable, Sendable {
    public var endpointId: String
    public var relayURL: String?
    public var directAddresses: [String]
    public init(endpointId: String, relayURL: String? = nil, directAddresses: [String] = []) {
        self.endpointId = endpointId; self.relayURL = relayURL; self.directAddresses = directAddresses
    }
    fileprivate func native() throws -> EndpointAddr {
        guard endpointId.count == 64, endpointId.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              directAddresses.count <= 32, directAddresses.allSatisfy({ $0.utf8.count <= 128 }) else {
            throw P2PTransportError.invalidAddress
        }
        if let relayURL {
            guard relayURL.utf8.count <= 2048, let url = URLComponents(string: relayURL),
                  url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
                  url.query == nil, url.fragment == nil else { throw P2PTransportError.invalidAddress }
        }
        return EndpointAddr(id: try EndpointId.fromString(s: endpointId), relayUrl: relayURL, addresses: directAddresses)
    }
}

public enum P2PConnectivity: Sendable {
    /// No discovery, VPN, public relay, HTTP API or central business service.
    case directOnly
    /// Opt-in NAT traversal with upstream discovery/relay; no monitoring client.
    case automatic
    /// Operator-selected reachable connectivity helpers; business data stays local.
    case customRelays([String])
}

public struct P2PPath: Codable, Equatable, Sendable {
    public var selected: Bool
    public var direct: Bool
    public var relayed: Bool
    public var rttMilliseconds: UInt64
}

/// An independent transport key must be persisted by the app before production
/// use. This raw transport never grants membership or interprets business data.
public actor IrohEndpoint {
    private let endpoint: Endpoint
    private init(_ endpoint: Endpoint) { self.endpoint = endpoint }
    public static func generateTransportKey() -> Data { SecretKey.generate().toBytes() }
    public static func bind(secretKey: Data, connectivity: P2PConnectivity = .directOnly,
                            bindAddress: String? = nil) async throws -> IrohEndpoint {
        guard secretKey.count == 32 else { throw P2PTransportError.invalidAddress }
        let preset: any Preset
        let relay: RelayMode
        switch connectivity {
        case .directOnly: preset = presetMinimal(); relay = .disabled()
        case .automatic: preset = presetN0(); relay = .defaultMode()
        case .customRelays(let urls):
            guard !urls.isEmpty, urls.count <= 8 else { throw P2PTransportError.invalidAddress }
            for url in urls { _ = try P2PAddress(endpointId: String(repeating: "a", count: 64), relayURL: url).native() }
            preset = presetMinimal(); relay = try .customFromUrls(urls: urls)
        }
        return try await IrohEndpoint(Endpoint.bind(options: EndpointOptions(preset: preset,
            bindAddr: bindAddress, secretKey: secretKey, alpns: [P2PTransportLimits.alpn], relayMode: relay)))
    }
    public func address() -> P2PAddress {
        let addr = endpoint.addr()
        return P2PAddress(endpointId: addr.id().description, relayURL: addr.relayUrl(), directAddresses: addr.directAddresses())
    }
    public func boundSockets() -> [String] { endpoint.boundSockets() }
    public func connect(to address: P2PAddress) async throws -> IrohFrameConnection {
        let connection = try await endpoint.connect(addr: address.native(), alpn: P2PTransportLimits.alpn)
        guard connection.remoteId().description == address.endpointId else {
            try? connection.close(errorCode: 1, reason: Data()); throw P2PTransportError.unexpectedPeer
        }
        return try await IrohFrameConnection(connection: connection, stream: connection.openBi())
    }
    public func accept(expectedEndpointId: String) async throws -> IrohFrameConnection {
        guard let incoming = await endpoint.acceptNext() else { throw P2PTransportError.closed }
        let connection = try await incoming.accept().connect()
        guard connection.remoteId().description == expectedEndpointId,
              connection.alpn() == P2PTransportLimits.alpn else {
            try? connection.close(errorCode: 1, reason: Data()); throw P2PTransportError.unexpectedPeer
        }
        return try await IrohFrameConnection(connection: connection, stream: connection.acceptBi())
    }
    public func close() async throws { try await endpoint.close() }
}

/// One ordered, backpressured stream. A file is sent through existing 64 KiB
/// media messages. A malicious length is rejected before payload allocation.
public actor IrohFrameConnection {
    private let connection: Connection
    private let stream: BiStream
    private var receiving = false
    private var closed = false
    private var sending = false
    private var queuedBytes = 0
    private var queuedFrames = 0
    private var writers: [CheckedContinuation<Void, Never>] = []
    fileprivate init(connection: Connection, stream: BiStream) { self.connection = connection; self.stream = stream }
    public func remoteEndpointId() -> String { connection.remoteId().description }
    public func paths() -> [P2PPath] {
        connection.paths().map { P2PPath(selected: $0.isSelected, direct: $0.isIp, relayed: $0.isRelay, rttMilliseconds: $0.rttMs) }
    }
    public func send(_ bytes: Data) async throws {
        guard !closed else { throw P2PTransportError.closed }
        guard !bytes.isEmpty, bytes.count <= P2PTransportLimits.maximumFrameBytes else { throw P2PTransportError.frameBounds }
        guard queuedFrames < 64, queuedBytes + bytes.count <= 8_388_608 else { throw P2PTransportError.frameBounds }
        queuedFrames += 1; queuedBytes += bytes.count
        if sending { await withCheckedContinuation { writers.append($0) } } else { sending = true }
        defer {
            queuedFrames -= 1; queuedBytes -= bytes.count
            if writers.isEmpty { sending = false } else { writers.removeFirst().resume() }
        }
        try Task.checkCancellation()
        guard !closed else { throw P2PTransportError.closed }
        var length = UInt32(bytes.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }; frame.append(bytes)
        try await stream.send().writeAll(buf: frame)
    }
    public func receive() async throws -> Data {
        guard !closed else { throw P2PTransportError.closed }
        guard !receiving else { throw P2PTransportError.busy }
        receiving = true; defer { receiving = false }
        let prefix = try await stream.recv().readExact(size: 4)
        let length = prefix.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= P2PTransportLimits.maximumFrameBytes else {
            close(); throw P2PTransportError.frameBounds
        }
        return try await stream.recv().readExact(size: length)
    }
    public func close() {
        closed = true
        try? connection.close(errorCode: 0, reason: Data())
        let waiting = writers; writers = []; waiting.forEach { $0.resume() }
    }
}
