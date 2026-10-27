import SwiftUI
import TogetherCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ConnectionView: View {
    @ObservedObject var model: ApplicationModel
    @State private var invitation = ""
    @State private var verified = false
    @State private var showSuccess = false
    @TogetherMotionPreference private var reduceMotion
    @Namespace private var pairGeometry
    var body: some View {
        #if TOGETHER_NATIVE_TRANSPORT || TOGETHER_NATIVE_P2P_QA
        if let nativeNetwork = model.nativeNetwork { NativeConnectionView(model: model, network: nativeNetwork) }
        else { relayContent }
        #else
        relayContent
        #endif
    }
    private var relayContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                #if os(macOS)
                PageHeading(title: Copy.text("nav.connection"), subtitle: "")
                #endif
                HStack { Circle().fill(model.network.isOnline ? .green : .secondary).frame(width: 7, height: 7); Text(model.network.state.displayName).font(.callout); Spacer() }
                    .accessibilityIdentifier("connection.state")
                TogetherIconButton(Copy.text("device.title"), systemImage: TogetherSymbols.name("desktopcomputer")) { model.show(.devices) }.accessibilityIdentifier("connection.devices")
                if let error = model.network.errorMessage { Text(Copy.userErrorMessage(error)).foregroundColor(.orange).accessibilityIdentifier("connection.error") }
                if !model.network.isConfigured {
                    Text(Copy.text("copy.guidance.4d93993d5b23")).font(.callout).foregroundColor(.secondary)
                } else if let proposal = model.network.proposal {
                    TogetherCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(Copy.text("copy.action.2fd9629c1a44")).font(.headline)
                            HStack(spacing: 14) {
                                AvatarView(profile: model.engine.peer?.descriptor.deviceId == proposal.deviceId ? model.engine.partnerProfile : nil, size: 54, engine: model.engine)
                                Text(proposal.name).font(.title3.weight(.semibold))
                            }
                            Text(verbatim: proposal.verificationCode).font(.system(size: 30, weight: .semibold, design: .monospaced)).accessibilityIdentifier("pairing.verificationCode")
                            Text(Copy.text("copy.status.3ebca10fcb10")).font(.callout).foregroundColor(.secondary)
                            Text(verbatim: proposal.fingerprint).font(.system(.caption, design: .monospaced)).togetherTextSelection()
                            Toggle(Copy.text("copy.guidance.9132a75101e9"), isOn: $verified).accessibilityIdentifier("pairing.verified")
                            HStack {
                                Button(Copy.text("copy.action.2cd0f3be8738")) { model.network.rejectPairing(); verified = false }.accessibilityIdentifier("pairing.cancel")
                                Spacer()
                                Button(Copy.text("copy.action.2fd9629c1a44")) { Task { await model.network.confirmPairing() } }.togetherProminentButton().disabled(!verified || model.network.busy).accessibilityIdentifier("pairing.confirm")
                            }
                        }
                    }
                } else if model.engine.context.peer == nil || model.network.needsMigration {
                    if model.network.needsMigration { Text(Copy.text("copy.guidance.0c2e0cb3cd53")).font(.callout).foregroundColor(.secondary) }
                    TogetherCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Button(Copy.text("copy.action.1032f5e75333")) { Task { await model.network.createInvitation() } }.togetherProminentButton().disabled(model.network.busy).accessibilityIdentifier("pairing.createInvite")
                            if let code = model.network.invitationCode {
                                Text(verbatim: code).font(.system(size: 28, weight: .semibold, design: .monospaced)).togetherTextSelection().accessibilityIdentifier("pairing.invitationCode")
                                if let expires = model.network.invitationExpiresAt { Text(Copy.time(expires)).font(.caption).foregroundColor(.secondary) }
                                Button(Copy.text("copy.action.52c229c10699")) { TogetherPlatform.copy(code) }.accessibilityIdentifier("pairing.copyInvite")
                            }
                            Divider()
                            TextField(Copy.text("copy.guidance.c8b56dca7aed"), text: $invitation).textFieldStyle(.roundedBorder).frame(maxWidth: 300).accessibilityIdentifier("pairing.codeInput")
                            Button(Copy.text("copy.action.d8392ef9f3fb")) { Task { await model.network.joinInvitation(invitation) } }.disabled(invitation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.network.busy).accessibilityIdentifier("pairing.joinInvite")
                        }
                    }
                } else {
                    TogetherCard {
                        TogetherAdaptiveStack(spacing: 18) {
                            AvatarView(profile: model.engine.ownProfile, size: 54, engine: model.engine).matchedGeometryEffect(id: "self", in: pairGeometry)
                            if showSuccess { Image(systemName: TogetherSymbols.name("heart.fill")).foregroundColor(TogetherTheme.rose); Text(Copy.text("copy.status.15a314eb8b4d")).font(.headline) }
                            AvatarView(profile: model.engine.partnerProfile, size: 54, engine: model.engine).matchedGeometryEffect(id: "partner", in: pairGeometry)
                            #if os(macOS)
                            Spacer()
                            #endif
                            Button(Copy.text("copy.action.68891ab35cab")) { model.network.reconnect() }.disabled(model.network.busy).accessibilityIdentifier("connection.reconnect")
                            Button(Copy.text("copy.action.dcfe516d1114")) { model.network.synchronize() }.disabled(!model.network.isOnline).accessibilityIdentifier("connection.sync")
                        }
                    }
                }
                if model.network.busy { ProgressView().controlSize(.small) }
                MediaTransferProgressView(engine: model.engine)
                if !model.engine.snapshot.conflicts.isEmpty { ForEach(model.engine.snapshot.conflicts) { Text(Copy.domainMessage($0.reason)).font(.caption).foregroundColor(.orange) } }
            }.togetherPadding(30)
        }.onChange(of: model.network.pairedFeedback) { _ in
            withAnimation(TogetherTheme.motion(reduceMotion)) { showSuccess = true }
            Task { @MainActor in try? await Task.sleep(nanoseconds: 2_000_000_000); withAnimation(TogetherTheme.motion(reduceMotion)) { showSuccess = false } }
        }
    }
}

/// Shared existing progress presentation for authenticated relay/native sessions.
struct MediaTransferProgressView: View {
    @ObservedObject var engine: ReplicaEngine
    var body: some View {
        if !engine.mediaProgress.isEmpty {
            TogetherCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(Copy.text("copy.status.1c39d7d54b8f")).font(.headline)
                    ForEach(engine.mediaProgress.values.sorted { $0.assetId.uuidString < $1.assetId.uuidString }, id: \.assetId) { progress in
                        Text(engine.mediaAsset(progress.assetId)?.originalFilename ?? Copy.text("copy.status.c7225dbf105e")).font(.callout).lineLimit(1)
                        ProgressView(value: progress.fraction)
                        Text(progress.status.displayName).font(.caption).foregroundColor(.secondary)
                        if let error = progress.error { Text(Copy.userErrorMessage(error)).font(.caption).foregroundColor(.orange) }
                    }
                }
            }
        }
    }
}
