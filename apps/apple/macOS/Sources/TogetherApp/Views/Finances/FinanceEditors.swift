import SwiftUI
import TogetherCore

struct FinanceSheetView: View {
    @ObservedObject var model: ApplicationModel
    let sheet: FinanceSheet
    var body: some View {
        switch sheet {
        case .deposit(let id, let opening): ReserveEditor(model: model, id: id, opening: opening)
        case .expense(let id): ExpenseEditor(model: model, id: id)
        case .bill(let id): BillEditor(model: model, id: id)
        case .occurrence(let id, let month): OccurrenceEditor(model: model, billId: id, month: month)
        case .dateEvent(let id): DateEventEditor(model: model, id: id)
        case .settings: FinanceSettingsView(model: model)
        case .card(let id): PaymentCardEditor(model: model, id: id)
        case .changes: FinanceChangeHistoryView(model: model)
        }
    }
}
struct FinanceEditorLayout<Content: View>: View {
    let title: String
    let error: String?
    let save: () -> Void
    let cancel: () -> Void
    var supplementaryActions: AnyView? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            #if os(iOS)
            Text(title).font(.title2.weight(.semibold))
            #else
            Text(title).font(.system(size: 26, weight: .semibold, design: .rounded))
            #endif
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                    if let error { Text(error).foregroundColor(.red).togetherTextSelection().accessibilityIdentifier("finance.editor.error") }
                    #if os(iOS)
                    // Review/delete actions share the form's scroll region;
                    // cancel/save remain outside it and above the keyboard.
                    if let supplementaryActions { supplementaryActions }
                    #endif
                }.padding(.trailing, 4)
            }
            #if os(macOS)
            if let supplementaryActions { supplementaryActions }
            #endif
            Divider()
            HStack { Button(Copy.text("copy.action.2cd0f3be8738"), action: cancel).togetherTouchTarget().keyboardShortcut(.cancelAction).accessibilityIdentifier("sheet.cancel"); Spacer(); Button(Copy.text("copy.action.a3030bf8f16d"), action: save).togetherTouchTarget().togetherProminentButton().keyboardShortcut(.defaultAction).accessibilityIdentifier("finance.save") }
        // Fits the supported 620pt compact content area. Longer fields scroll
        // while the footer remains above the Dock and outside the scroll view.
        }.togetherPadding(28).togetherSheetSize(width: 625, height: 620)
    }
}
struct ReserveEditor: View {
    @ObservedObject var model: ApplicationModel
    let id: UUID?
    let opening: Bool
    @State private var amount: FinanceAmountDraft
    @State private var user: UUID
    @State private var date: Date
    @State private var notes: String
    @State private var error: String?
    @State private var editingBaseline: UnitedReservesLedgerEntry?
    init(model: ApplicationModel, id: UUID?, opening: Bool) {
        self.model = model; self.id = id; self.opening = opening
        let entry = id.flatMap { model.engine.snapshot.finance.reserves[$0] }
        _editingBaseline = State(initialValue: entry)
        _amount = State(initialValue: FinanceAmountDraft(entry?.amount)); _user = State(initialValue: entry?.depositedBy ?? model.engine.identity.descriptor.userId)
        _date = State(initialValue: entry.flatMap { try? FinancialCalendar.instant($0.depositDate, timeZone: model.engine.sharedSpace.timeZoneIdentifier) } ?? model.currentDate)
        _notes = State(initialValue: entry?.notes ?? "")
    }
    var body: some View {
        FinanceEditorLayout(title: Copy.text(opening ? "finance.reserves.opening" : "finance.action.new.reserves"), error: error, save: save, cancel: model.dismissSheet) {
            FinanceAmountFields(draft: $amount)
            if !opening { Picker(Copy.text("finance.deposit.member"), selection: $user) { ForEach(model.engine.context.members.sorted { $0.uuidString < $1.uuidString }, id: \.self) { Text(model.name($0)).tag($0) } } }
            DatePicker(Copy.text("finance.field.date"), selection: $date, displayedComponents: .date).environment(\.timeZone, TimeZone(identifier: model.engine.sharedSpace.timeZoneIdentifier)!)
            TogetherMultilineField(Copy.text("copy.guidance.daede9881787"), text: $notes).textFieldStyle(.roundedBorder)
        }
    }
    private func save() {
        do {
            let value = try amount.amount(), day = CivilDate(date, timeZone: TimeZone(identifier: model.engine.sharedSpace.timeZoneIdentifier)!)
            if opening { try model.engine.setOpeningBalance(value, on: day) }
            else if let id { try model.engine.editDeposit(id, amount: value, by: user, on: day, notes: notes, editingBaseline: editingBaseline) }
            else { _ = try model.engine.deposit(value, by: user, on: day, notes: notes) }
            model.dismissSheet()
        } catch { self.error = Copy.userError(error) }
    }
}
struct ExpenseEditor: View {
    @ObservedObject var model: ApplicationModel
    let id: UUID?
    @State private var title: String
    @State private var amount: FinanceAmountDraft
    @State private var payment: RelativeFinancePayment
    @State private var cardId: UUID?
    @State private var date: Date
    @State private var category: String
    @State private var notes: String
    @State private var eventId: UUID?
    @State private var error: String?
    @State private var editingBaseline: ExpenseEntry?
    init(model: ApplicationModel, id: UUID?) {
        self.model = model; self.id = id; let item = id.flatMap { model.engine.snapshot.finance.expenses[$0] }
        _editingBaseline = State(initialValue: item)
        _title = State(initialValue: item?.title ?? ""); _amount = State(initialValue: .init(item?.amount))
        _payment = State(initialValue: item.map { RelativeFinancePayment($0.payment, me: model.engine.identity.descriptor.userId) } ?? .reserves)
        _cardId = State(initialValue: item?.payment.paymentMethodId)
        _date = State(initialValue: item.flatMap { try? FinancialCalendar.instant($0.occurredOn, timeZone: $0.timeZoneIdentifier) } ?? model.currentDate)
        _category = State(initialValue: item?.category ?? ""); _notes = State(initialValue: item?.notes ?? ""); _eventId = State(initialValue: item?.dateEventId)
    }
    private var existing: ExpenseEntry? { id.flatMap { model.engine.snapshot.finance.expenses[$0] } }
    var body: some View {
        FinanceEditorLayout(title: Copy.text(existing == nil ? "finance.action.new.expenses" : "finance.expenses.edit"), error: error, save: save, cancel: model.dismissSheet, supplementaryActions: existing == nil ? nil : AnyView(reviewActions)) {
            TextField(Copy.text("finance.field.title"), text: $title).textFieldStyle(.roundedBorder).accessibilityIdentifier("finance.expense.title")
            FinanceAmountFields(draft: $amount)
            FinancePaymentFields(model: model, selection: $payment, cardId: $cardId, amount: try? amount.amount())
            DatePicker(Copy.text("finance.field.date"), selection: $date, displayedComponents: .date).environment(\.timeZone, TimeZone(identifier: existing?.timeZoneIdentifier ?? model.engine.sharedSpace.timeZoneIdentifier)!).disabled(existing?.recurringBillId != nil)
            TextField(Copy.text("finance.field.category"), text: $category).textFieldStyle(.roundedBorder)
            Picker(Copy.text("finance.events.title"), selection: $eventId) {
                Text(Copy.text("finance.source.standalone")).tag(Optional<UUID>.none)
                ForEach(model.engine.snapshot.finance.dateEvents.values.filter { $0.deletedAt == nil || $0.id == eventId }.sorted { $0.date > $1.date }) { event in Text(Copy.format("finance.format.detail", event.title, event.date.iso)).tag(Optional(event.id)) }
            }
            TogetherMultilineField(Copy.text("copy.guidance.daede9881787"), text: $notes).textFieldStyle(.roundedBorder)
            if let existing {
                Text(Copy.text("finance.status." + existing.status.rawValue)).font(.caption).foregroundColor(.secondary)
                if existing.recurringBillId != nil { Text(Copy.text("finance.expenses.occurrenceGuidance")).font(.caption).foregroundColor(.secondary) }
            }
        }
    }
    private var reviewActions: some View {
        TogetherAdaptiveStack(spacing: 10, desktop: .init()) {
            if let existing {
                if existing.status == .provisional { Button(Copy.text("finance.review.correct")) { review(.reconciled) }.accessibilityIdentifier("finance.review.correct") }
                Button(Copy.text("finance.review.skipped")) { review(.skipped) }.accessibilityIdentifier("finance.review.skipped")
                #if os(macOS)
                Spacer()
                #endif
                if existing.deletedAt == nil { TogetherRoleButton(Copy.text("copy.action.2f9daa828907"), role: .destructive) { do { try model.engine.deleteFinance(existing.id, type: .expense); model.dismissSheet() } catch { self.error = Copy.userError(error) } }.accessibilityIdentifier("finance.expense.delete") }
            }
        }
    }
    private func review(_ status: ExpenseReviewStatus) {
        do {
            guard let id, let current = existing else { return }
            if status == .reconciled {
                guard try amount.amount() == current.amount, try payment.payment(model: model, cardId: cardId) == current.payment else { throw FinanceError.recordChanged }
            }
            try model.engine.reviewExpense(id, status: status); model.dismissSheet()
        } catch { self.error = Copy.userError(error) }
    }
    private func save() {
        do {
            let value = try amount.amount(), pay = try payment.payment(model: model, cardId: cardId), zone = existing?.timeZoneIdentifier ?? model.engine.sharedSpace.timeZoneIdentifier
            let day = CivilDate(date, timeZone: TimeZone(identifier: zone)!)
            if let id { try model.engine.editExpense(id, title: title, amount: value, payment: pay, on: day, category: category, notes: notes, dateEventId: eventId, reviewed: existing?.status == .provisional && existing?.recurringBillId != nil, editingBaseline: editingBaseline) }
            else { _ = try model.engine.createExpense(title: title, amount: value, payment: pay, on: day, category: category, notes: notes, dateEventId: eventId) }
            model.dismissSheet()
        } catch { self.error = Copy.userError(error) }
    }
}
struct BillEditor: View {
    @ObservedObject var model: ApplicationModel
    let id: UUID?
    @State private var title: String
    @State private var amount: FinanceAmountDraft
    @State private var payment: RelativeFinancePayment
    @State private var cardId: UUID?
    @State private var day: Int
    @State private var zone: String
    @State private var category: String
    @State private var customStart = false
    @State private var start: Date
    @State private var specificTime = false
    @State private var time = Date()
    @State private var error: String?
    @State private var initialAmount: FinanceAmount?
    @State private var initialPayment: FinancePayment?
    @State private var editingBaseline: RecurringBill?
    init(model: ApplicationModel, id: UUID?) {
        self.model = model; self.id = id; let item = id.flatMap { model.engine.snapshot.finance.bills[$0] }
        let future = item.flatMap { try? model.engine.snapshot.finance.occurrence($0, month: FinanceMonth(model.currentDate, timeZone: $0.timeZoneIdentifier).next) }
        _initialAmount = State(initialValue: future?.amount); _initialPayment = State(initialValue: future?.payment); _editingBaseline = State(initialValue: item)
        _title = State(initialValue: item?.title ?? ""); _amount = State(initialValue: .init(future?.amount ?? item?.defaultAmount))
        _payment = State(initialValue: (future?.payment ?? item?.defaultPayment).map { RelativeFinancePayment($0, me: model.engine.identity.descriptor.userId) } ?? .reserves)
        _cardId = State(initialValue: future?.payment.paymentMethodId ?? item?.defaultPayment.paymentMethodId)
        _day = State(initialValue: item?.recurrenceDay ?? 1); _zone = State(initialValue: item?.timeZoneIdentifier ?? model.engine.sharedSpace.timeZoneIdentifier)
        _category = State(initialValue: item?.category ?? ""); _start = State(initialValue: model.currentDate)
    }
    var body: some View {
        FinanceEditorLayout(title: Copy.text(id == nil ? "finance.action.new.bills" : "finance.bill.editDefaults"), error: error, save: save, cancel: model.dismissSheet) {
            TextField(Copy.text("finance.field.title"), text: $title).textFieldStyle(.roundedBorder).accessibilityIdentifier("finance.bill.title")
            FinanceAmountFields(draft: $amount)
            FinancePaymentFields(model: model, selection: $payment, cardId: $cardId, amount: try? amount.amount())
            TextField(Copy.text("finance.field.category"), text: $category).textFieldStyle(.roundedBorder)
            if id == nil {
                HStack { Text(Copy.text("finance.bill.day")); Spacer(); MonthDayWheelPicker(selection: $day) }
                Text(Copy.text("finance.bill.shortMonth")).font(.caption).foregroundColor(.secondary)
                TextField(Copy.text("finance.field.timeZone"), text: $zone).textFieldStyle(.roundedBorder)
                Toggle(Copy.text("finance.bill.customStart"), isOn: $customStart)
                if customStart { DatePicker(Copy.text("finance.bill.startMonth"), selection: $start, displayedComponents: .date).environment(\.timeZone, TimeZone(identifier: zone) ?? .current) }
                Toggle(Copy.text("finance.bill.specificTime"), isOn: $specificTime)
                if specificTime { DatePicker(Copy.text("finance.bill.time"), selection: $time, displayedComponents: .hourAndMinute).environment(\.timeZone, TimeZone(identifier: zone) ?? .current) }
            } else {
                Text(Copy.text("finance.bill.nextMonthGuidance")).font(.callout).foregroundColor(.secondary)
                if let id, let bill = model.engine.snapshot.finance.bills[id] {
                    Text(Copy.format("finance.bill.monthlyDay", String(bill.recurrenceDay))).font(.caption)
                    ForEach(model.engine.snapshot.finance.revisions.values.filter { $0.billId == id && ($0.amount != nil || $0.payment != nil) }.sorted { $0.order > $1.order }) { revision in
                        TogetherAdaptiveStack(spacing: 6, desktop: .init()) { Text(verbatim: revision.effectiveMonth.iso)
                            #if os(macOS)
                            Spacer()
                            #endif
                            if let amount = revision.amount { Text(verbatim: FinanceMoney.display(amount.finalCNYMinor)) }; if let pay = revision.payment { Text(model.financialPaymentName(pay)) } }.font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    private func save() {
        do {
            let value = try amount.amount(), pay = try payment.payment(model: model, cardId: cardId)
            if let id {
                try model.engine.editBillTitle(id, title: title, category: category, editingBaseline: editingBaseline)
                if value != initialAmount || pay != initialPayment { _ = try model.engine.reviseBillDefaults(id, amount: value != initialAmount ? value : nil, payment: pay != initialPayment ? pay : nil) }
            } else {
                let c = try FinancialCalendar.calendar(zone), parts = c.dateComponents([.hour, .minute], from: time)
                _ = try model.engine.createRecurringBill(title: title, amount: value, payment: pay, day: day, timeZone: zone, startMonth: customStart ? FinanceMonth(start, timeZone: zone) : nil, minuteOfDay: specificTime ? (parts.hour! * 60 + parts.minute!) : nil, category: category)
            }
            model.dismissSheet()
        } catch { self.error = Copy.userError(error) }
    }
}
struct OccurrenceEditor: View {
    @ObservedObject var model: ApplicationModel
    let billId: UUID
    let month: FinanceMonth
    @State private var amount: FinanceAmountDraft
    @State private var payment: RelativeFinancePayment
    @State private var cardId: UUID?
    @State private var error: String?
    @State private var editingBaseline: RecurringBillOccurrence?
    init(model: ApplicationModel, billId: UUID, month: FinanceMonth) {
        self.model = model; self.billId = billId; self.month = month
        let bill = model.engine.snapshot.finance.bills[billId], item = bill.flatMap { try? model.engine.snapshot.finance.occurrence($0, month: month) }
        _editingBaseline = State(initialValue: item)
        _amount = State(initialValue: .init(item?.amount)); _payment = State(initialValue: item.map { RelativeFinancePayment($0.payment, me: model.engine.identity.descriptor.userId) } ?? .reserves); _cardId = State(initialValue: item?.payment.paymentMethodId)
    }
    var body: some View {
        FinanceEditorLayout(title: Copy.text("finance.bill.editOccurrence"), error: error, save: {
            do { try model.engine.overrideBillOccurrence(billId, month: month, amount: amount.amount(), payment: payment.payment(model: model, cardId: cardId), editingBaseline: editingBaseline); model.dismissSheet() } catch { self.error = Copy.userError(error) }
        }, cancel: model.dismissSheet) {
            Text(verbatim: model.engine.snapshot.finance.bills[billId]?.title ?? "").font(.headline)
            Text(verbatim: month.iso).foregroundColor(.secondary)
            FinanceAmountFields(draft: $amount); FinancePaymentFields(model: model, selection: $payment, cardId: $cardId, amount: try? amount.amount())
            Text(Copy.text("finance.expenses.occurrenceGuidance")).font(.caption).foregroundColor(.secondary)
        }
    }
}
struct DateEventEditor: View {
    @ObservedObject var model: ApplicationModel
    let id: UUID?
    @State private var title: String
    @State private var date: Date
    @State private var notes: String
    @State private var error: String?
    init(model: ApplicationModel, id: UUID?) {
        self.model = model; self.id = id; let event = id.flatMap { model.engine.snapshot.finance.dateEvents[$0] }
        _title = State(initialValue: event?.title ?? ""); _date = State(initialValue: event.flatMap { try? FinancialCalendar.instant($0.date, timeZone: model.engine.sharedSpace.timeZoneIdentifier) } ?? model.currentDate); _notes = State(initialValue: event?.notes ?? "")
    }
    var body: some View {
        FinanceEditorLayout(title: Copy.text("finance.events.title"), error: error, save: {
            do { let day = CivilDate(date, timeZone: TimeZone(identifier: model.engine.sharedSpace.timeZoneIdentifier)!); if let id { try model.engine.editDateEvent(id, title: title, on: day, notes: notes) } else { _ = try model.engine.createDateEvent(title: title, on: day, notes: notes) }; model.dismissSheet() } catch { self.error = Copy.userError(error) }
        }, cancel: model.dismissSheet) {
            TextField(Copy.text("finance.field.title"), text: $title).textFieldStyle(.roundedBorder)
            DatePicker(Copy.text("finance.field.date"), selection: $date, displayedComponents: .date).environment(\.timeZone, TimeZone(identifier: model.engine.sharedSpace.timeZoneIdentifier)!)
            TogetherMultilineField(Copy.text("copy.guidance.daede9881787"), text: $notes).textFieldStyle(.roundedBorder)
            if let id { TogetherRoleButton(Copy.text("copy.action.2f9daa828907"), role: .destructive) { model.perform { try model.engine.deleteFinance(id, type: .dateEvent); model.dismissSheet() } }; ForEach(model.engine.snapshot.finance.expenses.values.filter { $0.dateEventId == id }) { entry in Text(verbatim: entry.title + " · " + FinanceMoney.display(entry.amount.finalCNYMinor)).font(.callout) } }
        }
    }
}
