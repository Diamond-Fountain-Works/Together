import Foundation
import Combine
@preconcurrency import Network

public enum TransportState: Sendable { case offline, connecting, connected, error }
public enum TransportEndpoint: Sendable { case relay(url: URL, ticket: String), legacy(host: String, port: UInt16) }
@MainActor public protocol SyncTransport: AnyObject {
    var state: TransportState { get }
    var onReceive: ((Data) -> Void)? { get set }
    var onState: ((TransportState) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
    func connect(_ endpoint: TransportEndpoint) async throws
    func send(_ data: Data) async throws
    func disconnect()
}

@MainActor public final class RelayWebSocketTransport: SyncTransport, ObservableObject {
    @Published public private(set) var state: TransportState = .offline
    public var onReceive: ((Data) -> Void)?
    public var onState: ((TransportState) -> Void)?
    public var onError: ((Error) -> Void)?
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private let session: URLSession
    public init(session: URLSession? = nil) { self.session = session ?? RelayURLSession.make() }
    public func connect(_ endpoint: TransportEndpoint) async throws {
        guard case let .relay(url, ticket) = endpoint else { throw TogetherError.invalid(Copy.text("copy.error.3df54032c0e6")) }
        disconnect(); set(.connecting)
        var request = URLRequest(url: url); request.setValue("Bearer " + ticket, forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request); task.maximumMessageSize = FrameDecoder.maximum; self.task = task; task.resume()
        receiveTask = Task { @MainActor [weak self] in
            do {
                while !Task.isCancelled {
                    let message = try await CompatibilityURLSession.receive(task)
                    guard let self, self.task === task else { return }
                    self.set(.connected)
                    let data: Data; switch message { case .data(let bytes): data = bytes; case .string(let text): data = Data(text.utf8); @unknown default: throw TogetherError.invalid(Copy.text("copy.error.5de002320d44")) }
                    guard data.count <= FrameDecoder.maximum else { throw TogetherError.invalid(Copy.text("copy.error.99e51d775e05")) }
                    self.onReceive?(data)
                }
            } catch { if !Task.isCancelled, let self, self.task === task { self.set(.error); self.onError?(error) } }
        }
    }
    public func send(_ data: Data) async throws {
        guard let task, data.count <= FrameDecoder.maximum else { throw TogetherError.invalid(Copy.text("copy.error.c71af0e23a33")) }
        try await CompatibilityURLSession.send(.data(data), through: task)
    }
    public func disconnect() { receiveTask?.cancel(); receiveTask = nil; task?.cancel(with: .goingAway, reason: nil); task = nil; set(.offline) }
    private func set(_ state: TransportState) { self.state = state; onState?(state) }
}

/// Retained low-level TCP adapter for migration and local regression tests.
/// Legacy PeerService still owns its original listener/pairing lifecycle.
@MainActor public final class LegacyTailscaleTransport: SyncTransport {
    @Published public private(set) var state: TransportState = .offline
    public var onReceive: ((Data) -> Void)?
    public var onState: ((TransportState) -> Void)?
    public var onError: ((Error) -> Void)?
    private var connection: NWConnection?
    private var decoder = FrameDecoder()
    private let queue = DispatchQueue(label: "com.together.legacy.transport")
    public init() {}
    public func connect(_ endpoint: TransportEndpoint) async throws {
        guard case let .legacy(host, port) = endpoint, NetworkAddressPolicy.allowed(host), port > 0 else { throw TogetherError.invalid(Copy.text("copy.error.32068192f569")) }
        disconnect(); decoder = FrameDecoder(); state = .connecting; onState?(state)
        let connection = NWConnection(host: .init(host), port: .init(rawValue: port)!, using: .tcp); self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in Task { @MainActor in
            guard let self, self.connection === connection else { return }
            switch state { case .ready: self.state = .connected; self.onState?(.connected); self.receive(connection)
            case .failed(let error), .waiting(let error): self.state = .error; self.onState?(.error); self.onError?(error)
            default: break }
        } }
        connection.start(queue: queue)
    }
    private func receive(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in Task { @MainActor in
            guard let self, self.connection === connection else { return }
            do { if let data { for frame in try self.decoder.append(data) { self.onReceive?(frame) } }; if let error { throw error }; if complete { self.disconnect() } else { self.receive(connection) } }
            catch { self.onError?(error); self.disconnect() }
        } }
    }
    public func send(_ data: Data) async throws {
        guard let connection else { throw TogetherError.invalid(Copy.text("copy.error.4e3a074f1822")) }
        let frame = try FrameDecoder.encode(data)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: frame, completion: .contentProcessed { error in if let error { continuation.resume(throwing: error) } else { continuation.resume() } })
        }
    }
    public func disconnect() { connection?.cancel(); connection = nil; state = .offline; onState?(.offline) }
}

public protocol EncryptedMailbox: Sendable {
    func uploadCiphertext(_ data: Data, resourceId: UUID) async throws
    func pendingCiphertextIds() async throws -> [UUID]
    func acknowledge(_ id: UUID) async throws
}
// Interface only. No mailbox implementation, storage, offline delivery or UI claim in this phase.
