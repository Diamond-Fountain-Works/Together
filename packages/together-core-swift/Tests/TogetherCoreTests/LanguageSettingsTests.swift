import Foundation
import Combine
import Testing
@testable import TogetherCore

@Suite("Interface Language") struct LanguageSettingsTests {
    @Test func resolveSavedChoiceAndSystemLanguage() {
        #expect(AppLanguage.resolve(saved: "en", preferredLanguages: ["zh-CN"]) == .english)
        #expect(AppLanguage.resolve(saved: "zh-Hans", preferredLanguages: ["en-US"]) == .chinese)
        #expect(AppLanguage.resolve(saved: "unsupported", preferredLanguages: ["zh-TW"]) == .chinese)
        #expect(AppLanguage.resolve(saved: nil, preferredLanguages: ["fr-FR"]) == .english)
        #expect(AppLanguage.resolve(saved: nil, preferredLanguages: []) == .english)
    }

    @Test func preferencePersistsWithoutChangingOtherPreferences() throws {
        let suite = "together-tests-language-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("preserved", forKey: "unrelated-setting")
        let settings = LanguageSettings(defaults: defaults, preferredLanguages: ["en"])
        settings.language = .chinese
        #expect(LanguageSettings(defaults: defaults, preferredLanguages: ["en"]).language == .chinese)
        settings.language = .english
        #expect(LanguageSettings(defaults: defaults, preferredLanguages: ["zh-Hans"]).language == .english)
        #expect(defaults.string(forKey: "unrelated-setting") == "preserved")
    }

    @Test func observableLanguageInvalidatesDisplayReads() throws {
        final class Flag: @unchecked Sendable {
            let lock = NSLock()
            private var value = false
            func set() { lock.withLock { value = true } }
            var isSet: Bool { lock.withLock { value } }
        }
        let suite = "together-tests-language-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = LanguageSettings(defaults: defaults, preferredLanguages: ["zh-Hans"])
        let changed = Flag()
        let subscription = settings.objectWillChange.sink { changed.set() }
        defer { subscription.cancel() }
        _ = settings.language
        settings.language = .english
        #expect(changed.isSet)
        #expect(settings.language == .english)
    }

    @Test func explicitLocaleLookupAndFormattingDoNotCrossLanguages() {
        #expect(Copy.text("nav.home", language: .chinese) == "首页")
        #expect(Copy.text("nav.home", language: .english) == "Home")
        #expect(Copy.text("language.option.en", language: .chinese) == "英语")
        #expect(Copy.text("language.option.zh-Hans", language: .english) == "Chinese")
        #expect(Copy.format("gift.title.known.text", language: .english, "your girl") == "A love note from your girl, just for you ♡")
        #expect(Copy.format("gift.title.known.text", language: .chinese, "小女友") == "这是小女友专门送给你的情话 ♡")
    }

    @Test func romanticCopyKeepsSenderIdentityAndAttachmentMeaning() {
        #expect(LoveCopy.ending(sender: .boyfriend, language: .english).contains("him"))
        #expect(LoveCopy.ending(sender: .girlfriend, language: .english).contains("her"))
        #expect(LoveCopy.ending(sender: .unknown, language: .english).contains("them"))
        #expect(LoveCopy.title(sender: .unknown, hasText: true, language: .chinese).contains("对方"))
        for role in RelationshipLabel.allCases {
            let text = LoveCopy.title(sender: role, hasText: true, language: .english)
            let attachment = LoveCopy.title(sender: role, hasText: false, language: .english)
            #expect(text.range(of: "[\\p{Han}]", options: .regularExpression) == nil)
            #expect(attachment.contains("gift"))
            #expect(!attachment.contains("love note"))
        }
    }
}
