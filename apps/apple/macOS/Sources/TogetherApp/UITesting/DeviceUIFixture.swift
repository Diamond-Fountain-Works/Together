#if DEBUG
import Foundation
import TogetherCore

/// Real native clients and a real loopback Worker, with deterministic synthetic
/// identities. No fake transport or production endpoint is used by these cases.
@MainActor enum DeviceUIFixture {
    static func configure(original: ApplicationModel, a: ReplicaEngine, b: ReplicaEngine,
                          root: URL, page: String) async throws -> ApplicationModel {
        guard Bundle.main.bundleIdentifier == "com.together.app.qa", UIFixture.enabled,
              let text = ProcessInfo.processInfo.environment["TOGETHER_UI_RELAY_URL"],
              let url = URL(string: text), url.scheme == "http", url.host == "127.0.0.1",
              url.user == nil, url.password == nil, url.path.isEmpty || url.path == "/" else {
            throw TogetherError.invalid("Device UI tests require an isolated loopback Worker")
        }
        let output = root.appendingPathComponent("user-export")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let pa = PairingService(engine: a, serviceURL: url), pb = PairingService(engine: b, serviceURL: url)
        await pa.createInvitation()
        guard let code = pa.invitationCode else { throw TogetherError.invalid("Synthetic invitation failed") }
        await pb.joinInvitation(code)
        try await wait { pa.proposal != nil && pb.proposal != nil }
        await pa.confirmPairing(); await pb.confirmPairing()
        try await wait { pa.isOnline && pb.isOnline && a.snapshot == b.snapshot }
        pa.disconnect()
        if page == "devices-migration" {
            let model = ApplicationModel(engine: a, defaults: original.localDefaults, serviceURL: url, useBundledService: false, filePanelDirectory: output)
            model.qaAllowsLocalNetwork = true; model.qaLegacyPeers = [pb]
            model.qaDeviceTask = Task { @MainActor [weak model] in
                do {
                    let file = output.appendingPathComponent(Copy.text("device.file.migration"))
                    while !Task.isCancelled {
                        if let bytes = try? Data(contentsOf: file), let exchange = try? CanonicalJSON.decode(LegacyMigrationExchange.self, from: bytes) {
                            let signed = try await exchange.cosign(b, verified: true)
                            try CanonicalJSON.encode(signed).write(to: output.appendingPathComponent("Together-Migration-Cosigned.json"), options: .atomic)
                            pb.disconnect()
                            let service = try await C1ReplicationService.migrate(engine: b, genesis: signed.genesis)
                            model?.qaC1Peers.append(service); await service.start()
                            break
                        }
                        try await Task.sleep(for: .milliseconds(150))
                    }
                } catch { model?.errorMessage = error.localizedDescription }
            }
            model.section = .connection; model.show(.devices)
            return model
        }
        pb.disconnect()
        let first = try await LegacyMigrationExchange.begin(a)
        let signed = try await first.cosign(b, verified: true)
        let sa = try await C1ReplicationService.migrate(engine: a, genesis: signed.genesis)
        let sb = try await C1ReplicationService.migrate(engine: b, genesis: signed.genesis)
        await sb.start()
        if page == "devices" {
            let model = ApplicationModel(engine: a, defaults: original.localDefaults, serviceURL: url, useBundledService: false, filePanelDirectory: output)
            model.qaAllowsLocalNetwork = true; model.qaC1Peers = [sb]
            model.section = .connection; model.show(.devices)
            return model
        }
        await sa.start()
        try await wait { sa.state == .connected && sb.state == .connected }
        let offer = try await sa.createDeviceOffer()
        try CanonicalJSON.encode(offer).write(to: output.appendingPathComponent(Copy.text("device.file.offer")))
        let folder = root.appendingPathComponent("new-local-bootstrap")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let identity = try DeviceIdentity(protocolVersion: 3)
        let fresh = try ReplicaEngine(repository: TogetherRepository(url: folder.appendingPathComponent("Together.store")), identity: identity, mediaRoot: folder.appendingPathComponent("Media"), dateProvider: a.dateProvider)
        let model = ApplicationModel(engine: fresh, defaults: original.localDefaults, serviceURL: url, useBundledService: false, filePanelDirectory: output)
        model.qaAllowsLocalNetwork = true; model.qaC1Peers = [sa, sb]
        model.qaDeviceTask = Task { @MainActor [weak model] in
            do {
                let file = output.appendingPathComponent(Copy.text("device.file.request"))
                while !Task.isCancelled {
                    if let bytes = try? Data(contentsOf: file), let request = try? CanonicalJSON.decode(DeviceEnrollmentRequest.self, from: bytes) {
                        let completion = try await sa.approveDeviceRequest(request, verified: true)
                        try CanonicalJSON.encode(completion).write(to: output.appendingPathComponent(Copy.text("device.file.completion")), options: .atomic)
                        break
                    }
                    try await Task.sleep(for: .milliseconds(150))
                }
            } catch { model?.errorMessage = error.localizedDescription }
        }
        model.section = .connection; model.show(.devices)
        return model
    }
    private static func wait(_ ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(25))
        while !ready() {
            guard ContinuousClock.now < deadline else { throw TogetherError.invalid("Isolated peer setup timed out") }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
#endif
