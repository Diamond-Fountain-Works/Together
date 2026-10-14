import Foundation

public enum RecurrenceCalculator {
    public static func instanceId(ruleId: UUID, occurrenceIndex: Int) -> UUID { StableID.make("recurrence:\(ruleId.uuidString):\(occurrenceIndex)") }
    public static func flexibleInstanceId(parentTaskId: UUID) -> UUID { StableID.make("flexible-next:\(parentTaskId.uuidString)") }
    public static func date(rule: RecurrenceRule, occurrenceIndex: Int) -> Date? {
        guard rule.mode == .regular, occurrenceIndex >= 0, let zone = TimeZone(identifier: rule.timeZoneIdentifier) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let amount = rule.interval * occurrenceIndex
        if rule.unit == .month {
            let anchor = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: rule.anchorAt)
            guard let monthStart = calendar.date(from: DateComponents(year: anchor.year, month: anchor.month, day: 1)),
                  let targetMonth = calendar.date(byAdding: .month, value: amount, to: monthStart),
                  let days = calendar.range(of: .day, in: .month, for: targetMonth) else { return nil }
            let ym = calendar.dateComponents([.year, .month], from: targetMonth)
            let components = DateComponents(timeZone: zone, year: ym.year, month: ym.month, day: min(anchor.day!, days.count), hour: anchor.hour, minute: anchor.minute, second: anchor.second)
            return calendar.date(from: components)
        }
        return calendar.date(byAdding: rule.unit == .day ? .day : .weekOfYear, value: amount, to: rule.anchorAt)
    }
}
