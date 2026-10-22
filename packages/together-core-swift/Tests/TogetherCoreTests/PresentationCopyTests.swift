import Foundation
import Darwin
import Testing
@testable import TogetherCore

@Suite("Localized dates and error presentation")
struct PresentationCopyTests {
    @Test(arguments: AppLanguage.allCases)
    func domainErrorsRespectExplicitLanguage(_ language: AppLanguage) {
        #expect(Copy.userError(FinanceError.invalidAmount, language: language)
                == Copy.text("finance.error.invalidAmount", language: language))
        #expect(Copy.userError(IdentityStorageError.identityMismatch, language: language)
                == Copy.text("identity.error.mismatch", language: language))
        #expect(Copy.userError(DeviceEnrollmentError.expired, language: language)
                == Copy.text("device.error.expired", language: language))
        #expect(Copy.userError(ReplicationError.incompatibleProtocol, language: language)
                == Copy.text("copy.error.eb6f75e7a5e4", language: language))
        #expect(Copy.userError(RepositoryError.reusedOperationId, language: language)
                == Copy.text("copy.status.492c7e8b42f9", language: language))
    }

    @Test(arguments: AppLanguage.allCases)
    func nativeErrorsUseActionableCatalogMessages(_ language: AppLanguage) {
        let examples: [(any Error, String)] = [
            (URLError(.timedOut), "presentation.error.timeout"),
            (URLError(.notConnectedToInternet), "presentation.error.network"),
            (URLError(.serverCertificateUntrusted), "presentation.error.certificate"),
            (CocoaError(.fileReadNoPermission), "presentation.error.filePermission"),
            (CocoaError(.fileWriteOutOfSpace), "presentation.error.storage"),
            (CocoaError(.fileReadNoSuchFile), "presentation.error.fileMissing"),
            (CocoaError(.fileWriteFileExists), "presentation.error.fileExists"),
            (CocoaError(.fileReadCorruptFile), "presentation.error.fileDamaged"),
            (CocoaError(.fileWriteVolumeReadOnly), "presentation.error.readOnly"),
            (NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)), "presentation.error.storage"),
            (NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)), "presentation.error.filePermission"),
            (NSError(domain: NSPOSIXErrorDomain, code: Int.max), "presentation.error.retry"),
            (CancellationError(), "presentation.error.cancelled"),
        ]
        for (error, key) in examples {
            let message = Copy.userError(error, language: language)
            #expect(message == Copy.text(key, language: language))
            #expect(message != key)
        }
    }

    @Test(arguments: AppLanguage.allCases)
    func externalErrorDetailsAreNotDisplayed(_ language: AppLanguage) {
        let diagnostic = "Synthetic provider diagnostic with /private/example and a secret-shaped value"
        let error = NSError(domain: "example.synthetic-provider", code: 123,
                            userInfo: [NSLocalizedDescriptionKey: diagnostic])
        #expect(Copy.userError(error, language: language)
                == Copy.text("presentation.error.retry", language: language))
        #expect(!Copy.userError(error, language: language).contains(diagnostic))
        #expect(error.localizedDescription == diagnostic)
    }

    @Test func cachedDomainErrorsFollowTheRequestedLanguage() {
        let key = "copy.error.c9e9d90c0c38"
        let chinese = Copy.text(key, language: .chinese)
        let english = Copy.text(key, language: .english)
        #expect(Copy.userError(TogetherError.invalid(chinese), language: .english) == english)
        #expect(Copy.userError(TogetherError.invalid(english), language: .chinese) == chinese)
        #expect(Copy.domainMessage("超出本批愿望额度", language: .english)
                == Copy.text("presentation.error.wishAllowance", language: .english))
        #expect(Copy.domainMessage("操作签名或用户身份不匹配", language: .english)
                == Copy.text("presentation.error.operationIdentity", language: .english))
    }

    @Test func dynamicDomainMessagesArePreserved() {
        let value = "A user-authored record title and its context: 一起去旅行"
        #expect(Copy.userError(TogetherError.invalid(value), language: .english) == value)
        #expect(Copy.userError(TogetherError.invalid(value), language: .chinese) == value)
    }

    @Test func civilDatesUseGregorianCalendarWithoutChangingTheDay() throws {
        let civil = try #require(CivilDate(iso: "2024-02-29"))
        let chinese = civil.display(language: .chinese)
        let english = civil.display(language: .english)
        #expect(chinese.contains("2024") && chinese.contains("2月") && chinese.contains("29"))
        #expect(english.contains("2024") && english.contains("Feb") && english.contains("29"))
        #expect(!english.contains("年") && !english.contains("月") && !english.contains("日"))
        #expect(civil.iso == "2024-02-29")
        #expect(CivilDate(year: 2024, month: 2, day: 30).display(language: .english) == "2024-02-30")
    }

    @Test func timestampsFollowExplicitLanguage() {
        let value = Date(timeIntervalSince1970: 1_791_518_400)
        let chinese = Copy.date(value, includeTime: true, language: .chinese)
        let english = Copy.date(value, includeTime: true, language: .english)
        #expect(chinese.contains("年") && chinese.contains("月"))
        #expect(english.contains("2026"))
        #expect(!english.contains("年") && !english.contains("月") && !english.contains("日"))
        #expect(chinese != english)
    }
}
