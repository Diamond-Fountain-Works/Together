#if TOGETHER_NATIVE_TRANSPORT || TOGETHER_NATIVE_P2P_QA
import SwiftUI
import TogetherCore
import TogetherP2P
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct NativeConnectionView: View {
    @ObservedObject var model: ApplicationModel
    @ObservedObject var network: NativeAppPeerService
    @State private var invitation = ""
    @State private var verified = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                #if os(macOS)
                PageHeading(title: Copy.text("nav.connection"), subtitle: "")
                #endif
                HStack {
                    Circle().fill(network.isOnline ? .green : .secondary).frame(width: 7, height: 7)
                    Text(network.state.displayName)
                    Spacer()
                }.accessibilityIdentifier("connection.state")
                if let error = network.localizedErrorMessage { Text(verbatim: error).foregroundColor(.orange).togetherTextSelection().accessibilityIdentifier("connection.error") }
                if let code = network.verificationCode {
                    TogetherCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(Copy.text("copy.action.2fd9629c1a44")).font(.headline)
                            Text(verbatim: network.remoteName).font(.title3.weight(.semibold))
                            Text(verbatim: code).font(.system(size: 30, weight: .semibold, design: .monospaced)).accessibilityIdentifier("pairing.verificationCode")
                            Text(verbatim: network.remoteFingerprint).font(.system(.caption, design: .monospaced)).togetherTextSelection()
                            Toggle(Copy.text("copy.guidance.9132a75101e9"), isOn: $verified).accessibilityIdentifier("pairing.verified")
                            HStack {
                                Button(Copy.text("copy.action.2cd0f3be8738")) { network.disconnect(); verified = false }.accessibilityIdentifier("pairing.cancel")
                                Spacer()
                                Button(Copy.text("copy.action.2fd9629c1a44")) { network.confirmPairing(verified: verified) }.togetherProminentButton().disabled(!verified).accessibilityIdentifier("pairing.confirm")
                            }
                        }
                    }
                } else if model.engine.context.peer == nil {
                    TogetherCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Button(Copy.text("copy.action.1032f5e75333")) { network.createInvitation() }.togetherProminentButton().disabled(network.busy).accessibilityIdentifier("pairing.createInvite")
                            if let code = network.invitationCode {
                                Text(Copy.text("native.pairing.contactReady")).font(.callout)
                                if let expires = network.invitationExpiresAt { Text(Copy.time(expires)).font(.caption).foregroundColor(.secondary) }
                                Button(Copy.text("copy.action.52c229c10699")) { TogetherPlatform.copy(code) }.accessibilityIdentifier("pairing.copyInvite")
                                Button(Copy.text("copy.action.2cd0f3be8738")) { network.disconnect() }.accessibilityIdentifier("pairing.cancelInvite")
                            }
                            Divider()
                            TogetherMultilineField(Copy.text("copy.guidance.c8b56dca7aed"), text: $invitation).lineLimit(4).textFieldStyle(.roundedBorder).accessibilityIdentifier("pairing.codeInput")
                            Button(Copy.text("copy.action.d8392ef9f3fb")) { network.joinInvitation(invitation) }.disabled(invitation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || network.busy).accessibilityIdentifier("pairing.joinInvite")
                        }
                    }
                } else {
                    TogetherCard {
                        VStack(alignment: .leading, spacing: 16) {
                            TogetherAdaptiveStack(spacing: 12, desktop: .init()) {
                                Text(model.name(model.engine.context.peer!.userId))
                                #if os(macOS)
                                Spacer()
                                #endif
                                Button(Copy.text("copy.action.68891ab35cab")) { network.reconnect() }.disabled(network.needsRecovery).accessibilityIdentifier("connection.reconnect")
                                Button(Copy.text("copy.action.dcfe516d1114")) { network.synchronize() }.disabled(!network.isOnline).accessibilityIdentifier("connection.sync")
                                Button(Copy.text("native.connection.disconnect")) { network.disconnect() }.disabled(!network.isOnline).accessibilityIdentifier("connection.disconnect")
                            }
                            Text(Copy.text(network.latestOperationProgress?.partnerHasPersisted == true ? "native.sync.remotePersisted" : "native.sync.pending")).font(.callout).accessibilityIdentifier("connection.persistence")
                            let selected = network.paths.filter(\.selected)
                            if selected.contains(where: \.direct) { Text(Copy.text("native.path.direct")).font(.caption).foregroundColor(.secondary).accessibilityIdentifier("connection.path") }
                            else if selected.contains(where: \.relayed) { Text(Copy.text("native.path.relay")).font(.caption).foregroundColor(.secondary).accessibilityIdentifier("connection.path") }
                        }
                    }
                }
                MediaTransferProgressView(engine: model.engine)
                if network.busy { ProgressView().controlSize(.small) }
            }.togetherPadding(30)
        }.onChange(of: network.verificationCode) { _ in verified = false }
    }
}
#endif
