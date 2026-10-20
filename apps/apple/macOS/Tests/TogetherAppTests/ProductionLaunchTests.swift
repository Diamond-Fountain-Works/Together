import Testing
import Foundation
@testable import TogetherApp

#if TOGETHER_NATIVE_TRANSPORT
@Suite("Normal launch identity boundary") @MainActor
struct ProductionLaunchTests {
    @Test func ordinaryLaunchNeedsNoQAArguments() throws {
        try NativeProduction.validateLaunch(bundleIdentifier: "com.together.app", arguments: ["Together"])
    }
    @Test func qaBundleCannotFallBackToProduction() {
        for id in [nil, "com.together.app.qa", "com.together.app.qa.p2p"] as [String?] {
            #expect(throws: (any Error).self) { try NativeProduction.validateLaunch(bundleIdentifier: id, arguments: ["Together"]) }
        }
    }
    @Test func qaAndFixtureLaunchArgumentsAreRejectedBeforeOpeningStorage() {
        for flag in ["--native-p2p-qa", "--ui-testing"] {
            #expect(throws: (any Error).self) {
                try NativeProduction.validateLaunch(bundleIdentifier: "com.together.app", arguments: ["Together", flag, "/private/tmp/test"])
            }
        }
    }
    @Test func emptyStorageBoundaryDoesNotCreateFilesAndSymlinkStoreIsRejected() throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("together-app-policy-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("Together", isDirectory: true)
        try NativeProduction.validateStorageBoundary(root)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let outside = parent.appendingPathComponent("outside.store")
        try Data("synthetic".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Together.store"), withDestinationURL: outside)
        #expect(throws: (any Error).self) { try NativeProduction.validateStorageBoundary(root) }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Identity").path))
    }
}
#endif
