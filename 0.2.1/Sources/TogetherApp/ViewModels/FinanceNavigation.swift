import SwiftUI
import TogetherCore

enum FinanceTab: String, CaseIterable, Identifiable {
    case reserves, expenses, bills
    var id: String { rawValue }
    var title: String { Copy.text("finance.tab." + rawValue) }
}
enum FinanceSheet: Identifiable {
    case deposit(UUID?, Bool), expense(UUID?), bill(UUID?), occurrence(UUID, FinanceMonth), dateEvent(UUID?), settings, card(UUID?), changes
    var id: String {
        switch self {
        case .deposit(let id, let opening): "deposit-\(id?.uuidString ?? "new")-\(opening)"
        case .expense(let id): "expense-\(id?.uuidString ?? "new")"
        case .bill(let id): "bill-\(id?.uuidString ?? "new")"
        case .occurrence(let id, let month): "occurrence-\(id)-\(month.iso)"
        case .dateEvent(let id): "dateEvent-\(id?.uuidString ?? "new")"
        case .settings: "financeSettings"
        case .card(let id): "card-\(id?.uuidString ?? "new")"
        case .changes: "financeChanges"
        }
    }
}
enum RelativeFinancePayment: String, CaseIterable, Identifiable {
    case reserves, own, partner, aa
    var id: String { rawValue }
    var title: String { Copy.text("finance.payment." + rawValue) }
    @MainActor func payment(model: ApplicationModel, cardId: UUID?) throws -> FinancePayment {
        let me = model.engine.identity.descriptor.userId
        switch self {
        case .reserves: return .init(kind: .reserves, paymentMethodId: cardId)
        case .own: return .init(kind: .personal, userIds: [me], paymentMethodId: cardId)
        case .partner:
            guard let peer = model.engine.peer else { throw FinanceError.invalidPayment }; return .init(kind: .personal, userIds: [peer.descriptor.userId], paymentMethodId: cardId)
        case .aa:
            guard let peer = model.engine.peer else { throw FinanceError.invalidPayment }; return .init(kind: .equalSplit, userIds: [me, peer.descriptor.userId], paymentMethodId: cardId)
        }
    }
    init(_ payment: FinancePayment, me: UUID) {
        self = payment.kind == .reserves ? .reserves : payment.kind == .equalSplit ? .aa : payment.userIds.contains(me) ? .own : .partner
    }
}
extension ApplicationModel {
    func showFinance(_ value: FinanceSheet) { show(.finance(value)) }
    func financialPaymentName(_ payment: FinancePayment) -> String {
        if payment.kind == .reserves { return Copy.text("finance.payment.reserves") }
        if payment.kind == .equalSplit { return Copy.text("finance.payment.aa") }
        return payment.userIds.first.map(name) ?? Copy.text("status.member.other")
    }
    func refreshFinancialState() {
        perform {
            try engine.reconcileFinanceBills()
            financialReminders = try engine.financeReminders(at: currentDate)
            if lastFinancialOperationCount != engine.operations.count {
                let state = try engine.financialReviewState(), changes = engine.financialChanges(limit: max(150, engine.operations.count))
                let displaying = Set(financialBannerChanges.map(\.id))
                financialBannerChanges = changes.filter { $0.actorId != engine.identity.descriptor.userId && (displaying.contains($0.id) || !state.presentedOperationIds.contains($0.id)) }
                lastFinancialOperationCount = engine.operations.count
            }
            let signature = String(engine.operations.count) + ":" + CivilDate(currentDate).iso + ":" + String(localDefaults.bool(forKey: "financeSystemNotifications"))
            if signature != financialNotificationSignature {
                financialNotificationSignature = signature
                financialNotificationTask?.cancel()
                financialNotificationTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(for: .milliseconds(250))
                        guard let self, !Task.isCancelled else { return }
                        try await FinanceNotificationScheduler.schedule(engine: self.engine, enabled: self.localDefaults.bool(forKey: "financeSystemNotifications"))
                    } catch is CancellationError {} catch { self?.errorMessage = error.localizedDescription }
                }
            }
        }
    }
    func markFinancialBannerPresented() {
        perform {
            var state = try engine.financialReviewState(); state.presentedOperationIds.formUnion(financialBannerChanges.map(\.id)); try engine.saveFinancialReviewState(state)
        }
    }
    func dismissFinancialBanner() { financialBannerChanges = [] }
    func dismissFinancialReminder(_ id: String) {
        perform { var state = try engine.financialReviewState(); state.dismissedReminderIds.insert(id); try engine.saveFinancialReviewState(state) }
        financialReminders.removeAll { $0.id == id }
    }
    var financialRangeOwner: UUID? {
        if financialDateFilter == "personal" { return engine.identity.descriptor.userId }
        if financialDateFilter == "partner" { return engine.peer?.descriptor.userId }
        return nil
    }
    var financialRange: DateInterval? {
        guard financialDateFilter != "all" else { return nil }
        let setting = engine.snapshot.finance.settings(for: financialRangeOwner, fallbackTimeZone: engine.sharedSpace.timeZoneIdentifier)
        if financialDateFilter == "range", let calendar = try? FinancialCalendar.calendar(setting.timeZoneIdentifier),
           let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(financialRangeStart, financialRangeEnd))) {
            return DateInterval(start: calendar.startOfDay(for: min(financialRangeStart, financialRangeEnd)), end: end)
        }
        return try? FinancialCalendar.cycle(containing: currentDate, startDay: setting.cycleStartDay, timeZone: setting.timeZoneIdentifier)
    }
}
