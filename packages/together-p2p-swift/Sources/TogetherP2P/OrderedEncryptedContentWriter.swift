import Foundation

/// One native stream's bounded clear-content writer. Both log and media
/// producers enter the same consumer, so cipher sequence allocation and the
/// subsequent stream write cannot be reordered by cross-actor resumptions.
@MainActor final class OrderedEncryptedContentWriter {
    private struct Pending {
        let id = UUID()
        let bytes: Data
        var completion: CheckedContinuation<Void, any Error>?
    }
    private let sealAndSend: @MainActor (Data) async throws -> Void
    private let failed: @MainActor (Error) -> Void
    private var queue: [Pending] = []
    private var bufferedBytes = 0
    private var active: Pending?
    private var worker: Task<Void, Never>?
    private var valid = true

    init(sealAndSend: @escaping @MainActor (Data) async throws -> Void,
         failed: @escaping @MainActor (Error) -> Void) {
        self.sealAndSend = sealAndSend; self.failed = failed
    }
    func send(_ bytes: Data) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { completion in enqueue(bytes, completion: completion) }
    }
    func submit(_ bytes: Data) { enqueue(bytes, completion: nil) }
    private func enqueue(_ bytes: Data, completion: CheckedContinuation<Void, any Error>?) {
        guard valid else { completion?.resume(throwing: CancellationError()); return }
        guard !bytes.isEmpty, bytes.count < 360_000,
              queue.count + (active == nil ? 0 : 1) < 16_384,
              bufferedBytes + bytes.count <= 8_388_608 else {
            completion?.resume(throwing: P2PTransportError.frameBounds)
            invalidate(); failed(P2PTransportError.frameBounds); return
        }
        queue.append(Pending(bytes: bytes, completion: completion)); bufferedBytes += bytes.count
        guard worker == nil else { return }
        worker = Task { @MainActor [weak self] in
            guard let self else { return }
            while valid, !Task.isCancelled, !queue.isEmpty {
                let next = queue.removeFirst(); active = next
                do {
                    try await sealAndSend(next.bytes)
                    guard valid, active?.id == next.id else { return }
                    completeActive(result: .success(()))
                } catch {
                    guard valid, active?.id == next.id else { return }
                    completeActive(result: .failure(error)); invalidate(); failed(error); return
                }
            }
            worker = nil
        }
    }
    private func completeActive(result: Result<Void, any Error>) {
        guard let active else { return }
        self.active = nil; bufferedBytes -= active.bytes.count
        active.completion?.resume(with: result)
    }
    func invalidate() {
        guard valid else { return }; valid = false
        worker?.cancel(); worker = nil
        completeActive(result: .failure(CancellationError()))
        for pending in queue { pending.completion?.resume(throwing: CancellationError()) }
        queue = []; bufferedBytes = 0
    }
}
