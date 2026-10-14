import Foundation

public struct FinanceMonth: Codable, Equatable, Comparable, Hashable, Sendable {
    public let year: Int
    public let month: Int
    public init(year: Int, month: Int) { self.year = year; self.month = month }
    public init(_ date: Date, timeZone: String) {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: timeZone) ?? TimeZone(secondsFromGMT: 0)!
        let p = c.dateComponents([.year, .month], from: date); year = p.year!; month = p.month!
    }
    public init?(iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1900...3000).contains(parts[0]), (1...12).contains(parts[1]) else { return nil }
        self.init(year: parts[0], month: parts[1])
    }
    public var iso: String { String(format: "%04d-%02d", year, month) }
    public var next: FinanceMonth { month == 12 ? .init(year: year + 1, month: 1) : .init(year: year, month: month + 1) }
    public var previous: FinanceMonth { month == 1 ? .init(year: year - 1, month: 12) : .init(year: year, month: month - 1) }
    public static func < (a: Self, b: Self) -> Bool { a.iso < b.iso }
}
public enum FinancialCalendar {
    public static func calendar(_ zone: String) throws -> Calendar {
        guard let timeZone = TimeZone(identifier: zone) else { throw FinanceError.invalidDate }
        var c = Calendar(identifier: .gregorian); c.timeZone = timeZone; return c
    }
    public static func day(in month: FinanceMonth, requested: Int, timeZone: String) throws -> CivilDate {
        guard (1...31).contains(requested), (1900...3000).contains(month.year), (1...12).contains(month.month) else { throw FinanceError.invalidDate }
        let c = try calendar(timeZone)
        guard let first = c.date(from: DateComponents(year: month.year, month: month.month, day: 1)), let range = c.range(of: .day, in: .month, for: first) else { throw FinanceError.invalidDate }
        return CivilDate(year: month.year, month: month.month, day: min(requested, range.count))
    }
    public static func instant(_ day: CivilDate, timeZone: String, minuteOfDay: Int? = nil) throws -> Date {
        guard day.isValid, minuteOfDay.map({ (0..<1440).contains($0) }) ?? true else { throw FinanceError.invalidDate }
        let c = try calendar(timeZone)
        guard let start = c.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) else { throw FinanceError.invalidDate }
        guard let minuteOfDay else { return c.startOfDay(for: start) }
        guard let date = c.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: start, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward) else { throw FinanceError.invalidDate }
        return date
    }
    public static func shifted(_ day: CivilDate, days: Int, timeZone: String) throws -> CivilDate {
        let c = try calendar(timeZone), d = try instant(day, timeZone: timeZone)
        guard let next = c.date(byAdding: .day, value: days, to: d) else { throw FinanceError.invalidDate }
        return CivilDate(next, timeZone: c.timeZone)
    }
    public static func cycle(containing date: Date, startDay: Int, timeZone: String) throws -> DateInterval {
        let current = FinanceMonth(date, timeZone: timeZone)
        let anchor = try instant(day(in: current, requested: startDay, timeZone: timeZone), timeZone: timeZone)
        let month = date < anchor ? current.previous : current
        let start = try instant(day(in: month, requested: startDay, timeZone: timeZone), timeZone: timeZone)
        let end = try instant(day(in: month.next, requested: startDay, timeZone: timeZone), timeZone: timeZone)
        return DateInterval(start: start, end: end)
    }
}
