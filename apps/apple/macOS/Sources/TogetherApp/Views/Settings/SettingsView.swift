import SwiftUI
import TogetherCore

struct SettingsView: View {
    let model: ApplicationModel
    @State private var name = ""
    @State private var label = RelationshipLabel.unknown
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: Copy.text("copy.navigation.7289f8ec5827"), subtitle: "")
                TogetherCard {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 18) {
                            AvatarView(profile: model.engine.ownProfile, size: 80, engine: model.engine)
                            VStack(alignment: .leading, spacing: 9) {
                                Button(Copy.text("copy.action.b49918dc7f72")) { model.importAvatar() }.disabled(model.importingMedia)
                                if model.engine.ownProfile?.avatarData != nil || model.engine.ownProfile?.avatarAssetId != nil {
                                    Button(Copy.text("copy.action.a91feb645e62")) { model.perform { try model.engine.setAvatar(assetId: nil) } }.buttonStyle(.borderless)
                                }
                                Text(Copy.text("copy.status.af495a06b2de")).font(.caption).foregroundStyle(.secondary)
                                if model.importingMedia { ProgressView().controlSize(.small) }
                            }
                        }
                        TextField(Copy.text("copy.guidance.7a1e2b964b67"), text: $name).textFieldStyle(.roundedBorder)
                        Picker(Copy.text("copy.guidance.3ae0703dd5cd"), selection: $label) { ForEach(RelationshipLabel.allCases, id: \.self) { Text($0.displayName).tag($0) } }.frame(maxWidth: 340)
                        if model.engine.ownProfile?.role == .unknown { Text(Copy.text("copy.guidance.af004a022055")).font(.callout).foregroundStyle(TogetherTheme.rose) }
                        Text(Copy.text("copy.status.cd960931fa8a")).font(.caption).foregroundStyle(.secondary)
                        Button(Copy.text("copy.action.c0a70fcb56f0")) { model.perform { try model.engine.setProfile(name: name, label: label) } }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if let partner = model.engine.partnerProfile {
                    TogetherCard {
                        HStack(spacing: 14) { AvatarView(profile: partner, size: 62, engine: model.engine); VStack(alignment: .leading, spacing: 5) { Text(partner.displayName).font(.headline); Text(partner.role.displayName).foregroundStyle(.secondary); Text(Copy.text("copy.status.bffe51e12e5e")).font(.caption).foregroundStyle(.secondary) }; Spacer() }
                    }
                }
                TogetherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(Copy.text("copy.status.3a7f9c11d059")).font(.headline)
                        Picker(Copy.text("copy.guidance.86a63f23a076"), selection: $appearance) { Text(Copy.text("copy.guidance.217cfe7db1e3")).tag("system"); Text(Copy.text("copy.guidance.dbcd5e7bb7a0")).tag("light"); Text(Copy.text("copy.guidance.60acc53f13a5")).tag("dark") }.pickerStyle(.segmented).frame(maxWidth: 350)
                        Text(Copy.text("copy.guidance.e2ee62dfbb66")).font(.callout).foregroundStyle(.secondary)
                    }
                }
                TogetherCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Copy.text("copy.status.610b105f07da")).font(.headline)
                        Text(Copy.text("copy.guidance.9dd62bb75ce0")).foregroundStyle(.secondary)
                        Text(Copy.text("copy.empty_state.6b4beaf7f321")).font(.caption).foregroundStyle(.secondary)
                        Text(Copy.format("copy.guidance.5e362a89fa84", String(describing: model.version))).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(30)
        }.onAppear { name = model.engine.ownProfile?.displayName ?? Copy.text("status.profile.self"); label = model.engine.ownProfile?.role ?? .unknown }
    }
}
