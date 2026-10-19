import Foundation

/// Only the initial inbox and the first startup synchronization can supply automatic gifts.
/// Gifts received during ordinary use remain in the non-interrupting inbox until another launch.
public struct GiftLaunchPolicy: Sendable {
    private var candidates: Set<UUID>
    private var inspectedFirstSync = false
    private var presented = false
    private var userEngaged = false
    private let startupDeadline: Date
    private let clock: any DateProvider
    public init(cachedInboxIds: [UUID], clock: any DateProvider = SystemDateProvider(), startupWindow: TimeInterval = 15) {
        candidates = Set(cachedInboxIds); self.clock = clock; startupDeadline = clock.now().addingTimeInterval(startupWindow)
    }
    public mutating func noteUserInteraction() { userEngaged = true }
    public mutating func noteFirstSync(inboxIds: [UUID]) {
        guard !inspectedFirstSync else { return }; inspectedFirstSync = true
        if !userEngaged && clock.now() <= startupDeadline { candidates.formUnion(inboxIds) }
    }
    public mutating func didPresentAutomatically() { presented = true }
    public var canPresentAutomatically: Bool { !presented && !userEngaged }
    public func pendingIds(inbox: [DailyLoveGift], presentations: [UUID: GiftPresentationState]) -> [UUID] {
        guard canPresentAutomatically else { return [] }
        return inbox.filter { candidates.contains($0.id) && !(presentations[$0.id]?.hasAutoPresented ?? false) && presentations[$0.id]?.openedAt == nil }.map(\.id)
    }
    public func eligible(inbox: [DailyLoveGift], readyIds: Set<UUID>, presentations: [UUID: GiftPresentationState]) -> [UUID] {
        pendingIds(inbox: inbox, presentations: presentations).filter(readyIds.contains)
    }
}
public enum AutomaticModal: Int, CaseIterable, Comparable, Sendable {
    case initialSetup, giftReveal, whatsNew, advisor
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
