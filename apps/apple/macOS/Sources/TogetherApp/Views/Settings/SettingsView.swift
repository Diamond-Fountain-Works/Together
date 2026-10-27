import SwiftUI
import TogetherCore

struct SettingsView: View {
    @ObservedObject var model: ApplicationModel
    @State private var name = ""
    @State private var label = RelationshipLabel.unknown
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.sizeCategory) private var sizeCategory
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                #if os(macOS)
                HStack {
                    PageHeading(title: Copy.text("copy.navigation.7289f8ec5827"), subtitle: "")
                    Spacer()
                    LanguageMenu()
                }
                #endif
                TogetherCard {
                    VStack(alignment: .leading, spacing: 20) {
                        TogetherAdaptiveStack(spacing: 18) {
                            AvatarView(profile: model.engine.ownProfile, size: 80, engine: model.engine)
                            VStack(alignment: .leading, spacing: 9) {
                                Button(Copy.text("copy.action.b49918dc7f72")) { model.importAvatar() }.disabled(model.importingMedia)
                                if model.engine.ownProfile?.avatarData != nil || model.engine.ownProfile?.avatarAssetId != nil {
                                    Button(Copy.text("copy.action.a91feb645e62")) { model.perform { try model.engine.setAvatar(assetId: nil) } }.buttonStyle(.borderless)
                                }
                                Text(Copy.text("copy.status.af495a06b2de")).font(.caption).foregroundColor(.secondary)
                                if model.importingMedia { ProgressView().controlSize(.small) }
                            }
                        }
                        TextField(Copy.text("copy.guidance.7a1e2b964b67"), text: $name).textFieldStyle(.roundedBorder).accessibilityIdentifier("settings.displayName")
                        Picker(Copy.text("copy.guidance.3ae0703dd5cd"), selection: $label) { ForEach(RelationshipLabel.allCases, id: \.self) { Text($0.displayName).tag($0) } }.frame(maxWidth: 340)
                        if model.engine.ownProfile?.role == .unknown { Text(Copy.text("copy.guidance.af004a022055")).font(.callout).foregroundColor(TogetherTheme.rose) }
                        Button(Copy.text("copy.action.c0a70fcb56f0")) { model.perform { try model.engine.setProfile(name: name, label: label) } }.togetherProminentButton().togetherTouchTarget().disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("settings.saveProfile")
                    }
                }
                if let partner = model.engine.partnerProfile {
                    TogetherCard {
                        HStack(spacing: 14) { AvatarView(profile: partner, size: 62, engine: model.engine); VStack(alignment: .leading, spacing: 5) { Text(partner.displayName).font(.headline); Text(partner.role.displayName).foregroundColor(.secondary); Text(Copy.text("copy.status.bffe51e12e5e")).font(.caption).foregroundColor(.secondary) }; Spacer() }
                    }
                }
                TogetherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(Copy.text("copy.status.3a7f9c11d059")).font(.headline)
                        appearancePicker
                    }
                }
                Text(Copy.format("copy.guidance.5e362a89fa84", model.version)).font(.caption).foregroundColor(.secondary)
            }.togetherPadding(30)
        }.onAppear { name = model.engine.ownProfile?.displayName ?? Copy.text("status.profile.self"); label = model.engine.ownProfile?.role ?? .unknown }
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) { LanguageMenu() }
            #endif
        }
    }
    @ViewBuilder private var appearancePicker: some View {
        #if os(iOS)
        if sizeCategory.isAccessibilityCategory { appearanceOptions.pickerStyle(.menu) }
        else { appearanceOptions.pickerStyle(.segmented) }
        #else
        appearanceOptions.pickerStyle(.segmented).frame(maxWidth: 350)
        #endif
    }
    private var appearanceOptions: some View {
        Picker(Copy.text("copy.guidance.86a63f23a076"), selection: $appearance) {
            Text(Copy.text("copy.guidance.217cfe7db1e3")).tag("system")
            Text(Copy.text("copy.guidance.dbcd5e7bb7a0")).tag("light")
            Text(Copy.text("copy.guidance.60acc53f13a5")).tag("dark")
        }.accessibilityIdentifier("settings.appearance")
    }
}
