import Foundation
import Darwin

/// Monotonic elapsed time that includes sleep, available before Swift's
/// ContinuousClock. It never participates in business dates or log ordering.
public struct CompatibilityDuration: Comparable, Sendable {
    let nanoseconds: Int64
    public static let zero = Self(nanoseconds: 0)
    public static func seconds<T: BinaryInteger>(_ value: T) -> Self { scaled(value, by: 1_000_000_000) }
    public static func seconds(_ value: Double) -> Self {
        if value.isNaN { return .zero }
        let nanoseconds = value * 1_000_000_000
        if nanoseconds >= Double(Int64.max) { return .init(nanoseconds: .max) }
        if nanoseconds <= Double(Int64.min) { return .init(nanoseconds: .min) }
        return .init(nanoseconds: Int64(nanoseconds))
    }
    public static func milliseconds<T: BinaryInteger>(_ value: T) -> Self { scaled(value, by: 1_000_000) }
    public var components: (seconds: Int64, attoseconds: Int64) {
        (nanoseconds / 1_000_000_000, (nanoseconds % 1_000_000_000) * 1_000_000_000)
    }
    private static func scaled<T: BinaryInteger>(_ value: T, by factor: Int64) -> Self {
        guard let integer = Int64(exactly: value) else { return .init(nanoseconds: value < 0 ? .min : .max) }
        let (result, overflow) = integer.multipliedReportingOverflow(by: factor)
        return .init(nanoseconds: overflow ? (integer < 0 ? .min : .max) : result)
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.nanoseconds < rhs.nanoseconds }
}

public struct CompatibilityClock: Sendable {
    public struct Instant: Comparable, Sendable {
        let nanoseconds: UInt64
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.nanoseconds < rhs.nanoseconds }
        public func advanced(by duration: CompatibilityDuration) -> Self {
            if duration.nanoseconds >= 0 {
                let (value, overflow) = nanoseconds.addingReportingOverflow(UInt64(duration.nanoseconds))
                return .init(nanoseconds: overflow ? .max : value)
            }
            let delta = duration.nanoseconds.magnitude
            return .init(nanoseconds: nanoseconds >= delta ? nanoseconds - delta : 0)
        }
        public func duration(to other: Self) -> CompatibilityDuration {
            let difference = nanoseconds <= other.nanoseconds ? other.nanoseconds - nanoseconds : nanoseconds - other.nanoseconds
            let bounded = Int64(min(difference, UInt64(Int64.max)))
            return .init(nanoseconds: nanoseconds <= other.nanoseconds ? bounded : -bounded)
        }
    }
    private static let timebase: mach_timebase_info_data_t = {
        var value = mach_timebase_info_data_t(); mach_timebase_info(&value); return value
    }()
    public init() {}
    public static var now: Instant {
        let full = mach_continuous_time().multipliedFullWidth(by: UInt64(timebase.numer))
        return .init(nanoseconds: UInt64(timebase.denom).dividingFullWidth(full).quotient)
    }
    public var now: Instant { Self.now }
    public static func sleep(for duration: CompatibilityDuration) async throws {
        try Task.checkCancellation()
        guard duration.nanoseconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(duration.nanoseconds))
    }
    public func sleep(until deadline: Instant) async throws {
        // Task.sleep can resume after the Mac wakes; compare the continuous
        // clock again rather than adding a wall-clock-derived delay.
        while Self.now < deadline { try await Self.sleep(for: Self.now.duration(to: deadline)) }
    }
}
