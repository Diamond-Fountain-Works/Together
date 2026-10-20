import Foundation
import IrohLib

public enum P2PTransportError: Error { case invalidAddress, frameBounds, busy, closed, unexpectedPeer, relayReadiness }
/// Only failures before any application device identity/pin is available.
/// A caller may reject this unauthenticated candidate and keep listening.
/// Contact signatures, pinned identities and authenticated frames never use
/// this classification and must continue to fail closed.
public enum P2PUnverifiedIncomingError: Error, Sendable {
    case handshake(String)
    case unsupportedALPN
}

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

/// Test constraint implemented through the pinned public foreign-preset API.
/// Both address families must be replaced: setting just IPv4 leaves the
/// builder's default IPv6 socket available for direct application QUIC.
private final class LoopbackQuicPresetForQA: Preset, @unchecked Sendable {
    private let base: any Preset
    private let lock = NSLock()
    private var failed = false
    init(base: any Preset) { self.base = base }
    func apply(builder: EndpointBuilder) {
        base.apply(builder: builder)
        do {
            try builder.bindAddr(addr: "127.0.0.1:0")
            try builder.bindAddr(addr: "[::1]:0")
        } catch { lock.withLock { failed = true } }
    }
    var configurationFailed: Bool { lock.withLock { failed } }
}

/// An independent transport key must be persisted by the app before production
/// use. This raw transport never grants membership or interprets business data.
public actor IrohEndpoint {
    private let endpoint: Endpoint
    private let applicationProtocol: Data
    private init(_ endpoint: Endpoint, applicationProtocol: Data) { self.endpoint = endpoint; self.applicationProtocol = applicationProtocol }
    public static func generateTransportKey() -> Data { SecretKey.generate().toBytes() }
    public static func bind(secretKey: Data, connectivity: P2PConnectivity = .directOnly,
                            bindAddress: String? = nil, loopbackQuicForQA: Bool = false,
                            applicationProtocol: Data = P2PTransportLimits.alpn) async throws -> IrohEndpoint {
        guard secretKey.count == 32, !loopbackQuicForQA || bindAddress == nil,
              [P2PTransportLimits.alpn, P2PTransportLimits.nativeAppALPN].contains(applicationProtocol) else {
            throw P2PTransportError.invalidAddress
        }
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
        let constrained = loopbackQuicForQA ? LoopbackQuicPresetForQA(base: preset) : nil
        let selectedPreset: any Preset
        if let constrained { selectedPreset = constrained } else { selectedPreset = preset }
        let value = try await IrohEndpoint(Endpoint.bind(options: EndpointOptions(preset: selectedPreset,
            bindAddr: loopbackQuicForQA ? nil : bindAddress, secretKey: secretKey,
            alpns: [applicationProtocol], relayMode: relay)), applicationProtocol: applicationProtocol)
        if loopbackQuicForQA {
            do {
                guard constrained?.configurationFailed == false else { throw P2PTransportError.invalidAddress }
                try await value.requireLoopbackQuicForQA()
            } catch { try? await value.close(); throw error }
        }
        return value
    }
    public func address() -> P2PAddress {
        let addr = endpoint.addr()
        return P2PAddress(endpointId: addr.id().description, relayURL: addr.relayUrl(), directAddresses: addr.directAddresses())
    }
    public func boundSockets() -> [String] { endpoint.boundSockets() }
    /// Verifies only application QUIC binds. DNS/discovery/relay helper traffic
    /// has independent sockets and is intentionally outside this QA assertion.
    public func requireLoopbackQuicForQA() throws {
        let sockets = endpoint.boundSockets()
        var families = Set<Int>()
        for socket in sockets {
            let portText: Substring
            if socket.hasPrefix("127.0.0.1:") { portText = socket.dropFirst(10); families.insert(4) }
            else if socket.hasPrefix("[::1]:") { portText = socket.dropFirst(6); families.insert(6) }
            else { throw P2PTransportError.invalidAddress }
            guard !portText.isEmpty, portText.utf8.allSatisfy({ (48...57).contains($0) }),
                  let port = UInt16(portText), port > 0 else { throw P2PTransportError.invalidAddress }
        }
        guard sockets.count == 2, families == [4, 6] else { throw P2PTransportError.invalidAddress }
    }
    /// Waits only for a selected relay address, NOT a connected relay handshake.
    /// The pinned Swift online() bridge ignores cancellation, so this bounded
    /// public-API poll never starts that native future. Actual QUIC + signed
    /// Protocol 4 authentication must separately establish reachability.
    public func waitForRelayAddress(timeout: Duration = .seconds(15)) async throws -> Bool {
        guard timeout > .zero, timeout <= .seconds(60) else { throw P2PTransportError.relayReadiness }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while true {
            try Task.checkCancellation()
            guard !endpoint.isClosed() else { throw P2PTransportError.closed }
            let address = address()
            if address.relayURL != nil {
                _ = try address.native() // Require a validated HTTPS routing hint.
                return true
            }
            let now = clock.now
            guard now < deadline else { return false }
            try await clock.sleep(until: min(deadline, now.advanced(by: .milliseconds(100))))
        }
    }
    public func connect(to address: P2PAddress) async throws -> IrohFrameConnection {
        let connection = try await endpoint.connect(addr: address.native(), alpn: applicationProtocol)
        guard connection.remoteId().description == address.endpointId else {
            try? connection.close(errorCode: 1, reason: Data()); throw P2PTransportError.unexpectedPeer
        }
        return try await IrohFrameConnection(connection: connection, stream: connection.openBi())
    }
    public func accept(expectedEndpointId: String) async throws -> IrohFrameConnection {
        let connection = try await acceptForPartnerBootstrap()
        guard await connection.remoteEndpointId() == expectedEndpointId else {
            await connection.close(); throw P2PTransportError.unexpectedPeer
        }
        return connection
    }
    /// Only a transport connection. The caller must verify the first signed
    /// contact against this connection's TLS identity, then require mutual
    /// identity confirmation before granting access to any signed facts.
    public func acceptForPartnerBootstrap() async throws -> IrohFrameConnection {
        guard let incoming = await endpoint.acceptNext() else { throw P2PTransportError.closed }
        try Task.checkCancellation()
        let connection: Connection
        do { connection = try await incoming.accept().connect() }
        catch {
            try Task.checkCancellation()
            guard !endpoint.isClosed() else { throw P2PTransportError.closed }
            throw P2PUnverifiedIncomingError.handshake(String(describing: error))
        }
        guard connection.alpn() == applicationProtocol else {
            try? connection.close(errorCode: 1, reason: Data()); throw P2PUnverifiedIncomingError.unsupportedALPN
        }
        do {
            try Task.checkCancellation()
            return try await IrohFrameConnection(connection: connection, stream: connection.acceptBi())
        } catch {
            try? connection.close(errorCode: 1, reason: Data()); throw error
        }
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
