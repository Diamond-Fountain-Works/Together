import Foundation
import Darwin

/// Device-local presentation. These values never change signed operations or
/// replace the original errors used by networking diagnostics.
public extension Copy {
    /// For external error strings only. Diagnostic details stay in their
    /// original fields; user-authored content must never pass through here.
    static func userErrorMessage(_ value: String, language: AppLanguage? = nil) -> String {
        let language = language ?? LanguageSettings.shared.language
        return translatedStaticMessage(value, language: language) ?? text("presentation.error.retry", language: language)
    }
    static func time(_ value: Date, language: AppLanguage? = nil) -> String {
        let language = language ?? LanguageSettings.shared.language
        return value.formatted(Date.FormatStyle(date: .omitted, time: .shortened,
            locale: language.locale, calendar: Calendar(identifier: .gregorian), timeZone: .current))
    }

    static func date(_ value: Date, includeTime: Bool = false, language: AppLanguage? = nil) -> String {
        let language = language ?? LanguageSettings.shared.language
        return value.formatted(Date.FormatStyle(
            date: .abbreviated, time: includeTime ? .shortened : .omitted,
            locale: language.locale, calendar: Calendar(identifier: .gregorian), timeZone: .current))
    }

    /// For domain diagnostics only, never for user-authored titles or messages.
    /// Exact static matches let cached projection errors follow the UI language.
    static func domainMessage(_ value: String, language: AppLanguage? = nil) -> String {
        let language = language ?? LanguageSettings.shared.language
        switch value {
        case "操作签名或用户身份不匹配": return text("presentation.error.operationIdentity", language: language)
        case "超出本批愿望额度": return text("presentation.error.wishAllowance", language: language)
        default: return translatedStaticMessage(value, language: language) ?? value
        }
    }

    static func userError(_ error: any Error, language: AppLanguage? = nil) -> String {
        let language = language ?? LanguageSettings.shared.language
        func message(_ key: String) -> String { text(key, language: language) }
        if let error = error as? FinanceError { return message("finance.error." + error.rawValue) }
        if let error = error as? IdentityStorageError {
            switch error {
            case .legacyMigrationRequired: return message("identity.migration.guidance")
            case .legacyKeyMissing: return message("identity.error.legacyMissing")
            case .invalidFile: return message("identity.error.invalidFile")
            case .identityMismatch: return message("identity.error.mismatch")
            case .keychain: return message("identity.error.keychainMigration")
            }
        }
        if let error = error as? DeviceEnrollmentError {
            switch error {
            case .expired: return message("device.error.expired")
            case .confirmationRequired: return message("device.error.confirm")
            case .existingData: return message("device.error.existingData")
            case .invalidWorkspace: return message("device.error.workspace")
            case .identityUnavailable: return message("device.error.identityUnavailable")
            }
        }
        if let error = error as? ReplicationError {
            return message(error == .incompatibleProtocol ? "copy.error.eb6f75e7a5e4" : "copy.error.76ef9b5cd8a8")
        }
        if error is RepositoryError { return message("copy.status.492c7e8b42f9") }
        if case let TogetherError.invalid(value) = error {
            // Only exact catalog entries are translated. A domain message that
            // contains user-authored content is preserved as supplied.
            return domainMessage(value, language: language)
        }
        if error is CancellationError { return message("presentation.error.cancelled") }
        let native = error as NSError
        if native.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: native.code) {
            case .timedOut: return message("presentation.error.timeout")
            case .cancelled: return message("presentation.error.cancelled")
            case .badURL, .unsupportedURL: return message("presentation.error.address")
            case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                return message("presentation.error.certificate")
            case .notConnectedToInternet, .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost,
                 .networkConnectionLost, .internationalRoamingOff, .dataNotAllowed:
                return message("presentation.error.network")
            default: return message("presentation.error.retry")
            }
        }
        if native.domain == NSCocoaErrorDomain {
            switch CocoaError.Code(rawValue: native.code) {
            case .fileReadNoPermission, .fileWriteNoPermission: return message("presentation.error.filePermission")
            case .fileNoSuchFile, .fileReadNoSuchFile: return message("presentation.error.fileMissing")
            case .fileWriteOutOfSpace: return message("presentation.error.storage")
            case .fileWriteVolumeReadOnly: return message("presentation.error.readOnly")
            case .fileWriteFileExists: return message("presentation.error.fileExists")
            case .fileReadCorruptFile, .fileReadUnknownStringEncoding, .fileReadInapplicableStringEncoding:
                return message("presentation.error.fileDamaged")
            case .userCancelled: return message("presentation.error.cancelled")
            default: return message("presentation.error.retry")
            }
        }
        if native.domain == NSPOSIXErrorDomain {
            switch native.code {
            case Int(ENOSPC), Int(EDQUOT): return message("presentation.error.storage")
            case Int(EACCES), Int(EPERM): return message("presentation.error.filePermission")
            case Int(ENOENT): return message("presentation.error.fileMissing")
            case Int(EROFS): return message("presentation.error.readOnly")
            case Int(EEXIST): return message("presentation.error.fileExists")
            case Int(ETIMEDOUT): return message("presentation.error.timeout")
            case Int(ECONNREFUSED), Int(ECONNRESET), Int(EHOSTUNREACH), Int(ENETUNREACH): return message("presentation.error.network")
            default: break
            }
        }
        return message("presentation.error.retry")
    }
}
