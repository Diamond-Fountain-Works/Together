import SwiftUI
import TogetherCore

struct FinanceSettingsView: View {
    @ObservedObject var model: ApplicationModel
    @State private var personal = false
    @State private var sharedDay: Int
    @State private var personalDay: Int
    @State private var sharedZone: String
    @State private var personalZone: String
    @State private var salaryEnabled: Bool
    @State private var salaryDay: Int
    @State private var planEnabled: Bool
    @State private var planDay: Int
    @State private var error: String?
    @State private var systemNotifications = false
    @State private var initialShared: FinanceSettings
    @State private var initialPersonal: FinanceSettings
    init(model: ApplicationModel) {
        self.model = model
        let shared = model.engine.snapshot.finance.settings(for: nil, fallbackTimeZone: model.engine.sharedSpace.timeZoneIdentifier)
        let own = model.engine.snapshot.finance.settings(for: model.engine.identity.descriptor.userId, fallbackTimeZone: model.engine.sharedSpace.timeZoneIdentifier)
        _initialShared = State(initialValue: shared); _initialPersonal = State(initialValue: own)
        _sharedDay = State(initialValue: shared.cycleStartDay); _personalDay = State(initialValue: own.cycleStartDay)
        _sharedZone = State(initialValue: shared.timeZoneIdentifier); _personalZone = State(initialValue: own.timeZoneIdentifier)
        _salaryEnabled = State(initialValue: own.salaryDay != nil); _salaryDay = State(initialValue: own.salaryDay ?? 1)
        _planEnabled = State(initialValue: own.plannedDepositDay != nil); _planDay = State(initialValue: own.plannedDepositDay ?? 1)
        _systemNotifications = State(initialValue: model.localDefaults.bool(forKey: "financeSystemNotifications"))
    }
    var body: some View {
        FinanceEditorLayout(title: Copy.text("finance.action.settings"), error: error, save: save, cancel: model.dismissSheet) {
            Text(Copy.text("finance.cycle.title")).font(.headline)
            Picker(Copy.text("finance.cycle.scope"), selection: $personal) { Text(Copy.text("finance.cycle.shared")).tag(false); Text(Copy.text("finance.cycle.personal")).tag(true) }.pickerStyle(.segmented).accessibilityIdentifier("finance.cycle.scope")
            HStack { Text(Copy.text("finance.cycle.startDay")); Spacer(); MonthDayWheelPicker(selection: personal ? $personalDay : $sharedDay).id(personal) }
            TextField(Copy.text("finance.field.timeZone"), text: personal ? $personalZone : $sharedZone).textFieldStyle(.roundedBorder)
            if (personal ? personalDay : sharedDay) > 28 {
                Text(Copy.text("finance.cycle.guidance")).font(.caption).foregroundColor(.secondary)
            }
            if personal {
                Toggle(Copy.text("finance.cycle.salaryDay"), isOn: $salaryEnabled)
                if salaryEnabled { MonthDayWheelPicker(selection: $salaryDay) }
                Toggle(Copy.text("finance.cycle.depositDay"), isOn: $planEnabled)
                if planEnabled { MonthDayWheelPicker(selection: $planDay) }
            }
            Divider()
            Toggle(Copy.text("finance.notifications.enable"), isOn: $systemNotifications).onChange(of: systemNotifications) { enabled in
                guard enabled else { return }
                Task { do { let allowed = try await FinanceNotificationScheduler.requestPermission(); if !allowed { systemNotifications = false; error = Copy.text("finance.notifications.denied") } } catch { systemNotifications = false; self.error = Copy.userError(error) } }
            }
            HStack { Text(Copy.text("finance.cards.title")).font(.headline); Spacer(); Button(Copy.text("finance.cards.new")) { model.replaceSheet(.finance(.card(nil))) }.accessibilityIdentifier("finance.card.new") }
            ForEach(model.engine.visiblePaymentMethods) { card in
                #if os(macOS)
                HStack { VStack(alignment: .leading) { Text(Copy.format("finance.format.detail", card.name, card.lastFour)); Text(Copy.format("finance.format.detail", card.bankName, model.name(card.holderId))).font(.caption).foregroundColor(.secondary) }; Spacer(); if card.ownerId == model.engine.identity.descriptor.userId { Button(Copy.text("copy.action.051836569928")) { model.replaceSheet(.finance(.card(card.id))) }; TogetherRoleButton(Copy.text("copy.action.2f9daa828907"), role: .destructive) { model.perform { try model.engine.deletePaymentMethod(card.id) } } } }
                #else
                TogetherAdaptiveStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Copy.format("finance.format.detail", card.name, card.lastFour))
                        Text(Copy.format("finance.format.detail", card.bankName, model.name(card.holderId))).font(.caption).foregroundColor(.secondary)
                    }
                    #if os(macOS)
                    Spacer()
                    #endif
                    if card.ownerId == model.engine.identity.descriptor.userId {
                        TogetherAccessibleStack(spacing: 12) {
                            Button(Copy.text("copy.action.051836569928")) { model.replaceSheet(.finance(.card(card.id))) }.togetherTouchTarget()
                            TogetherRoleButton(Copy.text("copy.action.2f9daa828907"), role: .destructive) { model.perform { try model.engine.deletePaymentMethod(card.id) } }.togetherTouchTarget()
                        }
                    }
                }
                #endif
            }
        }
    }
    private func save() {
        do {
            try model.engine.setFinanceSettings(owner: nil, startDay: sharedDay, timeZone: sharedZone, salaryDay: nil, plannedDepositDay: nil, editingBaseline: initialShared)
            try model.engine.setFinanceSettings(owner: model.engine.identity.descriptor.userId, startDay: personalDay, timeZone: personalZone, salaryDay: salaryEnabled ? salaryDay : nil, plannedDepositDay: planEnabled ? planDay : nil, editingBaseline: initialPersonal)
            model.localDefaults.set(systemNotifications, forKey: "financeSystemNotifications")
            model.refreshFinancialState()
            model.dismissSheet()
        } catch { self.error = Copy.userError(error) }
    }
}
struct PaymentCardEditor: View {
    @ObservedObject var model: ApplicationModel
    let id: UUID
    @State private var bank: String
    @State private var name: String
    @State private var holder: UUID
    @State private var kind: PaymentCardKind
    @State private var lastFour: String
    @State private var currency = "CNY"
    @State private var hasCurrency = false
    @State private var shared: Bool
    @State private var error: String?
    init(model: ApplicationModel, id: UUID?) {
        self.model = model; self.id = id ?? UUID()
        let card = id.flatMap { key in model.engine.visiblePaymentMethods.first { $0.id == key } }
        _bank = State(initialValue: card?.bankName ?? ""); _name = State(initialValue: card?.name ?? ""); _holder = State(initialValue: card?.holderId ?? model.engine.identity.descriptor.userId)
        _kind = State(initialValue: card?.cardKind ?? .debit); _lastFour = State(initialValue: card?.lastFour ?? ""); _shared = State(initialValue: card?.isShared ?? false)
        _currency = State(initialValue: card?.currencyCode ?? "CNY"); _hasCurrency = State(initialValue: card?.currencyCode != nil)
    }
    var body: some View {
        FinanceEditorLayout(title: Copy.text("finance.cards.title"), error: error, save: {
            do { try model.engine.savePaymentMethod(PaymentMethodProfile(id: id, ownerId: model.engine.identity.descriptor.userId, holderId: holder, bankName: bank, name: name, cardKind: kind, lastFour: lastFour, currencyCode: hasCurrency ? currency : nil, isShared: shared)); model.dismissSheet() } catch { self.error = Copy.userError(error) }
        }, cancel: model.dismissSheet) {
            TextField(Copy.text("finance.cards.bank"), text: $bank).textFieldStyle(.roundedBorder)
            TextField(Copy.text("finance.cards.name"), text: $name).textFieldStyle(.roundedBorder)
            Picker(Copy.text("finance.cards.holder"), selection: $holder) { ForEach(model.engine.context.members.sorted { $0.uuidString < $1.uuidString }, id: \.self) { Text(model.name($0)).tag($0) } }
            Picker(Copy.text("finance.cards.kind"), selection: $kind) { ForEach(PaymentCardKind.allCases, id: \.self) { Text(Copy.text("finance.cards." + $0.rawValue)).tag($0) } }
            TextField(Copy.text("finance.cards.lastFour"), text: $lastFour).togetherDigitsKeyboard().textFieldStyle(.roundedBorder).accessibilityIdentifier("finance.card.lastFour")
            Toggle(Copy.text("finance.cards.optionalCurrency"), isOn: $hasCurrency)
            if hasCurrency { CurrencyWheelPicker(selection: $currency) }
            Toggle(Copy.text("finance.cards.shared"), isOn: $shared)
            if !shared, model.engine.visiblePaymentMethods.first(where: { $0.id == id })?.isShared == true {
                Text(Copy.text("finance.cards.privacy")).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}
