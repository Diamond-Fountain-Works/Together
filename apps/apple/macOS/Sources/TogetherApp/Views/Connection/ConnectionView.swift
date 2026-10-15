import SwiftUI
import TogetherCore
import AppKit

struct ConnectionView: View {
    let model: ApplicationModel
    @State private var invitation = ""
    @State private var verified = false
    @State private var showSuccess = false
    @TogetherMotionPreference private var reduceMotion
    @Namespace private var pairGeometry
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: Copy.text("nav.connection"), subtitle: "")
                HStack { Circle().fill(model.network.isOnline ? .green : .secondary).frame(width: 7, height: 7); Text(model.network.state.displayName).font(.callout); Spacer() }
                    .accessibilityIdentifier("connection.state")
                if let error = model.network.errorMessage { Text(error).foregroundStyle(.orange).accessibilityIdentifier("connection.error") }
                if !model.network.isConfigured {
                    Text(Copy.text("copy.guidance.4d93993d5b23")).font(.callout).foregroundStyle(.secondary)
                } else if let proposal = model.network.proposal {
                    TogetherCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(Copy.text("copy.action.2fd9629c1a44")).font(.headline)
                            HStack(spacing: 14) {
                                AvatarView(profile: model.engine.peer?.descriptor.deviceId == proposal.deviceId ? model.engine.partnerProfile : nil, size: 54, engine: model.engine)
                                Text(proposal.name).font(.title3.weight(.semibold))
                            }
                            Text(verbatim: proposal.verificationCode).font(.system(size: 30, weight: .semibold, design: .monospaced)).accessibilityIdentifier("pairing.verificationCode")
                            Text(Copy.text("copy.status.3ebca10fcb10")).font(.callout).foregroundStyle(.secondary)
                            Text(verbatim: proposal.fingerprint).font(.caption.monospaced()).textSelection(.enabled)
                            Toggle(Copy.text("copy.guidance.9132a75101e9"), isOn: $verified).accessibilityIdentifier("pairing.verified")
                            HStack {
                                Button(Copy.text("copy.action.2cd0f3be8738")) { model.network.rejectPairing(); verified = false }.accessibilityIdentifier("pairing.cancel")
                                Spacer()
                                Button(Copy.text("copy.action.2fd9629c1a44")) { Task { await model.network.confirmPairing() } }.buttonStyle(.borderedProminent).disabled(!verified || model.network.busy).accessibilityIdentifier("pairing.confirm")
                            }
                        }
                    }
                } else if model.engine.context.peer == nil || model.network.needsMigration {
                    if model.network.needsMigration { Text(Copy.text("copy.guidance.0c2e0cb3cd53")).font(.callout).foregroundStyle(.secondary) }
                    TogetherCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Button(Copy.text("copy.action.1032f5e75333")) { Task { await model.network.createInvitation() } }.buttonStyle(.borderedProminent).disabled(model.network.busy).accessibilityIdentifier("pairing.createInvite")
                            if let code = model.network.invitationCode {
                                Text(verbatim: code).font(.system(size: 28, weight: .semibold, design: .monospaced)).textSelection(.enabled).accessibilityIdentifier("pairing.invitationCode")
                                if let expires = model.network.invitationExpiresAt { Text(expires, style: .time).font(.caption).foregroundStyle(.secondary) }
                                Button(Copy.text("copy.action.52c229c10699")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) }.accessibilityIdentifier("pairing.copyInvite")
                            }
                            Divider()
                            TextField(Copy.text("copy.guidance.c8b56dca7aed"), text: $invitation).textFieldStyle(.roundedBorder).frame(maxWidth: 300).accessibilityIdentifier("pairing.codeInput")
                            Button(Copy.text("copy.action.d8392ef9f3fb")) { Task { await model.network.joinInvitation(invitation) } }.disabled(invitation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.network.busy).accessibilityIdentifier("pairing.joinInvite")
                        }
                    }
                } else {
                    TogetherCard {
                        HStack(spacing: 18) {
                            AvatarView(profile: model.engine.ownProfile, size: 54, engine: model.engine).matchedGeometryEffect(id: "self", in: pairGeometry)
                            if showSuccess { Image(systemName: "heart.fill").foregroundStyle(TogetherTheme.rose); Text(Copy.text("copy.status.15a314eb8b4d")).font(.headline) }
                            AvatarView(profile: model.engine.partnerProfile, size: 54, engine: model.engine).matchedGeometryEffect(id: "partner", in: pairGeometry)
                            Spacer()
                            Button(Copy.text("copy.action.68891ab35cab")) { model.network.reconnect() }.disabled(model.network.busy).accessibilityIdentifier("connection.reconnect")
                            Button(Copy.text("copy.action.dcfe516d1114")) { model.network.synchronize() }.disabled(!model.network.isOnline).accessibilityIdentifier("connection.sync")
                        }
                    }
                }
                if model.network.busy { ProgressView().controlSize(.small) }
                if !model.engine.mediaProgress.isEmpty {
                    TogetherCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(Copy.text("copy.status.1c39d7d54b8f")).font(.headline)
                            ForEach(model.engine.mediaProgress.values.sorted { $0.assetId.uuidString < $1.assetId.uuidString }, id: \.assetId) { progress in
                                Text(model.engine.mediaAsset(progress.assetId)?.originalFilename ?? Copy.text("copy.status.c7225dbf105e")).font(.callout).lineLimit(1)
                                ProgressView(value: progress.fraction)
                                Text(progress.status.displayName).font(.caption).foregroundStyle(.secondary)
                                if let error = progress.error { Text(error).font(.caption).foregroundStyle(.orange) }
                            }
                        }
                    }
                }
                if !model.engine.snapshot.conflicts.isEmpty { ForEach(model.engine.snapshot.conflicts) { Text($0.reason).font(.caption).foregroundStyle(.orange) } }
            }.padding(30)
        }.onChange(of: model.network.pairedFeedback) { _, _ in
            withAnimation(TogetherTheme.motion(reduceMotion)) { showSuccess = true }
            Task { @MainActor in try? await Task.sleep(for: .seconds(2)); withAnimation(TogetherTheme.motion(reduceMotion)) { showSuccess = false } }
        }
    }
}
