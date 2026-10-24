import SwiftUI
import TogetherCore

/// Popover owns its search/layout state so edits invalidate this content,
/// rather than waiting for the presenting button's focus/selection to change.
struct CurrencyWheelContent: View {
    @Binding var selection: String
    @Binding var isPresented: Bool
    @State private var search = ""
    @State private var centered: String?
    private var currencies: [FinanceCurrency] {
        FinanceCurrency.supported.filter { search.isEmpty || $0.code.localizedCaseInsensitiveContains(search) || $0.name.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(spacing: 12) {
            TextField(Copy.text("finance.currency.search"), text: $search).textFieldStyle(.roundedBorder).disableAutocorrection(true).accessibilityIdentifier("finance.currency.search")
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(currencies) { currency in
                            Button { selection = currency.code; isPresented = false } label: {
                                HStack { Text(verbatim: currency.symbol + " " + currency.code); Spacer(); Text(currency.name).foregroundColor(.secondary) }
                                    .padding(.horizontal, 12).frame(height: 42)
                                    .togetherBackground(selection == currency.code ? TogetherTheme.rose.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).id(currency.code).accessibilityIdentifier("finance.currency." + currency.code)
                        }
                    }.togetherScrollTargetLayout().padding(.vertical, 42)
                }.togetherHideScrollIndicators().frame(height: 150)
                .togetherViewAlignedScrolling().togetherScrollPosition(id: $centered, anchor: .center)
                .togetherFocusable().togetherOnMove { direction in
                    guard let index = currencies.firstIndex(where: { $0.code == selection }) else { return }
                    let next = direction == .up ? max(0, index - 1) : direction == .down ? min(currencies.count - 1, index + 1) : index
                    selection = currencies[next].code; centered = selection; proxy.scrollTo(selection, anchor: .center)
                }
                .onAppear { centered = selection; proxy.scrollTo(selection, anchor: .center) }
                .onChange(of: search) { _ in
                    // A stale scroll ID from the full list can hide a filtered
                    // first row. This changes layout, never the selected currency.
                    centered = search.isEmpty ? selection : currencies.first?.code
                }
                .onChange(of: centered) { value in
                    if search.isEmpty, let value, FinanceCurrency.find(value) != nil { selection = value }
                }
            }
            Button(Copy.text("copy.action.c0b3fbff51cc")) { isPresented = false }.keyboardShortcut(.defaultAction)
        }.padding(16).togetherSheetSize(width: 330)
    }
}
