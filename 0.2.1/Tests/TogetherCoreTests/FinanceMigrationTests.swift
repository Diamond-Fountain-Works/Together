import Foundation
import CryptoKit
import Testing
@testable import TogetherCore

@Suite("0.0.1 to 0.2.1 isolated store upgrade") @MainActor struct FinanceMigrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TOGETHER_LEGACY_FIXTURE"] != nil)) func actualLegacyStoreKeepsIdentityDataAndFinancialRestart() throws {
        let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["TOGETHER_LEGACY_FIXTURE"]))
        let expected = try CanonicalJSON.decode(LegacyExpectation.self, from: Data(contentsOf: root.appendingPathComponent("expected.json")))
        let clock = TestClock(instant("2026-10-09T04:00:00Z")), m = expected.metadata
        let beforeKey = try identityFiles(root.appendingPathComponent("Identity"))
        let identity = try DeviceIdentity.persistent(deviceId: m.deviceId, userId: m.userId, spaceId: m.spaceId, directory: root.appendingPathComponent("Identity"), needsExistingIdentity: true, timeZoneIdentifier: "Asia/Shanghai", protocolVersion: 3)
        #expect(identity.descriptor.publicKey == expected.descriptor.publicKey && identity.descriptor.fingerprint == expected.descriptor.fingerprint)
        #expect(try identityFiles(root.appendingPathComponent("Identity")) == beforeKey)
        let url = root.appendingPathComponent("legacy.store")
        let upgraded = try ReplicaEngine(repository: TogetherRepository(url: url), identity: identity, mediaRoot: root.appendingPathComponent("Media"), dateProvider: clock)
        #expect(upgraded.peer == expected.peer && upgraded.context.spaceId == expected.spaceId)
        #expect(try upgraded.repository.load(RelayBinding.self, key: "relay-binding") == expected.binding)
        #expect(upgraded.snapshot.tasks[expected.taskId]?.title == "LEGACY_TASK_FIXTURE")
        #expect(upgraded.snapshot.tasks[expected.taskId]?.recurrenceRuleId != nil)
        #expect(upgraded.snapshot.balance(for: expected.grantId).remaining == 2)
        #expect(upgraded.snapshot.wishes[expected.wishId]?.status == .fulfilled)
        #expect(upgraded.receivedGifts.map(\.id) == [expected.giftId])
        #expect(upgraded.presentation(expected.giftId).hasAutoPresented)
        #expect(upgraded.presentation(expected.giftId).openedAt != nil)
        #expect(digest(try #require(upgraded.ownProfile?.avatarData)) == expected.avatarHash)
        for signed in upgraded.operations { #expect(try expected.operationHashes[signed.id.uuidString] == digest(CanonicalJSON.encode(signed))) }
        #expect(upgraded.operations.count == expected.operationHashes.count && upgraded.snapshot.finance.expenses.isEmpty)
        let deposit = try upgraded.deposit(FinanceAmount(original: "100", currency: "USD", actualCNY: "701.23"), by: m.userId, on: CivilDate(year: 2026, month: 10, day: 9))
        let expense = try upgraded.createExpense(title: "UPGRADE_FINANCE_FIXTURE", amount: FinanceAmount(original: "70.01"), payment: .init(kind: .equalSplit, userIds: [m.userId, expected.peer.descriptor.userId]), on: CivilDate(year: 2026, month: 10, day: 9))
        var state = try upgraded.financialReviewState(); state.presentedOperationIds.insert(upgraded.operations.last!.id); try upgraded.saveFinancialReviewState(state)
        let privateCard = PaymentMethodProfile(ownerId: m.userId, bankName: "LOCAL_FIXTURE", name: "PRIVATE_FIXTURE", cardKind: .credit, lastFour: "1234")
        try upgraded.savePaymentMethod(privateCard)
        let reopened = try ReplicaEngine(repository: TogetherRepository(url: url), identity: identity, mediaRoot: root.appendingPathComponent("Media"), dateProvider: clock)
        #expect(reopened.snapshot == upgraded.snapshot && reopened.peer == expected.peer)
        #expect(reopened.snapshot.finance.reserves[deposit]?.amount.finalCNYMinor == 70123 && reopened.snapshot.finance.expenses[expense] != nil)
        #expect(try reopened.financialReviewState() == state && reopened.ownPrivatePaymentMethods == [privateCard])
        #expect(try identityFiles(root.appendingPathComponent("Identity")) == beforeKey)
        for signed in reopened.operations where expected.operationHashes[signed.id.uuidString] != nil { #expect(try expected.operationHashes[signed.id.uuidString] == digest(CanonicalJSON.encode(signed))) }
    }
    private func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    private func identityFiles(_ root: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey]) where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true { result[url.lastPathComponent] = digest(try Data(contentsOf: url)) }
        return result
    }
}
private struct LegacyExpectation: Codable {
    let metadata: LocalIdentityMetadata; let descriptor: DeviceDescriptor; let peer: PairedPeer; let binding: RelayBinding; let spaceId: UUID
    let taskId: UUID; let grantId: UUID; let wishId: UUID; let giftId: UUID; let avatarHash: String; let operationHashes: [String: String]
}
