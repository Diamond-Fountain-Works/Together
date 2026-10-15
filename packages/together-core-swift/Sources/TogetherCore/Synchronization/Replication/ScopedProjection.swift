import Foundation

/// Reuses the existing projector for independent entity histories and complete
/// dependent domains. No second merge algorithm and no record-level LWW.
public enum ScopedProjection {
  static let basic: Set<EntityType> = [.profile, .task, .recurrenceRule]
  static let wishes: Set<EntityType> = [.wishGrant, .wishItem, .grantAdjustment]
  static let gifts: Set<EntityType> = [.sharedSpace, .mediaAsset, .loveGift]
  public static func replay(
    existing: DomainSnapshot, log: [SignedOperation], additions: [SignedOperation],
    context: ReplicaContext
  ) -> DomainSnapshot {
    var result = existing
    let types = Set(additions.map(\.operation.entityType))
    func replay(_ selected: [SignedOperation]) -> DomainSnapshot {
      let ids = Set(selected.map(\.id))
      result.conflicts.removeAll { ids.contains($0.id) }
      let partial = OperationProjector.replay(selected, context: context)
      result.conflicts += partial.conflicts
      return partial
    }
    if !types.isDisjoint(with: basic) {
      let ids = Set(
        additions.filter { basic.contains($0.operation.entityType) }.map(\.operation.entityId))
      let profiles = types.contains(.profile)
      let selected = log.filter {
        (basic.contains($0.operation.entityType) && ids.contains($0.operation.entityId))
          || (profiles && [.sharedSpace, .mediaAsset].contains($0.operation.entityType))
      }
      let part = replay(selected)
      // The original basic projector shares one UUID namespace across
      // profiles/tasks/rules; include all three when resolving an ID.
      for id in ids {
        result.profiles[id] = part.profiles[id]
        result.tasks[id] = part.tasks[id]
        result.rules[id] = part.rules[id]
      }
    }
    if !types.isDisjoint(with: wishes) {
      let part = replay(log.filter { wishes.contains($0.operation.entityType) })
      result.grants = part.grants
      result.wishes = part.wishes
      result.adjustments = part.adjustments
    }
    if !types.isDisjoint(with: gifts) {
      let part = replay(
        log.filter {
          gifts.contains($0.operation.entityType) || $0.operation.entityType == .profile
        })
      result.space = part.space
      result.mediaAssets = part.mediaAssets
      result.gifts = part.gifts
      result.profiles = part.profiles
    }
    if !types.isDisjoint(with: FinanceProjector.types) {
      result.finance =
        replay(log.filter { FinanceProjector.types.contains($0.operation.entityType) }).finance
    }
    result.conflicts = Array(
      Dictionary(result.conflicts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }).values
    ).sorted { $0.id.uuidString < $1.id.uuidString }
    return result
  }
}
public struct ProjectionCacheRow: Sendable {
  public var key: String
  public var type: String
  public var bytes: Data?
}
public enum ProjectionCacheDelta {
  public static func rows(
    before: DomainSnapshot, after: DomainSnapshot, additions: [SignedOperation]? = nil
  ) throws -> [ProjectionCacheRow] {
    var rows: [ProjectionCacheRow] = []
    let types = additions.map { Set($0.map(\.operation.entityType)) }
    let basicIds = additions.map {
      Set(
        $0.filter { ScopedProjection.basic.contains($0.operation.entityType) }.map(
          \.operation.entityId))
    }
    func selected(_ family: Set<EntityType>) -> Bool {
      types.map { !$0.isDisjoint(with: family) } ?? true
    }
    func collect<T: Encodable & Equatable>(
      _ old: [UUID: T], _ new: [UUID: T], prefix: String, type: String, ids: Set<UUID>? = nil
    ) throws {
      for id in ids ?? Set(old.keys).union(new.keys) where old[id] != new[id] {
        let bytes: Data?
        if let value = new[id] { bytes = try CanonicalJSON.encode(value) } else { bytes = nil }
        rows.append(ProjectionCacheRow(key: prefix + ":" + id.uuidString, type: type, bytes: bytes))
      }
    }
    if selected(ScopedProjection.basic.union(ScopedProjection.gifts)) {
      let profilesAll = selected(ScopedProjection.gifts)
      try collect(
        before.profiles, after.profiles, prefix: "profile", type: "profile",
        ids: profilesAll ? nil : basicIds)
    }
    if selected(ScopedProjection.basic) {
      try collect(before.tasks, after.tasks, prefix: "task", type: "task", ids: basicIds)
      try collect(before.rules, after.rules, prefix: "rule", type: "recurrenceRule", ids: basicIds)
    }
    if selected(ScopedProjection.wishes) {
      try collect(before.grants, after.grants, prefix: "grant", type: "wishGrant")
      try collect(before.wishes, after.wishes, prefix: "wish", type: "wishItem")
      try collect(
        Dictionary(uniqueKeysWithValues: before.adjustments.map { ($0.id, $0) }),
        Dictionary(uniqueKeysWithValues: after.adjustments.map { ($0.id, $0) }),
        prefix: "adjustment", type: "grantAdjustment")
    }
    if selected(ScopedProjection.gifts) {
      try collect(before.mediaAssets, after.mediaAssets, prefix: "media", type: "mediaAsset")
      try collect(before.gifts, after.gifts, prefix: "gift", type: "loveGift")
    }
    if selected(FinanceProjector.types) {
      try collect(
        before.finance.reserves, after.finance.reserves, prefix: "reserve", type: "reserveEntry")
      try collect(
        before.finance.expenses, after.finance.expenses, prefix: "expense", type: "expense")
      try collect(
        before.finance.dateEvents, after.finance.dateEvents, prefix: "dateEvent", type: "dateEvent")
      try collect(before.finance.bills, after.finance.bills, prefix: "bill", type: "recurringBill")
      try collect(
        before.finance.revisions, after.finance.revisions, prefix: "billRevision",
        type: "billRevision")
      try collect(
        before.finance.occurrenceOverrides, after.finance.occurrenceOverrides,
        prefix: "billOccurrence", type: "billOccurrence")
      try collect(
        before.finance.settings, after.finance.settings, prefix: "financeSettings",
        type: "financeSettings")
      try collect(
        before.finance.paymentMethods, after.finance.paymentMethods, prefix: "paymentMethod",
        type: "paymentMethod")
    }
    return rows
  }
}
