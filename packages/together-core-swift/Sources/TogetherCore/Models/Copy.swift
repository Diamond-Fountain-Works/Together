import Foundation

public enum Copy {
    private static let sourceValues: [String: String] = {
        guard let url = Bundle.module.url(forResource: "UI", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url), let source = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = source["strings"] as? [String: [String: Any]] else { return [:] }
        return strings.compactMapValues { entry in
            let localizations = entry["localizations"] as? [String: [String: Any]]
            let unit = localizations?["zh-Hans"]?["stringUnit"] as? [String: String]
            return unit?["value"]
        }
    }()
    public static func text(_ key: String) -> String {
        let value = NSLocalizedString(key, tableName: "UI", bundle: .module, value: sourceValues[key] ?? key, comment: "")
        if value != key { return value }
        if let path = Bundle.module.path(forResource: "zh-Hans", ofType: "lproj"), let source = Bundle(path: path) {
            return source.localizedString(forKey: key, value: sourceValues[key] ?? key, table: "UI")
        }
        return sourceValues[key] ?? key
    }
    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: "zh_CN"), arguments: arguments)
    }
}
