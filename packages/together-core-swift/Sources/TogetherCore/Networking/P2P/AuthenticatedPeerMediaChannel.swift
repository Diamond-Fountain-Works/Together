import Foundation

/// The existing authenticated C1 content envelope and media-only session, shared
/// with native App transport. No business facts or ACKs enter the legacy log path.
@MainActor public final class AuthenticatedPeerMediaChannel {
    public var onError: ((Error) -> Void)?
    private let media: OperationLogSyncSession

    public init(engine: ReplicaEngine, remote: DeviceDescriptor,
                send: @escaping @MainActor (Data) -> Void) throws {
        guard engine.usesReplication4, engine.isAuthorizedRemote(remote) else { throw ReplicationError.unauthorized }
        media = OperationLogSyncSession(engine: engine, remote: remote, mediaOnly: true, send: { _ in })
        media.send = { [weak self] payload in
            do { send(try CanonicalJSON.encode(C1Content.media(payload))) }
            catch { self?.onError?(error) }
        }
        media.onError = { [weak self] error in self?.onError?(error) }
    }

    nonisolated public static func encodeReplication(_ frame: ReplicationFrame) throws -> Data {
        try CanonicalJSON.encode(C1Content.replication(frame))
    }

    /// Returns the existing replication frame, or processes an existing media
    /// payload. Caller must authenticate the transport cipher before this method.
    public func receive(_ bytes: Data) throws -> ReplicationFrame? {
        guard bytes.count <= FrameDecoder.maximum else { throw ReplicationError.bounds }
        switch try CanonicalJSON.decode(C1Content.self, from: bytes) {
        case .replication(let frame): return frame
        case .media(let payload): try media.receive(payload); return nil
        }
    }

    public func synchronize() throws { try media.synchronizeMedia() }
    public func invalidate() { media.invalidate() }
}
