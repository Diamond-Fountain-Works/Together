import Foundation
import Testing
@testable import TogetherCore

@Suite("Standalone and SwiftPM resource placement") struct ResourceBundleTests {
    @Test func appResourceBundlePrecedesGeneratedBuildPathFallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Together-resource-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Resources"), bundleURL = resources.appendingPathComponent("TogetherCore_TogetherCore.bundle")
        #if os(macOS)
        let contents = bundleURL.appendingPathComponent("Contents"), payload = contents.appendingPathComponent("Resources")
        #else
        let contents = bundleURL, payload = bundleURL
        #endif
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "com.together.synthetic-resources", "CFBundlePackageType": "BNDL", "CFBundleVersion": "1"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        try Data("SYNTHETIC_RESOURCE".utf8).write(to: payload.appendingPathComponent("marker.txt"))
        var fallbacks = 0
        let selected = TogetherResources.resolve(mainResourceURL: resources) { fallbacks += 1; return .main }
        #expect(selected.bundleURL.standardizedFileURL.path == bundleURL.standardizedFileURL.path && fallbacks == 0)
        #expect(try String(contentsOf: #require(selected.url(forResource: "marker", withExtension: "txt")), encoding: .utf8) == "SYNTHETIC_RESOURCE")
    }
    @Test func missingAppResourceBundleUsesRawSwiftPMResources() {
        var fallbacks = 0
        let selected = TogetherResources.resolve(mainResourceURL: nil) { fallbacks += 1; return TogetherResources.bundle }
        #expect(fallbacks == 1 && selected.bundleURL == TogetherResources.bundle.bundleURL)
        #expect(selected.url(forResource: "FinanceCurrencies", withExtension: "json") != nil)
        #expect(FinanceCurrency.supported.count == 165)
        #expect(Copy.text("nav.home", language: .chinese) == "首页")
        #expect(Copy.text("nav.home", language: .english) == "Home")
    }
}
