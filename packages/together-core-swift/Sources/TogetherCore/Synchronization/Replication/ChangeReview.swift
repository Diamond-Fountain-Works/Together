import Foundation

public enum ChangeResolution: String, Codable, Sendable {
  case effective, partiallySuperseded, superseded
}
public enum ChangeOrigin: String, Codable, Sendable { case thisDevice, myOtherDevice, partner }
public enum ChangeReviewDisposition: String, Codable, Sendable { case reviewed, dismissed }
public struct ChangeEvent: Identifiable, Codable, Equatable, Sendable {
  public var id: UUID
  public var entityId: UUID
  public var actorId: UUID
  public var deviceId: UUID
  public var type: EntityType
  public var action: OperationType
  public var order: ChangeOrder
  public var occurredAt: Date
  public var resolution: ChangeResolution = .effective
  public var supersededFields: [String] = []
  public var before: [String: LogValue]
  public var after: [String: LogValue]
  public func origin(local: DeviceDescriptor) -> ChangeOrigin {
    deviceId == local.deviceId ? .thisDevice : actorId == local.userId ? .myOtherDevice : .partner
  }
  public var title: String {
    after["title"]?.string ?? after["displayName"]?.string ?? before["title"]?.string ?? before[
      "displayName"]?.string ?? ""
  }
}
public struct ChangeOrder: Codable, Equatable, Comparable, Sendable {
  public var clock: Int64
  public var device: String
  public var operation: String
  init(_ value: OperationOrder) {
    clock = value.clock
    device = value.device
    operation = value.operation
  }
  public static func < (a: Self, b: Self) -> Bool {
    OperationOrder(clock: a.clock, device: a.device, operation: a.operation)
      < OperationOrder(clock: b.clock, device: b.device, operation: b.operation)
  }
}
public struct ChangeReviewState: Codable, Equatable, Sendable {
  public var presentedOperationIds: Set<UUID> = []
  public var dispositions: [UUID: ChangeReviewDisposition] = [:]
  public init() {}
}

/// An opt-in observer inside the actual deterministic projector. It records
/// only successful state mutations and filters final domain conflicts. It
/// never validates a candidate merely by seeing a syntactically valid payload.
final class ProjectionAudit {
  var events: [UUID: ChangeEvent] = [:]
  func record(_ op: SyncOperation, before: [String: LogValue], after: [String: LogValue]) {
    guard before != after else { return }
    // Media and routing metadata are not user-facing business changes.
    guard ![.mediaAsset, .sharedSpace, .recurrenceRule].contains(op.entityType) else { return }
    let keys = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
    var old: [String: LogValue] = [:]
    var new: [String: LogValue] = [:]
    for key in keys {
      old[key] = before[key] ?? .null
      new[key] = after[key] ?? .null
    }
    // Keep a user-authored label as context without interpreting it as a
    // newly changed field. Gift content is never included in review UI.
    for key in ["title", "displayName"] where new[key] == nil {
      if let value = after[key] ?? before[key] {
        old[key] = value
        new[key] = value
      }
    }
    events[op.id] = ChangeEvent(
      id: op.id, entityId: op.entityId, actorId: op.actorId, deviceId: op.deviceId,
      type: op.entityType, action: op.operationType, order: ChangeOrder(op.order),
      occurredAt: op.createdAt, before: old, after: new)
  }
  func record(_ op: SyncOperation, before: DomainSnapshot, after: DomainSnapshot) {
    record(
      op, before: Self.fields(op.entityType, id: op.entityId, in: before),
      after: Self.fields(op.entityType, id: op.entityId, in: after))
  }
  static func fields(_ type: EntityType, id: UUID, in s: DomainSnapshot) -> [String: LogValue] {
    switch type {
    case .wishGrant:
      guard let v = s.grants[id] else { return [:] }
      return [
        "quantity": .integer(v.quantity), "notes": .string(v.notes),
        "grantedOn": .string(v.grantedOn.iso),
      ]
    case .grantAdjustment:
      guard let v = s.adjustments.first(where: { $0.id == id }), v.isEffective else { return [:] }
      return ["quantity": .integer(v.delta), "notes": .string(v.notes)]
    case .wishItem:
      guard let v = s.wishes[id] else { return [:] }
      return [
        "title": .string(v.title), "description": .string(v.description),
        "status": .string(v.status.rawValue),
      ]
    case .loveGift:
      guard let v = s.gifts[id], v.isEffective else { return [:] }
      return ["sentAt": .date(v.sentAt), "deletedAt": .optionalDate(v.deletedAt)]
    default: return [:]
    }
  }
  func finish(_ snapshot: DomainSnapshot) -> [ChangeEvent] {
    let invalid = Set(snapshot.conflicts.map(\.id))
    let valid = events.values.filter { event in
      guard !invalid.contains(event.id) else { return false }
      switch event.type {
      case .profile: return snapshot.profiles[event.entityId] != nil
      case .task: return snapshot.tasks[event.entityId] != nil
      case .wishGrant: return snapshot.grants[event.entityId] != nil
      case .wishItem:
        return snapshot.wishes[event.entityId]?.status != .conflict
          && snapshot.wishes[event.entityId] != nil
      case .grantAdjustment:
        return snapshot.adjustments.contains { $0.id == event.entityId && $0.isEffective }
      case .loveGift: return snapshot.gifts[event.entityId]?.isEffective == true
      case .reserveEntry: return snapshot.finance.reserves[event.entityId] != nil
      case .expense: return snapshot.finance.expenses[event.entityId] != nil
      case .dateEvent: return snapshot.finance.dateEvents[event.entityId] != nil
      case .recurringBill: return snapshot.finance.bills[event.entityId] != nil
      case .billRevision: return snapshot.finance.revisions[event.entityId] != nil
      case .billOccurrence: return snapshot.finance.occurrenceOverrides[event.entityId] != nil
      case .financeSettings: return snapshot.finance.settings[event.entityId] != nil
      case .paymentMethod: return snapshot.finance.paymentMethods[event.entityId] != nil
      default: return false
      }
    }.sorted { $1.order < $0.order }
    var winners: Set<String> = []
    return valid.map { candidate in
      var event = candidate
      let fields = Set(event.before.keys).union(event.after.keys).filter {
        event.before[$0] != event.after[$0]
      }
      let key = { (field: String) in
        event.type.rawValue + ":" + event.entityId.uuidString + ":" + field
      }
      let replaced = fields.filter { winners.contains(key($0)) }
      if event.action != .create && !replaced.isEmpty {
        event.supersededFields = replaced.sorted()
        event.resolution = replaced.count == fields.count ? .superseded : .partiallySuperseded
      }
      for field in fields { winners.insert(key(field)) }
      return event
    }
  }
}

public actor ChangeReviewService {
  private let repository: TogetherRepository
  private var cached: (revision: UInt64, context: ReplicaContext, events: [ChangeEvent])?
  public init(repository: TogetherRepository) { self.repository = repository }
  public func events(context: ReplicaContext, limit: Int = 200) async throws -> [ChangeEvent] {
    let revision = await repository.operationRevision
    if let cached, cached.revision == revision, cached.context == context {
      return Array(cached.events.prefix(max(0, limit)))
    }
    let log = try await repository.allOperations()
    let events = OperationProjector.changes(log, context: context)
    cached = (revision, context, events)
    return Array(events.prefix(max(0, limit)))
  }
  public func state() async throws -> ChangeReviewState {
    try await repository.load(ChangeReviewState.self, key: "replication4/change-review")
      ?? ChangeReviewState()
  }
  public func pending(context: ReplicaContext, local: DeviceDescriptor) async throws
    -> [ChangeEvent]
  {
    let known = try await state()
    return try await events(context: context, limit: Int.max).filter {
      $0.origin(local: local) != .thisDevice && known.dispositions[$0.id] == nil
        && $0.resolution != .superseded && !known.presentedOperationIds.contains($0.id)
    }
  }
  public func markPresented(_ ids: [UUID]) async throws {
    guard ids.count <= 1000 else { throw ReplicationError.bounds }
    try await repository.updateChangeReview(ids: ids, disposition: nil, presented: true)
  }
  public func mark(_ ids: [UUID], as disposition: ChangeReviewDisposition) async throws {
    guard ids.count <= 1000 else { throw ReplicationError.bounds }
    try await repository.updateChangeReview(ids: ids, disposition: disposition, presented: false)
  }
}

@MainActor extension TogetherRepository {
  func updateChangeReview(ids: [UUID], disposition: ChangeReviewDisposition?, presented: Bool)
    throws
  {
    var state =
      try load(ChangeReviewState.self, key: "replication4/change-review") ?? ChangeReviewState()
    if presented { state.presentedOperationIds.formUnion(ids) }
    if let disposition { for id in ids { state.dispositions[id] = disposition } }
    try save(state, key: "replication4/change-review")
  }
}
