import SwiftUI
import TogetherCore

struct FinanceChangeBanner: View {
    @ObservedObject var model: ApplicationModel
    private var changes: [FinanceChange] { model.financialBannerChanges }
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: TogetherSymbols.name("arrow.triangle.2.circlepath")).foregroundColor(TogetherTheme.rose)
            VStack(alignment: .leading, spacing: 4) {
                let deposits = changes.filter { $0.type == .reserveEntry && $0.action == .create && model.engine.snapshot.finance.reserves[$0.entityId]?.kind == .deposit }
                let depositors = Set(deposits.compactMap { model.engine.snapshot.finance.reserves[$0.entityId]?.depositedBy })
                if deposits.count == changes.count, depositors.count == 1, let total = try? FinanceMoney.sum(deposits.compactMap(\.newCNYMinor)), let user = depositors.first {
                    Text(Copy.format("finance.banner.deposits", model.name(user), FinanceMoney.display(total)))
                } else { Text(Copy.format("finance.banner.changes", String(changes.count))) }
            }
            Spacer()
            Button(Copy.text("copy.action.db8db0530432")) { model.section = .finances; model.financeTab = .reserves; model.showFinance(.changes); model.dismissFinancialBanner() }
            Button { model.dismissFinancialBanner() } label: { Image(systemName: TogetherSymbols.name("xmark")) }.buttonStyle(.plain).accessibilityLabel(Copy.text("copy.action.3fd47edce45b"))
        }.padding(16).togetherMaterialSurface().accessibilityIdentifier("finance.banner")
            .onAppear { model.markFinancialBannerPresented() }.onChange(of: changes.map(\.id)) { _ in model.markFinancialBannerPresented() }
    }
}
struct FinanceReminderList: View {
    @ObservedObject var model: ApplicationModel
    @State private var expanded = false
    @TogetherMotionPreference private var reduceMotion
    private var reminders: [FinanceReminder] {
        let hidden = (try? model.engine.financialReviewState().dismissedReminderIds) ?? []
        return model.financialReminders.filter { !hidden.contains($0.id) }
    }
    var body: some View {
        if !reminders.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
              VStack(alignment: .leading, spacing: 12) {
                ForEach(reminders) { reminder in
                    TogetherCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text(title(reminder)).font(.headline).accessibilityIdentifier("finance.reminder." + reminder.id); Spacer(); Button { model.dismissFinancialReminder(reminder.id) } label: { Image(systemName: TogetherSymbols.name("xmark")) }.buttonStyle(.plain).accessibilityLabel(Copy.text("copy.action.3fd47edce45b")) }
                            HStack {
                                Text(verbatim: reminder.title)
                                Spacer()
                                if let amount = reminder.amount {
                                    if amount.currencyCode != "CNY" { Text(verbatim: FinanceMoney.display(amount.originalMinor, currency: amount.currencyCode)).foregroundColor(.secondary) }
                                    Text(verbatim: FinanceMoney.display(amount.finalCNYMinor))
                                }
                            }
                            if let amount = reminder.amount, let rate = amount.exchangeRate { Text(Copy.format("finance.reminder.rate", rate.cnyPerOriginalUnit, rate.source, rate.quotedOn.iso)).font(.caption).foregroundColor(.secondary) }
                            if let payment = reminder.payment { Text(model.financialPaymentName(payment)).font(.caption).foregroundColor(.secondary) }
                            HStack {
                                if reminder.kind == .reconcile, let expense = reminder.expenseId {
                                    Button(Copy.text("finance.review.correct")) { model.perform { try model.engine.reviewExpense(expense, status: .reconciled) } }.accessibilityIdentifier("finance.reminder.confirm." + expense.uuidString)
                                    Button(Copy.text("finance.review.modify")) { model.showFinance(.expense(expense)) }
                                    Button(Copy.text("finance.review.skipped")) { model.perform { try model.engine.reviewExpense(expense, status: .skipped) } }
                                } else if let id = reminder.billId, let month = reminder.month {
                                    Button(Copy.text("finance.bill.editOccurrence")) { model.showFinance(.occurrence(id, month)) }
                                } else if reminder.kind == .plannedDeposit { Button(Copy.text("finance.action.new.reserves")) { model.showFinance(.deposit(nil, false)) } }
                            }.togetherBorderedButton()
                        }
                    }
                }
              }.padding(.top, 12)
            } label: {
                Text(Copy.format("finance.reminder.count", String(reminders.count))).font(.callout.weight(.medium))
            }.accessibilityIdentifier("finance.reminders")
            .togetherAnimation(TogetherTheme.quickMotion(reduceMotion), value: expanded)
        }
    }
    private func title(_ reminder: FinanceReminder) -> String {
        if reminder.kind == .forecast { return Copy.text("finance.reminder.forecast") }
        if reminder.kind == .plannedDeposit { return Copy.text("finance.reminder.plannedDeposit") }
        let zone = reminder.expenseId.flatMap { model.engine.snapshot.finance.expenses[$0]?.timeZoneIdentifier }.flatMap(TimeZone.init(identifier:)) ?? .current
        let isNextDay = CivilDate(model.currentDate, timeZone: zone) == CivilDate(reminder.scheduledAt, timeZone: zone)
        return Copy.text(isNextDay ? "finance.reminder.review" : "finance.reminder.overdue")
    }
}
struct FinanceChangeHistoryView: View {
    @ObservedObject var model: ApplicationModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(Copy.text("finance.action.changes")).font(.title2.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let changes = model.engine.financialChanges()
                    if changes.isEmpty { TogetherEmptyState(Copy.text("finance.empty.changes"), systemImage: TogetherSymbols.name("clock.arrow.circlepath")) }
                    ForEach(changes) { change in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(model.name(change.actorId)).font(.headline); Spacer(); Text(Copy.date(change.createdAt)).font(.caption).foregroundColor(.secondary) }
                            HStack {
                                Text(Copy.text("finance.change." + change.type.rawValue + "." + change.action.rawValue))
                                if !change.title.isEmpty { Text(verbatim: change.title) }
                                Spacer()
                                if let old = change.oldCNYMinor, let new = change.newCNYMinor, old != new { Text(Copy.format("finance.change.amount", FinanceMoney.display(old), FinanceMoney.display(new))).font(.callout.monospacedDigit()) }
                                else if let value = change.newCNYMinor { Text(verbatim: FinanceMoney.display(value)).font(.callout.monospacedDigit()) }
                            }
                            if change.resolution != .effective {Text(Copy.text("sync.resolution."+change.resolution.rawValue)).font(.caption).foregroundColor(.secondary)}
                            if let month = change.effectiveMonth { Text(Copy.format("finance.change.effective", month.iso)).font(.caption).foregroundColor(.secondary) }
                            if let payment = change.newPayment, payment != change.oldPayment { Text(model.financialPaymentName(payment)).font(.caption).foregroundColor(.secondary) }
                            if let status = change.reviewStatus { Text(Copy.text("finance.status." + status.rawValue)).font(.caption).foregroundColor(.secondary) }
                            if let active = change.active { Text(Copy.text(active ? "finance.status.active" : "finance.status.paused")).font(.caption).foregroundColor(.secondary) }
                            Divider()
                        }.accessibilityIdentifier("finance.change." + change.id.uuidString)
                    }
                }
            }
            HStack { Spacer(); Button(Copy.text("copy.action.3fd47edce45b")) { model.dismissSheet() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("finance.changes.close") }
        }.togetherPadding(28).togetherSheetSize(width: 700, height: 660)
    }
}
