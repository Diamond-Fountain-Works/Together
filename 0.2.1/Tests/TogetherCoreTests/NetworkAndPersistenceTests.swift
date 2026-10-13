import Foundation
import Testing
import CoreGraphics
import ImageIO
@testable import TogetherCore

enum TestTimeout: Error { case expired }
@MainActor func eventually(_ condition: @MainActor () -> Bool, seconds: Double = 12) async throws {
    let deadline = Date.now.addingTimeInterval(seconds)
    while !condition() {
        guard Date.now < deadline else { throw TestTimeout.expired }
        try await Task.sleep(for: .milliseconds(30))
    }
}
@Suite("TCP and Persistence") @MainActor struct NetworkAndPersistenceTests {
    @Test func realLocalhostHandshakeSyncAndReconnect() async throws {
        let p = try TwoReplicas(paired: false)
        let a = PeerService(engine: p.a), b = PeerService(engine: p.b)
        defer { a.stopListening(); b.stopListening() }
        try a.startListening(host: "127.0.0.1", port: 0, persist: false)
        try b.startListening(host: "127.0.0.1", port: 0, persist: false)
        try await eventually { a.boundPort > 0 && b.boundPort > 0 }
        try a.connect(host: "127.0.0.1", port: b.boundPort)
        try await eventually { a.proposal != nil && b.proposal != nil }
        #expect(a.proposal!.verificationCode == b.proposal!.verificationCode)
        #expect(p.a.snapshot.profiles.count == 1 && p.b.snapshot.profiles.count == 1)
        try a.confirmPairing(); try b.confirmPairing()
        try await eventually { a.state == .connected && b.state == .connected && p.a.snapshot.profiles.count == 2 && p.b.snapshot.profiles.count == 2 }
        try p.a.createTask(title: "A 实际 TCP"); try p.b.createTask(title: "B 实际 TCP")
        try await eventually { p.a.snapshot.tasks.count == 2 && p.b.snapshot.tasks.count == 2 && p.a.snapshot == p.b.snapshot }
        a.disconnect(); b.disconnect()
        try p.a.createTask(title: "A 断线期间"); try p.b.createTask(title: "B 断线期间")
        // connect re-enables this side; startListening re-enables incoming acceptance on the other side.
        try b.startListening(host: "127.0.0.1", port: 0, persist: false)
        try await eventually { b.boundPort > 0 }
        try a.connect(host: "127.0.0.1", port: b.boundPort)
        try await eventually { p.a.snapshot.tasks.count == 4 && p.b.snapshot.tasks.count == 4 && p.a.snapshot == p.b.snapshot }
    }
    @Test func frameFragmentsAndAddressPolicy() throws {
        var decoder = FrameDecoder()
        let payload = Data("hello".utf8), frame = try FrameDecoder.encode(payload)
        #expect(try decoder.append(Data(frame.prefix(3))).isEmpty)
        #expect(try decoder.append(Data(frame.dropFirst(3))) == [payload])
        #expect(throws: (any Error).self) { try decoder.append(Data([255,255,255,255])) }
        #expect(NetworkAddressPolicy.allowed("100.70.80.90"))
        #expect(NetworkAddressPolicy.allowed("fd7a:115c:a1e0::1234"))
        #expect(!NetworkAddressPolicy.allowed("192.168.1.2"))
        #expect(!NetworkAddressPolicy.allowed("8.8.8.8"))
        #expect(NetworkAddressPolicy.validHost("partner-mac"))
        #expect(NetworkAddressPolicy.validHost("partner-mac.example.ts.net"))
        #expect(!NetworkAddressPolicy.validHost("example.com"))
        #expect(try ProtocolNegotiation.select(remote: [1, 2]) == 2)
        #expect(throws: (any Error).self) { try ProtocolNegotiation.select(remote: [1]) }
    }
    @Test func savedPeerAutomaticListenerReconnectWithoutRepairing() async throws {
        let p = try TwoReplicas()
        let firstA = PeerService(engine: p.a), firstB = PeerService(engine: p.b)
        try firstA.startListening(host: "127.0.0.1", port: 0, persist: false)
        try firstB.startListening(host: "127.0.0.1", port: 0, persist: false)
        try await eventually { firstA.boundPort > 0 && firstB.boundPort > 0 }
        let portA = firstA.boundPort, portB = firstB.boundPort
        try p.a.authorize(PairedPeer(descriptor: p.b.identity.descriptor, host: "127.0.0.1", port: portB))
        try p.b.authorize(PairedPeer(descriptor: p.a.identity.descriptor, host: "127.0.0.1", port: portA))
        firstA.stopListening(); firstB.stopListening()
        try p.a.createTask(title: "自动重连前离线 A"); try p.b.createTask(title: "自动重连前离线 B")
        let a = PeerService(engine: p.a), b = PeerService(engine: p.b)
        defer { a.stopListening(); b.stopListening() }
        a.restore(); b.restore()
        do { try await eventually { a.boundPort == portA && b.boundPort == portB && a.state == .connected && b.state == .connected && p.a.snapshot == p.b.snapshot } }
        catch { Issue.record("Automatic startup: A \(a.boundPort)/\(portA) \(a.state) \(a.errorMessage ?? "none") / B \(b.boundPort)/\(portB) \(b.state) \(b.errorMessage ?? "none") / tasks \(p.a.snapshot.tasks.count),\(p.b.snapshot.tasks.count)"); throw error }
        #expect(a.proposal == nil && b.proposal == nil)
        #expect(p.a.snapshot.tasks.count == 2)
        b.stopListening()
        try p.a.createTask(title: "对端停止期间")
        b.restore()
        do { try await eventually { a.state == .connected && b.state == .connected && p.a.snapshot == p.b.snapshot && p.b.snapshot.tasks.count == 3 } }
        catch { Issue.record("Automatic recovery: A \(a.boundPort) \(a.state) \(a.errorMessage ?? "none") / B \(b.boundPort) \(b.state) \(b.errorMessage ?? "none") / tasks \(p.a.snapshot.tasks.count),\(p.b.snapshot.tasks.count)"); throw error }
        #expect(a.proposal == nil && b.proposal == nil)
    }
    @Test func avatarCompressionSyncAndDiskReopen() throws {
        let c = CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        c.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.4, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        let data = try AvatarProcessor.encode(c.makeImage()!, crop: AvatarCrop(zoom: 1.2))
        #expect(data.count <= 131_072)
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        #expect(image.width <= 512 && image.width == image.height)
        let p = try TwoReplicas()
        try p.a.updateProfile(name: "头像 A", label: "Partner", avatar: data); try p.exchange()
        #expect(p.b.snapshot.profiles[p.a.identity.descriptor.userId]?.avatarData == data)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("together-storage-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")
        let identity = try DeviceIdentity()
        let first = try ReplicaEngine(repository: TogetherRepository(url: url), identity: identity)
        try first.updateProfile(name: "持久头像", label: "Partner", avatar: data)
        let task = try first.createTask(title: "重开后保留")
        let reopened = try ReplicaEngine(repository: TogetherRepository(url: url), identity: identity)
        #expect(reopened.ownProfile?.avatarData == data)
        #expect(reopened.snapshot.tasks[task]?.title == "重开后保留")
    }
}
