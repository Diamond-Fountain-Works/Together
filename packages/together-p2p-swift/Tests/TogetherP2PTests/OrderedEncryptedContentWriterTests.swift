import Foundation
import Testing
import TogetherCore
@testable import TogetherP2P

@Suite("Ordered encrypted log and media writer", .timeLimit(.minutes(1))) @MainActor
struct OrderedEncryptedContentWriterTests {
    @Test func mixedConcurrentProducersCannotReorderSealAndStreamWrite() async throws {
        var sequence = 0, active = 0, maximumActive = 0
        var written: [(Int, Data)] = [], errors: [Error] = []
        let writer = OrderedEncryptedContentWriter(sealAndSend: { bytes in
            sequence += 1; let assigned = sequence
            active += 1; maximumActive = max(maximumActive, active)
            // Deliberately suspend after sequence assignment. Separate producer
            // tasks must not be allowed to write the next cipher sequence first.
            if assigned % 2 == 1 { try await CompatibilityClock.sleep(for: .milliseconds(2)) }
            else { await Task.yield() }
            written.append((assigned, bytes)); active -= 1
        }, failed: { errors.append($0) })
        defer { writer.invalidate() }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for n in 1...40 {
                group.addTask {
                    let bytes = Data((n % 2 == 0 ? "synthetic-replication-\(n)" : "synthetic-media-\(n)").utf8)
                    if n % 2 == 0 { try await writer.send(bytes) }
                    else { await writer.submit(bytes) }
                }
            }
            try await group.waitForAll()
        }
        let deadline = CompatibilityClock.now.advanced(by: .seconds(2))
        while written.count != 40, CompatibilityClock.now < deadline { try await CompatibilityClock.sleep(for: .milliseconds(1)) }
        #expect(written.count == 40 && errors.isEmpty)
        #expect(maximumActive == 1)
        #expect(written.map(\.0) == Array(1...40))
        #expect(Set(written.map { String(decoding: $0.1, as: UTF8.self) }).count == 40)
    }
    @Test func invalidateReleasesActiveAndQueuedCallersWithoutWaitingForForeignIO() async throws {
        var held: CheckedContinuation<Void, Never>?
        var errors: [Error] = []
        let writer = OrderedEncryptedContentWriter(sealAndSend: { _ in
            await withCheckedContinuation { held = $0 }
        }, failed: { errors.append($0) })
        let active = Task { try await writer.send(Data("synthetic-active".utf8)) }
        let deadline = CompatibilityClock.now.advanced(by: .seconds(2))
        while held == nil, CompatibilityClock.now < deadline { try await CompatibilityClock.sleep(for: .milliseconds(1)) }
        #expect(held != nil)
        let queued = Task { try await writer.send(Data("synthetic-queued".utf8)) }
        await Task.yield()
        writer.invalidate()
        do { try await active.value; Issue.record("Active caller unexpectedly succeeded") } catch is CancellationError {} catch { Issue.record("Unexpected active cancellation error: \(error)") }
        do { try await queued.value; Issue.record("Queued caller unexpectedly succeeded") } catch is CancellationError {} catch { Issue.record("Unexpected queued cancellation error: \(error)") }
        held?.resume(); held = nil
        #expect(errors.isEmpty)
    }
    @Test func oversizedClearContentFailsBeforeQueueAllocation() async {
        var sends = 0, failures = 0
        let writer = OrderedEncryptedContentWriter(sealAndSend: { _ in sends += 1 }, failed: { _ in failures += 1 })
        await #expect(throws: P2PTransportError.frameBounds) { try await writer.send(Data(repeating: 0, count: 360_000)) }
        #expect(sends == 0 && failures == 1)
        writer.invalidate()
    }
}
