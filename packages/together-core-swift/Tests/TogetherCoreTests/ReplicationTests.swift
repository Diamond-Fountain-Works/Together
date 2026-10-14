import Foundation
import Testing
@testable import TogetherCore

@MainActor final class TwoReplicas {
    let a: ReplicaEngine
    let b: ReplicaEngine
    init(paired: Bool = true) throws {
        let ia = try DeviceIdentity(deviceId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let ib = try DeviceIdentity(deviceId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        a = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity: ia)
        b = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity: ib)
        if paired {
            try a.authorize(PairedPeer(descriptor: ib.descriptor, host: "127.0.0.1", port: 58432))
            try b.authorize(PairedPeer(descriptor: ia.descriptor, host: "127.0.0.1", port: 58431))
            try exchange()
        }
    }
    func exchange() throws {
        for _ in 0..<3 { let left = a.operations; let right = b.operations; try a.merge(right); try b.merge(left) }
    }
}
@Suite("Replication") @MainActor struct ReplicationTests {
    @Test func offlineTasksConverge() throws {
        let p = try TwoReplicas()
        let first = try p.a.createTask(title: "A 离线创建")
        let second = try p.b.createTask(title: "B 离线创建")
        try p.exchange()
        #expect(p.a.snapshot == p.b.snapshot)
        #expect(p.a.snapshot.tasks[first] != nil && p.a.snapshot.tasks[second] != nil)
        let count = p.a.operations.count
        try p.a.merge(p.b.operations + p.b.operations)
        #expect(p.a.operations.count == count)
        #expect(p.a.snapshot.tasks.count == 2)
    }
    @Test func concurrentFieldsAndOrdering() throws {
        let p = try TwoReplicas(); let id = try p.a.createTask(title: "原始")
        try p.exchange()
        try p.a.editTask(id, title: "A 标题", notes: "A 备注", assignedTo: nil, dueAt: nil, recurrence: nil)
        try p.b.editTask(id, title: "B 标题", notes: "B 备注", assignedTo: nil, dueAt: nil, recurrence: nil)
        try p.exchange()
        #expect(p.a.snapshot.tasks[id]?.title == "B 标题")
        #expect(p.a.snapshot == p.b.snapshot)
        let c = p.a.operations.map(\.operation.lamportClock).max()! + 1
        let title = SyncOperation(deviceId: p.a.identity.descriptor.deviceId, actorId: p.a.identity.descriptor.userId, entityId: id, entityType: .task, operationType: .patch, lamportClock: c, payload: ["title": .string("独立标题")])
        let notes = SyncOperation(deviceId: p.b.identity.descriptor.deviceId, actorId: p.b.identity.descriptor.userId, entityId: id, entityType: .task, operationType: .patch, lamportClock: c, payload: ["notes": .string("独立备注")])
        let left = try p.a.identity.sign(title), right = try p.b.identity.sign(notes)
        try p.a.merge([right, left]); try p.b.merge([left, right])
        #expect(p.a.snapshot.tasks[id]?.title == "独立标题")
        #expect(p.a.snapshot.tasks[id]?.notes == "独立备注")
        #expect(p.a.snapshot == p.b.snapshot)
    }
    @Test func tombstoneAndOutOfOrder() throws {
        let p = try TwoReplicas(); let id = try p.a.createTask(title: "将被删除")
        let creation = p.a.operations.last!
        let update = SyncOperation(deviceId: p.a.identity.descriptor.deviceId, actorId: p.a.identity.descriptor.userId, entityId: id, entityType: .task, operationType: .patch, lamportClock: creation.operation.lamportClock + 2, payload: ["title": .string("先到的更新")])
        let signed = try p.a.identity.sign(update)
        try p.b.merge([signed]); #expect(p.b.snapshot.tasks[id] == nil)
        try p.b.merge([creation]); #expect(p.b.snapshot.tasks[id]?.title == "先到的更新")
        try p.a.deleteTask(id)
        try p.exchange()
        #expect(p.a.snapshot.tasks[id]?.deletedAt != nil)
        #expect(p.b.snapshot.tasks[id]?.deletedAt != nil)
    }
    @Test func forgedIdentityAndProfilePermission() throws {
        let p = try TwoReplicas()
        let forged = SyncOperation(deviceId: p.a.identity.descriptor.deviceId, actorId: p.b.identity.descriptor.userId, entityId: p.b.identity.descriptor.userId, entityType: .profile, operationType: .patch, lamportClock: 100, payload: ["displayName": .string("伪造")])
        #expect(throws: (any Error).self) { try p.b.merge([p.a.identity.sign(forged)]) }
        let unauthorized = SyncOperation(deviceId: p.a.identity.descriptor.deviceId, actorId: p.a.identity.descriptor.userId, entityId: p.b.identity.descriptor.userId, entityType: .profile, operationType: .patch, lamportClock: 101, payload: ["displayName": .string("越权修改")])
        try p.b.merge([p.a.identity.sign(unauthorized)])
        #expect(p.b.ownProfile?.displayName == "我")
        #expect(!p.b.snapshot.conflicts.isEmpty)
    }
}
