import Foundation

/// A signed standalone app keeps its SwiftPM resource bundle in the platform's
/// resource directory. Raw SwiftPM tests still use their generated accessor.
enum TogetherResources {
    static let bundle: Bundle = resolve(mainResourceURL: Bundle.main.resourceURL) { Bundle.module }
    static func resolve(mainResourceURL: URL?, fallback: () -> Bundle) -> Bundle {
        if let url = mainResourceURL?.appendingPathComponent("TogetherCore_TogetherCore.bundle", isDirectory: true),
           let bundle = Bundle(url: url) { return bundle }
        return fallback()
    }
}
