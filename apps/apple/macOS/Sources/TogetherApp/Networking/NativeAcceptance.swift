#if TOGETHER_NATIVE_P2P_QA
import AppKit
import SwiftUI
import TogetherCore
import TogetherP2P

/// Separate bundle, explicit argument and bounded temporary storage are all
/// mandatory. No error or retry path is allowed to fall back to production().
@MainActor enum NativeAcceptance {
    static func build() throws -> ApplicationModel {
        let args = ProcessInfo.processInfo.arguments
        guard Bundle.main.bundleIdentifier == "com.together.app.qa.p2p",
              let flag = args.firstIndex(of: "--native-p2p-qa"), flag + 1 < args.count else {
            throw TogetherError.invalid(Copy.text("qa.error.isolatedLaunch"))
        }
        let input = URL(fileURLWithPath: args[flag + 1], isDirectory: true)
        let root = input.standardizedFileURL.resolvingSymlinksInPath()
        let parent = root.deletingLastPathComponent().path
        let allowed = ["/tmp", "/private/tmp", FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath().path]
        guard root.lastPathComponent.hasPrefix("together-native-app-"), allowed.contains(parent),
              FileManager.default.fileExists(atPath: root.path) else {
            throw TogetherError.invalid(Copy.text("qa.error.isolatedLaunch"))
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let repository = try TogetherRepository(url: root.appendingPathComponent("Together.store"))
        let saved = try repository.load(LocalIdentityMetadata.self, key: "local-identity")
        let hasFacts = try repository.operationCount() > 0
        guard saved != nil || !hasFacts else { throw IdentityStorageError.identityMismatch }
        let metadata = saved ?? LocalIdentityMetadata()
        let identity = try DeviceIdentity.persistent(deviceId: metadata.deviceId, userId: metadata.userId, spaceId: metadata.spaceId,
            directory: root.appendingPathComponent("Identity"), needsExistingIdentity: saved != nil || hasFacts,
            migrateLegacy: false, timeZoneIdentifier: "Asia/Shanghai", protocolVersion: 4)
        try repository.save(metadata, key: "local-identity")
        let engine = try ReplicaEngine(repository: repository, identity: identity, mediaRoot: root.appendingPathComponent("Media"))
        let suite = "com.together.app.qa.p2p." + root.lastPathComponent
        guard let defaults = UserDefaults(suiteName: suite) else { throw TogetherError.invalid(Copy.text("qa.error.isolatedLaunch")) }
        let model = ApplicationModel(engine: engine, defaults: defaults, serviceURL: nil, useBundledService: false)
        model.nativeNetwork = try NativeAppPeerService(engine: engine, root: root)
        return model
    }
}

#endif

#if TOGETHER_NATIVE_TRANSPORT || TOGETHER_NATIVE_P2P_QA
import SwiftUI
import TogetherCore
import TogetherP2P
import AppKit

struct NativeConnectionView: View {
    let model: ApplicationModel
    let network: NativeAppPeerService
    @State private var invitation = ""
    @State private var verified = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: Copy.text("nav.connection"), subtitle: "")
                HStack {
                    Circle().fill(network.isOnline ? .green : .secondary).frame(width: 7, height: 7)
                    Text(network.state.displayName)
                    Spacer()
                }.accessibilityIdentifier("connection.state")
                if let error = network.localizedErrorMessage { Text(verbatim: error).foregroundStyle(.orange).textSelection(.enabled).accessibilityIdentifier("connection.error") }
                if let code = network.verificationCode {
                    TogetherCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(Copy.text("copy.action.2fd9629c1a44")).font(.headline)
                            Text(verbatim: network.remoteName).font(.title3.weight(.semibold))
                            Text(verbatim: code).font(.system(size: 30, weight: .semibold, design: .monospaced)).accessibilityIdentifier("pairing.verificationCode")
                            Text(verbatim: network.remoteFingerprint).font(.caption.monospaced()).textSelection(.enabled)
                            Toggle(Copy.text("copy.guidance.9132a75101e9"), isOn: $verified).accessibilityIdentifier("pairing.verified")
                            HStack {
                                Button(Copy.text("copy.action.2cd0f3be8738")) { network.disconnect(); verified = false }.accessibilityIdentifier("pairing.cancel")
                                Spacer()
                                Button(Copy.text("copy.action.2fd9629c1a44")) { network.confirmPairing(verified: verified) }.buttonStyle(.borderedProminent).disabled(!verified).accessibilityIdentifier("pairing.confirm")
                            }
                        }
                    }
                } else if model.engine.context.peer == nil {
                    TogetherCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Button(Copy.text("copy.action.1032f5e75333")) { network.createInvitation() }.buttonStyle(.borderedProminent).disabled(network.busy).accessibilityIdentifier("pairing.createInvite")
                            if let code = network.invitationCode {
                                Text(Copy.text("native.pairing.contactReady")).font(.callout)
                                if let expires = network.invitationExpiresAt { Text(Copy.time(expires)).font(.caption).foregroundStyle(.secondary) }
                                Button(Copy.text("copy.action.52c229c10699")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) }.accessibilityIdentifier("pairing.copyInvite")
                                Button(Copy.text("copy.action.2cd0f3be8738")) { network.disconnect() }.accessibilityIdentifier("pairing.cancelInvite")
                            }
                            Divider()
                            TextField(Copy.text("copy.guidance.c8b56dca7aed"), text: $invitation, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder).accessibilityIdentifier("pairing.codeInput")
                            Button(Copy.text("copy.action.d8392ef9f3fb")) { network.joinInvitation(invitation) }.disabled(invitation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || network.busy).accessibilityIdentifier("pairing.joinInvite")
                        }
                    }
                } else {
                    TogetherCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text(model.name(model.engine.context.peer!.userId))
                                Spacer()
                                Button(Copy.text("copy.action.68891ab35cab")) { network.reconnect() }.disabled(network.needsRecovery).accessibilityIdentifier("connection.reconnect")
                                Button(Copy.text("copy.action.dcfe516d1114")) { network.synchronize() }.disabled(!network.isOnline).accessibilityIdentifier("connection.sync")
                                Button(Copy.text("native.connection.disconnect")) { network.disconnect() }.disabled(!network.isOnline).accessibilityIdentifier("connection.disconnect")
                            }
                            Text(Copy.text(network.latestOperationProgress?.partnerHasPersisted == true ? "native.sync.remotePersisted" : "native.sync.pending")).font(.callout).accessibilityIdentifier("connection.persistence")
                            let selected = network.paths.filter(\.selected)
                            if selected.contains(where: \.direct) { Text(Copy.text("native.path.direct")).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("connection.path") }
                            else if selected.contains(where: \.relayed) { Text(Copy.text("native.path.relay")).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("connection.path") }
                        }
                    }
                }
                MediaTransferProgressView(engine: model.engine)
                if network.busy { ProgressView().controlSize(.small) }
            }.padding(30)
        }.onChange(of: network.verificationCode) { _, _ in verified = false }
    }
}
#endif
