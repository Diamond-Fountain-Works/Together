import Foundation
import UserNotifications
import TogetherCore

@MainActor enum FinanceNotificationScheduler {
    static func requestPermission() async throws -> Bool { try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    static func schedule(engine: ReplicaEngine, enabled: Bool) async throws {
        #if DEBUG && os(macOS)
        if UIFixture.enabled { return }
        #endif
        let center = UNUserNotificationCenter.current(), pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("together-finance-") }.map(\.identifier))
        guard enabled else { return }
        let reminders = try engine.financeReminders(includeFuture: true)
        for reminder in reminders.prefix(48) where reminder.scheduledAt > engine.dateProvider.now() {
            try Task.checkCancellation()
            let content = UNMutableNotificationContent(); content.title = reminder.title
            let amount = reminder.amount.map { FinanceMoney.display($0.originalMinor, currency: $0.currencyCode) } ?? ""
            content.body = Copy.format(reminder.kind == .forecast ? "finance.notifications.forecast" : "finance.notifications.review", amount)
            content.sound = .default
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone.current
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.scheduledAt); components.timeZone = calendar.timeZone
            let request = UNNotificationRequest(identifier: "together-finance-" + reminder.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try await center.add(request)
        }
    }
}
