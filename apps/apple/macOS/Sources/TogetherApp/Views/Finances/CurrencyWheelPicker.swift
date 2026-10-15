import SwiftUI
import TogetherCore

struct CurrencyWheelPicker: View {
    @Binding var selection: String
    @State private var expanded = false
    var body: some View {
        Button {
            expanded = true
        } label: {
            HStack { Text(verbatim: (FinanceCurrency.find(selection)?.symbol ?? "") + " " + selection); Image(systemName: "chevron.up.chevron.down").font(.caption) }
        }.accessibilityIdentifier("finance.currency.open")
        .popover(isPresented: $expanded) {
            CurrencyWheelContent(selection: $selection, isPresented: $expanded)
        }
    }
}
struct MonthDayWheelPicker: View {
    @Binding var selection: Int
    @State private var centered: Int?
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(1...31, id: \.self) { day in
                        Button { selection = day; centered = day } label: {
                            Text(day, format: .number).font(.title3.monospacedDigit()).frame(maxWidth: .infinity).frame(height: 32)
                                .background(day == selection ? TogetherTheme.rose.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).id(day).accessibilityIdentifier("finance.day.\(day)")
                    }
                }.scrollTargetLayout().padding(.vertical, 32)
            }.scrollIndicators(.hidden).frame(width: 95, height: 104).scrollTargetBehavior(.viewAligned).scrollPosition(id: $centered, anchor: .center)
                .focusable().onMoveCommand { direction in selection = direction == .up ? max(1, selection - 1) : direction == .down ? min(31, selection + 1) : selection; proxy.scrollTo(selection, anchor: .center) }
                .onAppear { centered = selection; proxy.scrollTo(selection, anchor: .center) }
                .onChange(of: selection) { _, value in
                    if centered != value { centered = value; proxy.scrollTo(value, anchor: .center) }
                }
                .onChange(of: centered) { _, value in if let value { selection = value } }
        }.accessibilityIdentifier("finance.dayWheel")
    }
}
struct FinanceAmountFields: View {
    @Binding var draft: FinanceAmountDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(Copy.text("finance.amount.currency")); Spacer(); CurrencyWheelPicker(selection: Binding(get: { draft.currency }, set: { draft.changeCurrency($0) })) }
            TextField(Copy.text("finance.amount.original"), text: $draft.original).textFieldStyle(.roundedBorder).accessibilityIdentifier("finance.amount.original")
            if draft.currency != "CNY" {
                TextField(Copy.text("finance.amount.actualCNY"), text: $draft.actualCNY).textFieldStyle(.roundedBorder).accessibilityIdentifier("finance.amount.cny")
                DisclosureGroup(Copy.text("finance.amount.referenceRate")) {
                    TextField(Copy.text("finance.amount.rate"), text: $draft.rate).textFieldStyle(.roundedBorder)
                    TextField(Copy.text("finance.amount.source"), text: $draft.rateSource).textFieldStyle(.roundedBorder)
                    DatePicker(Copy.text("finance.amount.rateDate"), selection: $draft.rateDate, displayedComponents: .date).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                    Text(Copy.text("finance.amount.rateGuidance")).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let amount = try? draft.amount() { Text(verbatim: FinanceMoney.display(amount.finalCNYMinor)).font(.title3.monospacedDigit()).accessibilityIdentifier("finance.amount.preview") }
        }
    }
}
struct FinancePaymentFields: View {
    let model: ApplicationModel
    @Binding var selection: RelativeFinancePayment
    @Binding var cardId: UUID?
    let amount: FinanceAmount?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(Copy.text("finance.payment.title"), selection: $selection) {
                ForEach(RelativeFinancePayment.allCases.filter { model.engine.context.peer != nil || ![.partner, .aa].contains($0) }) { Text($0.title).tag($0) }
            }.accessibilityIdentifier("finance.payment.picker")
            if !model.engine.visiblePaymentMethods.isEmpty {
                Picker(Copy.text("finance.cards.title"), selection: $cardId) {
                    Text(Copy.text("finance.cards.none")).tag(Optional<UUID>.none)
                    ForEach(model.engine.visiblePaymentMethods) { card in Text(Copy.format("finance.format.detail", card.name, card.lastFour)).tag(Optional(card.id)) }
                }
            }
            if selection == .aa, let amount, let payment = try? selection.payment(model: model, cardId: cardId) {
                let half = NSDecimalNumber(decimal: Decimal(amount.finalCNYMinor) / 200).stringValue
                Text(Copy.format("finance.aa.formula", FinanceMoney.display(amount.finalCNYMinor), half)).font(.callout.monospacedDigit())
                ForEach(payment.allocations(amount: amount), id: \.userId) { share in HStack { Text(model.name(share.userId)); Spacer(); Text(verbatim: FinanceMoney.display(share.cnyMinor)) } }
                Text(Copy.text("finance.aa.rounding")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
