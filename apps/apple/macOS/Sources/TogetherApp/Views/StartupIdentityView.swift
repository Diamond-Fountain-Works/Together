import SwiftUI
import TogetherCore

struct StartupIdentityView: View {
    let needsMigration: Bool
    let error: String?
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(Copy.text(needsMigration ? "identity.migration.title" : "copy.empty_state.d1dea5d8aa17"), systemImage: "key.fill")
                .font(.title2.weight(.semibold))
            if needsMigration { Text(Copy.text("identity.migration.guidance")).foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.secondary).textSelection(.enabled) }
            Button(Copy.text(needsMigration ? "identity.migration.action" : "identity.action.retry"), action: retry)
                .buttonStyle(.borderedProminent).accessibilityIdentifier("identity.recover")
        }.padding(32).frame(width: 540, alignment: .leading)
    }
}
