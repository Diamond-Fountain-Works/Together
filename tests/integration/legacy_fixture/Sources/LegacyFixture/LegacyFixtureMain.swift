import Foundation
import CryptoKit
import CoreGraphics
import Darwin
import TogetherCore

/// Builds a real store using the untouched 0.0.1 source, never production data.
@main struct LegacyFixture {
    @MainActor static func main() throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--audit-copy" {
            try ExistingStoreAudit.run(URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true))
            return
        }
        guard CommandLine.arguments.count == 2 else { throw FixtureError.invalidPath }
        let requested = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
        let root = requested.resolvingSymlinksInPath()
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard root.path == requested.path, root.lastPathComponent.hasPrefix("together-migration-") else { throw FixtureError.invalidPath }
        try requireOwnedDirectory(root)
        if let configured = ProcessInfo.processInfo.environment["TOGETHER_MIGRATION_TEMP_PARENT"] {
            guard let projectPath = ProcessInfo.processInfo.environment["TOGETHER_MIGRATION_PROJECT_ROOT"] else { throw FixtureError.invalidPath }
            let project = URL(fileURLWithPath: projectPath, isDirectory: true).standardizedFileURL
            let allowed = project.appendingPathComponent("qa/results", isDirectory: true)
            let parent = URL(fileURLWithPath: configured, isDirectory: true).standardizedFileURL
            // Bind the override to the actual materialized fixture source,
            // not merely to an arbitrary caller-declared directory.
            let source = URL(fileURLWithPath: #filePath).standardizedFileURL.resolvingSymlinksInPath()
            guard project.path == project.resolvingSymlinksInPath().path,
                  parent.path == parent.resolvingSymlinksInPath().path,
                  parent.path == allowed.path || parent.path.hasPrefix(allowed.path + "/"),
                  source.path.hasPrefix(allowed.path + "/"),
                  root.deletingLastPathComponent().path == parent.path else { throw FixtureError.invalidPath }
            try requireOwnedDirectory(parent)
        } else {
            guard root.path.hasPrefix(temporary.path + "/") else { throw FixtureError.invalidPath }
        }
        guard try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty else { throw FixtureError.invalidPath }
        let meta = LocalIdentityMetadata()
        let identity = try DeviceIdentity.persistent(deviceId: meta.deviceId, userId: meta.userId, spaceId: meta.spaceId, directory: root.appendingPathComponent("Identity"), needsExistingIdentity: false, timeZoneIdentifier: "Asia/Shanghai")
        let peer = try DeviceIdentity(timeZoneIdentifier: "America/Los_Angeles")
        let now = ISO8601DateFormatter().date(from: "2026-10-09T04:00:00Z")!, clock = FixedDateProvider(now)
        let a = try ReplicaEngine(repository: TogetherRepository(url: root.appendingPathComponent("legacy.store")), identity: identity, mediaRoot: root.appendingPathComponent("Media"), dateProvider: clock)
        let b = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity: peer, mediaRoot: root.appendingPathComponent("PeerMedia"), dateProvider: clock)
        try a.authorize(.init(descriptor: peer.descriptor, host: "100.70.80.90", port: 58431))
        try b.authorize(.init(descriptor: identity.descriptor, host: "100.70.80.91", port: 58431))
        let canvas = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        canvas.setFillColor(CGColor(red: 0.8, green: 0.4, blue: 0.5, alpha: 1)); canvas.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        let avatar = try AvatarProcessor.encode(canvas.makeImage()!)
        try a.updateProfile(name: "LEGACY_PROFILE_FIXTURE", label: "Boyfriend", avatar: avatar)
        let task = try a.createTask(title: "LEGACY_TASK_FIXTURE", dueAt: now.addingTimeInterval(86400), recurrence: .init(mode: .regular, unit: .day, interval: 1, timeZoneIdentifier: "Asia/Shanghai"))
        let day = CivilDate(year: 2026, month: 10, day: 9)
        let grant = try a.grant(fulfiller: identity.descriptor.userId, beneficiary: peer.descriptor.userId, quantity: 3, date: day, notes: "LEGACY_GRANT_FIXTURE")
        try b.merge(a.operations)
        let wish = try b.createWish(grantId: grant, title: "LEGACY_WISH_FIXTURE", description: "")
        var draft = LoveGiftDraft(); draft.text = "LEGACY_GIFT_FIXTURE"
        let gift = try b.sendGift(draft)
        try a.merge(b.operations)
        try a.requestFulfillment(wish); try b.merge(a.operations); try b.confirmFulfillment(wish); try a.merge(b.operations)
        try a.markGiftPresented(gift, automatic: true); try a.markGiftOpened(gift)
        let bindingBody: [String: String] = ["serviceURL": "https://relay.example.test", "routeId": UUID().uuidString, "peerDeviceId": peer.descriptor.deviceId.uuidString, "peerPublicKey": peer.descriptor.publicKey.base64EncodedString(), "localDeviceId": identity.descriptor.deviceId.uuidString]
        let binding = try CanonicalJSON.decode(RelayBinding.self, from: JSONSerialization.data(withJSONObject: bindingBody))
        try a.bindRelay(peer: a.peer!, binding: binding)
        try a.repository.save(meta, key: "local-identity"); try a.repository.save("Asia/Shanghai", key: "initial-time-zone")
        let hashes = Dictionary(uniqueKeysWithValues: try a.operations.map { ($0.id.uuidString, digest(try CanonicalJSON.encode($0))) })
        let expected = Expectation(metadata: meta, descriptor: identity.descriptor, peer: a.peer!, binding: binding, spaceId: a.context.spaceId, taskId: task, grantId: grant, wishId: wish, giftId: gift, avatarHash: digest(avatar), operationHashes: hashes)
        try CanonicalJSON.encode(expected).write(to: root.appendingPathComponent("expected.json"))
        print("Legacy 0.0.1 store created: \(hashes.count) signed operations")
    }
    private static func requireOwnedDirectory(_ url: URL) throws {
        var info = stat()
        guard url.path.withCString({ lstat($0, &info) }) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), info.st_uid == getuid() else { throw FixtureError.invalidPath }
    }
    static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
}
enum FixtureError: Error { case invalidPath }
struct Expectation: Codable {
    let metadata: LocalIdentityMetadata; let descriptor: DeviceDescriptor; let peer: PairedPeer; let binding: RelayBinding; let spaceId: UUID
    let taskId: UUID; let grantId: UUID; let wishId: UUID; let giftId: UUID; let avatarHash: String; let operationHashes: [String: String]
}
