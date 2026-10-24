import SwiftUI
import TogetherCore

struct StartupIdentityView: View {
    let needsMigration: Bool
    let error: String?
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(Copy.text(needsMigration ? "identity.migration.title" : "copy.empty_state.d1dea5d8aa17"), systemImage: TogetherSymbols.name("key.fill"))
                .font(.title2.weight(.semibold))
            if needsMigration { Text(Copy.text("identity.migration.guidance")).foregroundColor(.secondary) }
            if let error { Text(error).foregroundColor(.secondary).togetherTextSelection() }
            Button(Copy.text(needsMigration ? "identity.migration.action" : "identity.action.retry"), action: retry)
                .togetherProminentButton().accessibilityIdentifier("identity.recover")
        }.togetherPadding(32).togetherSheetSize(width: 540)
    }
}
