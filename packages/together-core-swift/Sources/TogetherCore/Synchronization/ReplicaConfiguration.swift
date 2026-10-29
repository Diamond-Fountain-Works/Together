import Foundation

public struct RecurrenceDraft: Sendable {
    public var mode: RecurrenceMode
    public var unit: RecurrenceUnit
    public var interval: Int
    public var timeZoneIdentifier: String
    public init(mode: RecurrenceMode, unit: RecurrenceUnit = .day, interval: Int = 1, timeZoneIdentifier: String = TimeZone.current.identifier) {
        self.mode = mode; self.unit = unit; self.interval = interval; self.timeZoneIdentifier = timeZoneIdentifier
    }
}
public struct ListenerSettings: Codable, Sendable {
    public var host: String
    public var port: UInt16
    public var enabled: Bool
    public init(host: String = "127.0.0.1", port: UInt16 = 58431, enabled: Bool = false) { self.host = host; self.port = port; self.enabled = enabled }
}
public enum TogetherError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(text) = self { text } else { nil } }
}
