import Foundation
import Observation

public enum AppLanguage: String, CaseIterable, Sendable {
    case chinese = "zh-Hans"
    case english = "en"

    public var locale: Locale { Locale(identifier: self == .chinese ? "zh_CN" : "en_US") }

    public static func resolve(saved: String?, preferredLanguages: [String]) -> AppLanguage {
        if let saved, let language = AppLanguage(rawValue: saved) { return language }
        return preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? .chinese : .english
    }
}

/// A device-local display preference. It never enters the operation log.
/// Observation refreshes Copy.text callers without recreating the application,
/// losing an editor draft or restarting a network session.
@Observable public final class LanguageSettings: @unchecked Sendable {
    public static let preferenceKey = "interfaceLanguage"
    public static let shared = LanguageSettings()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private var selection: AppLanguage

    public init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        selection = AppLanguage.resolve(saved: defaults.string(forKey: Self.preferenceKey), preferredLanguages: preferredLanguages)
    }

    public var language: AppLanguage {
        get {
            access(keyPath: \.language)
            return lock.withLock { selection }
        }
        set {
            withMutation(keyPath: \.language) {
                lock.withLock {
                    selection = newValue
                    defaults.set(newValue.rawValue, forKey: Self.preferenceKey)
                    defaults.set([newValue.rawValue], forKey: "AppleLanguages")
                }
            }
        }
    }
}

public enum Copy {
    // SwiftPM retains the catalog; Xcode may compile it into .lproj resources.
    private static let values: [String: [String: String]] = {
        guard let url = Bundle.module.url(forResource: "UI", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url), let source = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = source["strings"] as? [String: [String: Any]] else { return [:] }
        return strings.mapValues { entry in
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            return localizations.compactMapValues { ($0["stringUnit"] as? [String: String])?["value"] }
        }
    }()

    public static func text(_ key: String, language: AppLanguage? = nil) -> String {
        let language = language ?? LanguageSettings.shared.language
        if let value = values[key]?[language.rawValue] { return value }
        if let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj"), let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: key, table: "UI")
        }
        return key
    }

    /// Exact static-catalog lookup for domain diagnostics, never user content.
    static func translatedStaticMessage(_ message: String, language: AppLanguage) -> String? {
        for key in values.keys.sorted() where values[key]?.values.contains(message) == true {
            return text(key, language: language)
        }
        // Xcode may compile the catalog into localized strings resources.
        for sourceLanguage in AppLanguage.allCases {
            guard let path = Bundle.module.path(forResource: sourceLanguage.rawValue, ofType: "lproj"),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("UI.strings")),
                  let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
                  let key = table.keys.sorted().first(where: { table[$0] == message }) else { continue }
            return text(key, language: language)
        }
        return nil
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        let language = LanguageSettings.shared.language
        return String(format: text(key, language: language), locale: language.locale, arguments: arguments)
    }

    public static func format(_ key: String, language: AppLanguage, _ arguments: CVarArg...) -> String {
        String(format: text(key, language: language), locale: language.locale, arguments: arguments)
    }
}
