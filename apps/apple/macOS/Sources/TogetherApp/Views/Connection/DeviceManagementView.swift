import SwiftUI
import TogetherCore

struct DeviceManagementView: View {
    @ObservedObject var model: ApplicationModel
    @StateObject private var manager: DeviceEnrollmentModel
    init(model: ApplicationModel) { self.model = model; _manager = StateObject(wrappedValue: DeviceEnrollmentModel(model: model)) }
    var body: some View {
        let pendingDevice = manager.revoking
        VStack(alignment: .leading, spacing: 0) {
            Text(Copy.text("device.title")).font(.title2.bold()).togetherPadding(26).accessibilityIdentifier("devices.title")
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    deviceList
                    if model.usesNativeTransport { EmptyView() }
                    else if model.engine.usesReplication4 { controller }
                    else if model.engine.peer != nil {
                        if manager.hasLegacyRelay { migration }
                        else { Text(Copy.text("device.guidance.relayMigration")).foregroundColor(.secondary) }
                    }
                    else if manager.canJoin { join }
                    else { Text(Copy.text("device.error.existingData")).foregroundColor(.secondary) }
                    if let status = manager.status { Text(status).foregroundColor(.secondary).accessibilityIdentifier("devices.feedback") }
                    if let error = manager.error { Text(error).foregroundColor(.orange).togetherTextSelection().accessibilityIdentifier("devices.error") }
                }.togetherHorizontalPadding(26).padding(.bottom, 24)
            }
            Divider()
            HStack {
                if manager.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button(Copy.text("copy.action.f867f3417859")) { model.dismissSheet() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("devices.close")
            }.padding(20)
        }.togetherSheetSize(width: 720, height: 650)
        .onChange(of: model.engine.changeNumber) { _ in manager.refresh() }
        .togetherConfirmation(Copy.text("device.action.revoke"),
            isPresented: Binding(get: { manager.revoking != nil }, set: { if !$0 { manager.revoking = nil } }),
            confirmationTitle: Copy.text("device.action.revoke"), message: Copy.text("device.guidance.revoke"), identifier: "devices.revoke.confirm") {
                if let device = pendingDevice { manager.revoke(device) }; manager.revoking = nil
            }
    }
    private var deviceList: some View {
        TogetherCard {
            VStack(alignment: .leading, spacing: 16) {
                if manager.devices.isEmpty {
                    row(model.engine.identity.descriptor, revoked: false)
                    if let peer = model.engine.peer { row(peer.descriptor, revoked: false) }
                } else {
                    ForEach(manager.devices) { device in
                        TogetherAdaptiveStack(spacing: 12, desktop: .init(alignment: .top)) {
                            row(device.descriptor, revoked: !device.isActive)
                            #if os(macOS)
                            Spacer()
                            #endif
                            if !model.usesNativeTransport, manager.isController, device.isActive, device.descriptor.userId == model.engine.identity.descriptor.userId,
                               model.engine.context.authorization?.root(for: device.descriptor.userId)?.deviceId != device.id {
                                Button(Copy.text("device.action.revoke")) { manager.revoking = device }.disabled(manager.busy).accessibilityIdentifier("devices.revoke." + device.id.uuidString)
                            }
                        }
                    }
                }
                if model.engine.usesReplication4 {
                    Text(Copy.text(model.completedSyncCount > 0 ? "device.status.historyReady" : "device.status.historyPending"))
                        .font(.caption).foregroundColor(.secondary).accessibilityIdentifier("devices.historyState")
                }
            }
        }
    }
    private func row(_ descriptor: DeviceDescriptor, revoked: Bool) -> some View {
        let own = descriptor.deviceId == model.engine.identity.descriptor.deviceId
        let online = model.network.multiDeviceService?.connectedDevices.contains(descriptor.deviceId) ?? (model.engine.peer?.descriptor.deviceId == descriptor.deviceId && model.partnerIsOnline)
        return VStack(alignment: .leading, spacing: 5) {
            TogetherAdaptiveStack(spacing: 12, desktop: .init()) {
                Image(systemName: TogetherSymbols.name("desktopcomputer"))
                Text(verbatim: descriptor.displayName).fontWeight(.medium)
                if let owner = model.engine.snapshot.profiles[descriptor.userId] {
                    Text(verbatim: owner.displayName).font(.caption).foregroundColor(.secondary)
                }
                Text(Copy.text(revoked ? "device.status.revoked" : own ? "device.status.thisDevice" : online ? "device.status.online" : "device.status.offline"))
                    .font(.caption).foregroundColor(online && !revoked ? Color.green : Color.secondary).accessibilityIdentifier("devices.state." + descriptor.deviceId.uuidString)
            }
            Text(verbatim: descriptor.fingerprint).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary).togetherTextSelection()
        }.accessibilityElement(children: .contain).accessibilityIdentifier("devices.row." + descriptor.deviceId.uuidString)
    }
    @ViewBuilder private var controller: some View {
        if manager.isController {
            TogetherAdaptiveStack(spacing: 12, desktop: .init()) {
                Button(Copy.text("device.action.add")) { manager.createOffer() }.togetherProminentButton().accessibilityIdentifier("devices.add")
                Button(Copy.text("device.action.importRequest")) { manager.importRequest() }.accessibilityIdentifier("devices.importRequest")
            }.disabled(manager.busy || manager.service == nil)
            if let offer = manager.offer, manager.request == nil {
                code(try? offer.verificationCode)
                Text(Copy.text("device.guidance.offer")).font(.callout).foregroundColor(.secondary)
                Text(Copy.time(offer.body.expiresAt)).font(.caption)
                Button(Copy.text("device.action.exportOffer")) { manager.exportOfferAgain() }.disabled(manager.busy)
            }
            if let request = manager.request {
                Text(verbatim: request.body.device.displayName).font(.headline)
                code(try? request.verificationCode)
                Text(verbatim: request.body.device.fingerprint).font(.system(.caption, design: .monospaced)).togetherTextSelection()
                Toggle(Copy.text("device.guidance.checkRequest"), isOn: $manager.verifiedRequest).accessibilityIdentifier("devices.verifyRequest")
                Button(Copy.text("device.action.authorize")) { manager.approveRequest() }
                    .disabled(!manager.verifiedRequest || manager.busy).accessibilityIdentifier("devices.authorize")
                if manager.completion != nil { Button(Copy.text("device.action.exportCompletion")) { manager.exportCompletionAgain() }.disabled(manager.busy) }
            }
        } else { Text(Copy.text("device.guidance.controller")).font(.callout).foregroundColor(.secondary) }
    }
    private var join: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(Copy.text("device.action.importOffer")) { manager.importOffer() }.accessibilityIdentifier("devices.importOffer")
            if let offer = manager.offer {
                code(try? offer.verificationCode)
                Text(Copy.text("device.guidance.offerCheck")).font(.callout).foregroundColor(.secondary)
                Toggle(Copy.text("device.guidance.checkOffer"), isOn: $manager.verifiedOffer).accessibilityIdentifier("devices.verifyOffer")
                TextField(Copy.text("device.field.name"), text: $manager.deviceName).textFieldStyle(.roundedBorder).accessibilityIdentifier("devices.name")
                Button(Copy.text("device.action.exportRequest")) { manager.createRequest() }.disabled(!manager.verifiedOffer || manager.deviceName.isEmpty).accessibilityIdentifier("devices.exportRequest")
                if let request = manager.request {
                    code(try? request.verificationCode)
                    Text(verbatim: request.body.device.fingerprint).font(.system(.caption, design: .monospaced)).togetherTextSelection()
                    Button(Copy.text("device.action.importCompletion")) { manager.importCompletion() }.accessibilityIdentifier("devices.importCompletion")
                }
                if manager.completion != nil {
                    Toggle(Copy.text("device.guidance.checkCompletion"), isOn: $manager.verifiedCompletion).accessibilityIdentifier("devices.verifyCompletion")
                    Button(Copy.text("device.action.use")) { manager.useDevice() }.togetherProminentButton().disabled(!manager.verifiedCompletion).accessibilityIdentifier("devices.use")
                }
            }
        }.disabled(manager.busy)
    }
    private var migration: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Copy.text("device.migration.title")).font(.headline)
            Text(Copy.text("device.guidance.migration")).font(.callout).foregroundColor(.secondary)
            TogetherAdaptiveStack(spacing: 12, desktop: .init()) {
                Button(Copy.text("device.action.exportMigration")) { manager.beginMigration() }.accessibilityIdentifier("devices.migration.begin")
                Button(Copy.text("device.action.importMigration")) { manager.importMigration() }.accessibilityIdentifier("devices.migration.import")
            }
            if let exchange = manager.migration {
                code(try? exchange.verificationCode)
                Toggle(Copy.text("device.guidance.checkMigration"), isOn: $manager.verifiedMigration).accessibilityIdentifier("devices.migration.verify")
                Button(Copy.text("device.action.signMigration")) { manager.signMigration() }.disabled(!manager.verifiedMigration).accessibilityIdentifier("devices.migration.sign")
                if exchange.genesis.signatures.count == 2 {
                    Button(Copy.text("device.action.activateMigration")) { manager.activateMigration() }.togetherProminentButton().disabled(!manager.verifiedMigration).accessibilityIdentifier("devices.migration.activate")
                }
            }
        }.disabled(manager.busy)
    }
    private func code(_ text: String?) -> some View {
        Text(verbatim: text ?? "").font(.system(.title3, design: .monospaced)).togetherTextSelection().accessibilityIdentifier("devices.verificationCode")
    }
}
