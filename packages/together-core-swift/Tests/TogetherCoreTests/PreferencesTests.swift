import Foundation
import Testing
@testable import TogetherCore

@Suite("Launch Preferences") @MainActor struct PreferencesTests {
    @Test func initialSetupIndependentAndPersistent() {
        let name = "Together-setup-test-\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = LocalAppPreferences(defaults: defaults)
        #expect(!prefs.hasCompletedInitialSetup)
        prefs.finishAdvisor(neverAgain: true)
        #expect(!prefs.hasCompletedInitialSetup)
        prefs.finishInitialSetup()
        let reopened = LocalAppPreferences(defaults: defaults)
        #expect(reopened.hasCompletedInitialSetup && reopened.neverShowAdvisorAgain)
    }
    @Test func firstSixtyDaysAndPermanentOptOut() throws {
        let suite = "together-tests-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let p = LocalAppPreferences(defaults: defaults), start = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(p.processLaunch(version: "0.0.1", now: start) == [.advisor])
        p.finishAdvisor(neverAgain: false)
        #expect(p.processLaunch(version: "0.0.1", now: start.addingTimeInterval(59 * 86400)) == [])
        #expect(p.processLaunch(version: "0.0.1", now: start.addingTimeInterval(119 * 86400)) == [.advisor])
        p.finishAdvisor(neverAgain: true)
        p.finishAdvisor(neverAgain: false)
        #expect(p.neverShowAdvisorAgain)
        #expect(p.processLaunch(version: "0.0.2", now: start.addingTimeInterval(200 * 86400)) == [.whatsNew])
        #expect(p.processLaunch(version: "0.0.2", now: start.addingTimeInterval(201 * 86400)) == [])
    }
    @Test func simultaneousSheetsOrdered() {
        let suite = "together-tests-\(UUID())", d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let p = LocalAppPreferences(defaults: d), start = Date(timeIntervalSince1970: 1_790_000_000)
        _ = p.processLaunch(version: "0.0.1", now: start); p.finishAdvisor(neverAgain: false)
        #expect(p.processLaunch(version: "0.0.2", now: start.addingTimeInterval(60 * 86400)) == [.whatsNew, .advisor])
    }
}
