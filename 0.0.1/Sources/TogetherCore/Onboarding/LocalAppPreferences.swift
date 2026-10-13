import Foundation

public enum LaunchPresentation: String, Identifiable, Sendable { case advisor, whatsNew; public var id: String { rawValue } }
@MainActor public final class LocalAppPreferences {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var hasCompletedOnboarding: Bool { defaults.bool(forKey: "hasCompletedOnboarding") }
    public var neverShowAdvisorAgain: Bool { defaults.bool(forKey: "neverShowAdvisorAgain") }
    public var lastAppOpenedAt: Date? { defaults.object(forKey: "lastAppOpenedAt") as? Date }
    public var advisorVersion: Int { defaults.integer(forKey: "advisorVersion") }
    public var lastSeenWhatsNewVersion: String? { defaults.string(forKey: "lastSeenWhatsNewVersion") }
    public var hasCompletedInitialSetup: Bool { defaults.bool(forKey: "hasCompletedInitialSetup") }
    public func finishInitialSetup() { defaults.set(true, forKey: "hasCompletedInitialSetup") }

    public func processLaunch(version: String, now: Date = .now) -> [LaunchPresentation] {
        let previous = lastAppOpenedAt
        let first = previous == nil
        let stale = previous.map { now.timeIntervalSince($0) >= 60 * 24 * 60 * 60 } ?? false
        let advisor = !neverShowAdvisorAgain && (first || !hasCompletedOnboarding || stale)
        let whatsNew = !first && lastSeenWhatsNewVersion != version
        defaults.set(now, forKey: "lastAppOpenedAt")
        if first || whatsNew { defaults.set(version, forKey: "lastSeenWhatsNewVersion") }
        var queue: [LaunchPresentation] = []
        if whatsNew { queue.append(.whatsNew) }
        if advisor { queue.append(.advisor) }
        return queue
    }
    public func finishAdvisor(neverAgain: Bool) {
        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.set(1, forKey: "advisorVersion")
        if neverAgain { defaults.set(true, forKey: "neverShowAdvisorAgain") }
    }
    public func sawRelease(version: String) { defaults.set(version, forKey: "lastSeenWhatsNewVersion") }
}
