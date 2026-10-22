import SwiftUI
import TogetherCore

struct OurFinancesView: View {
    @Bindable var model: ApplicationModel
    @TogetherMotionPreference private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ViewThatFits(in: .horizontal) {
                HStack { PageHeading(title: Copy.text("finance.title"), subtitle: ""); Spacer(minLength: 20); tabs.frame(width: 405) }
                VStack(alignment: .leading, spacing: 16) { PageHeading(title: Copy.text("finance.title"), subtitle: ""); tabs }
            }.padding(.horizontal, 30).padding(.top, 30)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    FinanceReminderList(model: model)
                    switch model.financeTab {
                    case .reserves: UnitedReservesView(model: model)
                    case .expenses: ExpensesView(model: model)
                    case .bills: RecurringBillsView(model: model)
                    }
                }.padding(.horizontal, 30).padding(.bottom, 30)
            }.id(model.financeTab).transition(.opacity)
        }.animation(TogetherTheme.standardMotion(reduceMotion), value: model.financeTab)
        #if DEBUG
        .background(FixtureFinanceCaptureAnchor())
        #endif
    }
    private var tabs: some View {
        Picker(Copy.text("finance.title"), selection: $model.financeTab) {
            ForEach(FinanceTab.allCases) { Text($0.title).tag($0).accessibilityIdentifier("finance.tab." + $0.rawValue) }
        }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("finance.tabs")
    }
}
struct FinanceStat: View {
    let title: String
    let value: Int64
    var body: some View {
        VStack(alignment: .leading, spacing: 9) { Text(title).font(.caption).foregroundStyle(.secondary).frame(minHeight: 30, alignment: .bottomLeading); Text(verbatim: FinanceMoney.display(value)).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(value < 0 ? .red : .primary).minimumScaleFactor(0.65).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct UnitedReservesView: View {
    let model: ApplicationModel
    private var entries: [UnitedReservesLedgerEntry] { model.engine.snapshot.finance.reserves.values.sorted { $0.depositDate == $1.depositDate ? $0.id.uuidString < $1.id.uuidString : $0.depositDate > $1.depositDate } }
    private var stats: FinanceStatistics? { try? model.engine.snapshot.finance.statistics() }
    var body: some View {
        if let stats {
            TogetherCard { HStack(spacing: 22) { FinanceStat(title: Copy.text("finance.balance.book"), value: stats.bookBalance); FinanceStat(title: Copy.text("finance.balance.verified"), value: stats.verifiedBalance); FinanceStat(title: Copy.text("finance.balance.provisional"), value: stats.provisionalReservesAmount) } }.accessibilityIdentifier("finance.balance")
        }
        FinanceCycleSummary(model: model)
        HStack { Text(Copy.text("finance.reserves.history")).font(.headline); Spacer(); Button(Copy.text("finance.reserves.opening")) { model.showFinance(.deposit(StableID.make("finance-reserves-opening"), true)) }.accessibilityIdentifier("finance.opening") }
        if entries.isEmpty { ContentUnavailableView(Copy.text("finance.empty.reserves"), systemImage: "tray").accessibilityIdentifier("finance.empty") }
        ForEach(entries) { entry in
            TogetherCard {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) { Text(entry.kind == .opening ? Copy.text("finance.reserves.opening") : model.name(entry.depositedBy)).font(.headline); Text(verbatim: entry.depositDate.iso).font(.caption).foregroundStyle(.secondary); if !entry.notes.isEmpty { Text(verbatim: entry.notes).font(.callout).foregroundStyle(.secondary) } }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(verbatim: FinanceMoney.display(entry.amount.finalCNYMinor)).font(.title3.monospacedDigit())
                        if entry.amount.currencyCode != "CNY" {
                            Text(verbatim: FinanceMoney.display(entry.amount.originalMinor, currency: entry.amount.currencyCode)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if entry.deletedAt != nil { Text(Copy.text("finance.status.revoked")).font(.caption).foregroundStyle(.secondary) }
                    else { Menu { Button(Copy.text("copy.action.051836569928")) { model.showFinance(.deposit(entry.id, entry.kind == .opening)) }; if entry.kind != .opening { Button(Copy.text("copy.action.926a50b98ece"), role: .destructive) { model.perform { try model.engine.deleteFinance(entry.id, type: .reserveEntry) } } } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize() }
                }
            }.opacity(entry.deletedAt == nil ? 1 : 0.6).accessibilityIdentifier("finance.deposit." + entry.id.uuidString)
        }
        let shared = model.engine.snapshot.finance.expenses.values.filter { $0.isEffective && $0.payment.kind == .reserves }.sorted { $0.occurredOn > $1.occurredOn }
        if !shared.isEmpty {
            HStack {
                Text(Copy.text("finance.reserves.spending")).font(.headline)
                Spacer()
                Button(Copy.text("finance.action.allExpenses")) {
                    model.financeTab = .expenses
                    model.financialPaymentFilter = "reserves"
                }
            }
            ForEach(Array(shared.prefix(4))) { expense in FinanceExpenseRow(model: model, expense: expense) }
        }
    }
}
struct FinanceCycleSummary: View {
    let model: ApplicationModel
    var ownerId: UUID? = nil
    var body: some View {
        let setting = model.engine.snapshot.finance.settings(for: ownerId, fallbackTimeZone: model.engine.sharedSpace.timeZoneIdentifier)
        if let period = try? FinancialCalendar.cycle(containing: model.currentDate, startDay: setting.cycleStartDay, timeZone: setting.timeZoneIdentifier), let stats = try? model.engine.snapshot.finance.statistics(in: period, timeZone: setting.timeZoneIdentifier) {
            let deposits = ownerId.map { user in (try? FinanceMoney.sum(model.engine.snapshot.finance.reserves.values.filter { $0.deletedAt == nil && $0.depositedBy == user && ((try? FinancialCalendar.instant($0.depositDate, timeZone: setting.timeZoneIdentifier)).map { period.contains($0) && $0 < period.end } ?? false) }.map { $0.amount.finalCNYMinor })) ?? 0 } ?? stats.deposited
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(ownerId.map(model.name) ?? Copy.text("finance.cycle.current")).foregroundStyle(.secondary); Spacer(); Text(Copy.format("finance.format.period", CivilDate(period.start, timeZone: TimeZone(identifier: setting.timeZoneIdentifier)!).iso, CivilDate(period.end.addingTimeInterval(-1), timeZone: TimeZone(identifier: setting.timeZoneIdentifier)!).iso)).font(.caption.monospaced()) }
                Text(Copy.format("finance.cycle.summary", FinanceMoney.display(deposits), FinanceMoney.display(ownerId.map { stats.personal[$0] ?? 0 } ?? stats.totalExpenses))).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
struct ExpensesView: View {
    @Bindable var model: ApplicationModel
    private var entries: [ExpenseEntry] {
        model.engine.snapshot.finance.expenses.values.filter { entry in
            let payment = model.financialPaymentFilter
            let mine = model.engine.identity.descriptor.userId
            let paid = payment == "all" || payment == "reserves" && entry.payment.kind == .reserves || payment == "aa" && entry.payment.kind == .equalSplit || payment == "own" && entry.payment.kind == .personal && entry.payment.userIds.contains(mine) || payment == "partner" && entry.payment.kind == .personal && !entry.payment.userIds.contains(mine)
            let source = model.financialSourceFilter
            let sourced = source == "all" || source == "bill" && entry.recurringBillId != nil || source == "date" && entry.dateEventId != nil || source == "standalone" && entry.recurringBillId == nil && entry.dateEventId == nil
            let inDate = model.financialRange.map { period in (try? FinancialCalendar.instant(entry.occurredOn, timeZone: entry.timeZoneIdentifier)).map { $0 >= period.start && $0 < period.end } ?? false } ?? true
            return paid && sourced && inDate && (model.financialCategoryFilter == "all" || entry.category == model.financialCategoryFilter) && (model.financialStatusFilter == "all" || entry.status.rawValue == model.financialStatusFilter) && (model.financialExpenseSearch.isEmpty || entry.title.localizedCaseInsensitiveContains(model.financialExpenseSearch) || entry.category.localizedCaseInsensitiveContains(model.financialExpenseSearch))
        }.sorted { $0.occurredOn == $1.occurredOn ? $0.id.uuidString < $1.id.uuidString : $0.occurredOn > $1.occurredOn }
    }
    var body: some View {
        let stats = filteredStatistics
        if let stats {
            TogetherCard { HStack(spacing: 18) { FinanceStat(title: Copy.text("finance.expenses.total"), value: stats.totalExpenses); ForEach(model.engine.context.members.sorted { $0.uuidString < $1.uuidString }, id: \.self) { user in FinanceStat(title: model.name(user) + " · " + (model.engine.snapshot.profiles[user]?.role.displayName ?? Copy.text("status.member.other")), value: stats.personal[user] ?? 0) }; FinanceStat(title: Copy.text("finance.payment.reserves"), value: stats.reservesSpent) } }
            if !stats.categories.isEmpty { LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)], alignment: .leading) { ForEach(stats.categories.keys.sorted(), id: \.self) { category in Text(Copy.format("finance.format.detail", category.isEmpty ? Copy.text("finance.category.none") : category, FinanceMoney.display(stats.categories[category] ?? 0))).font(.caption).foregroundStyle(.secondary) } } }
        }
        FinanceCycleSummary(model: model)
        if model.financialDateFilter == "personal" || model.financialDateFilter == "partner" { FinanceCycleSummary(model: model, ownerId: model.financialRangeOwner) }
        HStack {
            Picker(Copy.text("finance.payment.title"), selection: $model.financialPaymentFilter) { Text(Copy.text("finance.filter.all")).tag("all"); ForEach(RelativeFinancePayment.allCases) { Text($0.title).tag($0.rawValue) } }.frame(maxWidth: 220)
            Picker(Copy.text("finance.filter.source"), selection: $model.financialSourceFilter) { ForEach(["all", "standalone", "date", "bill"], id: \.self) { Text(Copy.text("finance.source." + $0)).tag($0) } }.frame(maxWidth: 170)
            Picker(Copy.text("finance.filter.status"), selection: $model.financialStatusFilter) { Text(Copy.text("finance.filter.all")).tag("all"); ForEach(ExpenseReviewStatus.allCases, id: \.self) { Text(Copy.text("finance.status." + $0.rawValue)).tag($0.rawValue) } }.frame(maxWidth: 150)
        }
        HStack {
            Picker(Copy.text("finance.filter.period"), selection: $model.financialDateFilter) { ForEach(["all", "shared", "personal", "partner", "range"].filter { model.engine.context.peer != nil || $0 != "partner" }, id: \.self) { Text(Copy.text("finance.period." + $0)).tag($0) } }.accessibilityIdentifier("finance.period")
            Picker(Copy.text("finance.field.category"), selection: $model.financialCategoryFilter) { Text(Copy.text("finance.filter.all")).tag("all"); ForEach(Set(model.engine.snapshot.finance.expenses.values.map(\.category)).sorted(), id: \.self) { category in Text(category.isEmpty ? Copy.text("finance.category.none") : category).tag(category) } }
        }
        if model.financialDateFilter == "range" { HStack { DatePicker(Copy.text("finance.period.from"), selection: $model.financialRangeStart, displayedComponents: .date); DatePicker(Copy.text("finance.period.to"), selection: $model.financialRangeEnd, displayedComponents: .date) }.environment(\.timeZone, TimeZone(identifier: model.engine.sharedSpace.timeZoneIdentifier)!) }
        HStack { TextField(Copy.text("finance.expenses.search"), text: $model.financialExpenseSearch).textFieldStyle(.roundedBorder).frame(maxWidth: 300); Spacer(); Menu(Copy.text("finance.events.title")) { Button(Copy.text("finance.events.new")) { model.showFinance(.dateEvent(nil)) }; ForEach(model.engine.snapshot.finance.dateEvents.values.filter { $0.deletedAt == nil }.sorted { $0.date > $1.date }) { event in Button { model.showFinance(.dateEvent(event.id)) } label: { Text(Copy.format("finance.format.detail", event.title, event.date.iso)) } } } }
        if entries.isEmpty { ContentUnavailableView(Copy.text("finance.empty.expenses"), systemImage: "list.bullet.rectangle").accessibilityIdentifier("finance.empty") }
        ForEach(entries) { entry in FinanceExpenseRow(model: model, expense: entry) }
    }
    private var filteredStatistics: FinanceStatistics? {
        var finance = model.engine.snapshot.finance
        finance.expenses = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        return try? finance.statistics()
    }
}
struct FinanceExpenseRow: View {
    let model: ApplicationModel
    let expense: ExpenseEntry
    var body: some View {
        TogetherCard {
            HStack(spacing: 16) {
                Button { model.showFinance(.expense(expense.id)) } label: {
                    VStack(alignment: .leading, spacing: 6) { Text(verbatim: expense.title).font(.headline); HStack { Text(verbatim: expense.occurredOn.iso); Text(model.financialPaymentName(expense.payment)); if !expense.category.isEmpty { Text(verbatim: expense.category) } }.font(.caption).foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("finance.expense.open." + expense.id.uuidString)
                VStack(alignment: .trailing, spacing: 5) { Text(verbatim: FinanceMoney.display(expense.amount.finalCNYMinor)).font(.title3.monospacedDigit()); Text(Copy.text(expense.deletedAt != nil ? "finance.status.deleted" : "finance.status." + expense.status.rawValue)).font(.caption).foregroundStyle(.secondary) }
            }
        }.opacity(expense.isEffective ? 1 : 0.55)
    }
}
struct RecurringBillsView: View {
    let model: ApplicationModel
    private var bills: [RecurringBill] { model.engine.snapshot.finance.bills.values.sorted { $0.id.uuidString < $1.id.uuidString } }
    var body: some View {
        if bills.isEmpty { ContentUnavailableView(Copy.text("finance.empty.bills"), systemImage: "calendar.badge.clock").accessibilityIdentifier("finance.empty") }
        ForEach(bills) { bill in
            let active = model.engine.snapshot.finance.isActive(bill, at: model.currentDate)
            TogetherCard {
                HStack(spacing: 18) {
                    Button { model.showFinance(.bill(bill.id)) } label: {
                        VStack(alignment: .leading, spacing: 8) { Text(verbatim: bill.title).font(.headline); Text(Copy.format("finance.bill.monthlyDay", String(bill.recurrenceDay))).font(.caption).foregroundStyle(.secondary); Text(verbatim: bill.timeZoneIdentifier).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("finance.bill.open." + bill.id.uuidString)
                    if let next = nextOccurrence(bill) { VStack(alignment: .trailing, spacing: 6) { Text(verbatim: FinanceMoney.display(next.amount.originalMinor, currency: next.amount.currencyCode)).font(.title3.monospacedDigit()); Text(verbatim: next.date.iso).font(.caption).foregroundStyle(.secondary) } }
                    Text(Copy.text(bill.deletedAt != nil ? "finance.status.terminated" : active ? "finance.status.active" : "finance.status.paused")).font(.caption).foregroundStyle(.secondary)
                    if bill.deletedAt == nil { Menu { Button(Copy.text(active ? "finance.bill.pause" : "finance.bill.resume")) { model.perform { try model.engine.setBillActive(bill.id, active: !active) } }; Button(Copy.text("finance.bill.terminate"), role: .destructive) { model.perform { try model.engine.deleteFinance(bill.id, type: .recurringBill) } } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize() }
                }
            }.opacity(active ? 1 : 0.65)
        }
    }
    private func nextOccurrence(_ bill: RecurringBill) -> RecurringBillOccurrence? {
        var month = FinanceMonth(model.currentDate, timeZone: bill.timeZoneIdentifier)
        for _ in 0..<24 {
            if let value = try? model.engine.snapshot.finance.occurrence(bill, month: month), value.isActive, let date = try? FinancialCalendar.instant(value.date, timeZone: bill.timeZoneIdentifier, minuteOfDay: bill.minuteOfDay), date >= model.currentDate { return value }
            month = month.next
        }
        return nil
    }
}
