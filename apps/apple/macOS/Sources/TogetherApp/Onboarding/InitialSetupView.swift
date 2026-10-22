import SwiftUI
import TogetherCore

struct InitialSetupView: View {
    let model: ApplicationModel
    @State private var step = 0
    @State private var role: RelationshipLabel? = nil
    @State private var name = ""
    @State private var connecting = false
    @State private var cropShown = false
    @TogetherMotionPreference private var reduceMotion
    private let titles = [Copy.text("setup.title.welcome"), Copy.text("setup.title.role"), Copy.text("setup.title.profile"), Copy.text("setup.title.connect"), Copy.text("setup.title.gift")]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { Label(Copy.text("copy.status.330e6de0a0e3"), systemImage: "heart.fill").foregroundStyle(TogetherTheme.rose); Spacer(); Text(Copy.format("copy.status.3a4fb6e6ee20", String(describing: step + 1))).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    content
                }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 490)
            if step < 4 {
                HStack {
                    if step > 0 { Button(Copy.text("copy.action.a57b08a480b8")) { move(-1) } }
                    Spacer()
                    if step == 3 {
                        Button(model.engine.context.peer == nil ? Copy.text("copy.action.0b4fa4b9e083") : Copy.text("copy.action.31fbef162594")) { move(1) }.buttonStyle(.borderedProminent)
                    } else {
                        Button(Copy.text("copy.action.31fbef162594")) { advance() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                            .disabled((step == 1 && role == nil) || (step == 2 && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || model.importingMedia)
                    }
                }
            }
            HStack(spacing: 6) { ForEach(0..<5) { index in Capsule().fill(index <= step ? TogetherTheme.rose : .secondary.opacity(0.15)).frame(height: 3) } }
        }.padding(32).frame(width: 620).tint(TogetherTheme.rose)
        .onAppear { let existing = model.engine.ownProfile?.displayName ?? ""; name = existing == Copy.text("status.profile.self") ? "" : existing }
        .sheet(isPresented: $cropShown) { AvatarCropView(model: model) { cropShown = false } }
    }
    @ViewBuilder private var content: some View {
        switch step {
        case 0:
            VStack(spacing: 22) {
                Image(systemName: "heart.fill").font(.system(size: 68, weight: .ultraLight)).foregroundStyle(TogetherTheme.rose)
                Text(Copy.text("copy.status.937a1f36deff")).font(.system(size: 30, weight: .semibold, design: .rounded))
                Text(Copy.text("copy.guidance.e39e76771c11")).font(.title3).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(.vertical, 55)
        case 1:
            Text(titles[step]).font(.title.weight(.semibold))
            Text(Copy.text("copy.status.1bb474fad984")).foregroundStyle(.secondary)
            ForEach([RelationshipLabel.boyfriend, .girlfriend], id: \.self) { choice in
                Button { withAnimation(TogetherTheme.motion(reduceMotion)) { role = choice } } label: {
                    HStack { Text(choice.displayName).font(.headline); Spacer(); Image(systemName: role == choice ? "checkmark.circle.fill" : "circle") }
                        .padding(20).background(role == choice ? TogetherTheme.rose.opacity(0.12) : .secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }
        case 2:
            Text(titles[step]).font(.title.weight(.semibold))
            HStack(spacing: 22) {
                AvatarView(profile: model.engine.ownProfile, size: 82, engine: model.engine)
                VStack(alignment: .leading, spacing: 10) {
                    Text(LoveCopy.avatarPrompt(partner: model.engine.partnerProfile?.role ?? .unknown)).font(.headline)
                    Text(Copy.text("copy.status.dbfd5d14c799")).foregroundStyle(.secondary)
                    Button(Copy.text("copy.action.7a7ceed76b69")) { model.importAvatar(showCrop: false) }.disabled(model.importingMedia)
                    if model.engine.ownProfile?.avatarAssetId != nil {
                        Button(Copy.text("copy.action.c33392c5ea4a")) { if let id = model.engine.ownProfile?.avatarAssetId { model.cropAsset = model.engine.snapshot.mediaAssets[id]; cropShown = true } }
                    }
                    if model.importingMedia { ProgressView(Copy.text("status.avatar.savingOriginal")).controlSize(.small) }
                }
            }
            TextField(Copy.text("copy.guidance.591976fa354e"), text: $name).textFieldStyle(.roundedBorder)
                .onChange(of: name) { _, value in if value.count > 80 { name = String(value.prefix(80)) } }
        case 3:
            Text(titles[step]).font(.title.weight(.semibold))
            Text(model.engine.context.peer == nil ? Copy.text("copy.guidance.34509ac3c987") : Copy.text("copy.status.854395e0abf2")).foregroundStyle(.secondary)
            Button(Copy.text("copy.action.e3b0859f5da0")) { connecting.toggle() }
            if connecting { ConnectionView(model: model).frame(height: 330) }
        default:
            Text(Copy.text("copy.emotional.acd76b74d637")).font(.title2.weight(.semibold))
            GiftComposerView(model: model, setup: true) { model.finishSetup() }
        }
    }
    private func move(_ amount: Int) { withAnimation(TogetherTheme.motion(reduceMotion)) { step += amount } }
    private func advance() {
        if step == 1, let role {
            model.perform { try model.engine.setProfile(name: model.engine.ownProfile?.displayName ?? Copy.text("status.profile.self"), label: role) }
        }
        if step == 2 {
            do { try model.engine.setProfile(name: name, label: role ?? .unknown) }
            catch { model.errorMessage = Copy.userError(error); return }
        }
        move(1)
    }
}
