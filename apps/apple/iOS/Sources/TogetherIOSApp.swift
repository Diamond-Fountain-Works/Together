import SwiftUI
import Combine
import TogetherCore
import TogetherP2P

@main struct TogetherIOSApp: App {
    @StateObject private var session = IOSApplicationController()
    @StateObject private var language = LanguageSettings.shared
    @Environment(\.scenePhase) private var phase
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            Group {
                if let model = session.model {
                    TogetherSessionView(model: model) { session.replace(with: $0) }
                        .id(model.engine.identity.descriptor.deviceId)
                } else {
                    StartupIdentityView(needsMigration: session.needsMigration,
                                        error: session.error, retry: session.open)
                }
            }
            .environment(\.locale, language.language.locale)
            .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
            .onChange(of: phase) { value in
                if value == .active { session.model?.resumeNetworking() }
                else if value == .background { session.model?.suspendNetworking() }
            }
        }
    }
}

@MainActor final class IOSApplicationController: ObservableObject {
    @Published private(set) var model: ApplicationModel?
    @Published private(set) var error: String?
    @Published private(set) var needsMigration = false

    init() { open() }

    func replace(with model: ApplicationModel) {
        do { try Self.protectDeviceOnlyFiles(model) }
        catch { self.model?.errorMessage = Copy.userError(error); return }
        self.model?.suspendNetworking()
        self.model = model
    }

    func open() {
        do {
            #if TOGETHER_IOS_QA
            // The QA product cannot fall through into a normal workspace even
            // when accidentally opened without its explicit test launch flag.
            guard Bundle.main.bundleIdentifier == "com.together.app.ios.qa",
                  ProcessInfo.processInfo.environment["TOGETHER_IOS_QA"] == "1" else {
                throw TogetherError.invalid(Copy.text("qa.error.isolatedLaunch"))
            }
            model = try Self.isolatedSession()
            #else
            model = try NativeProduction.build(migrateLegacyIdentity: needsMigration)
            try Self.protectDeviceOnlyFiles(model!)
            #endif
            error = nil
            needsMigration = false
        } catch IdentityStorageError.legacyMigrationRequired {
            // There is no legacy Mac Keychain to migrate on an iPhone/iPad.
            // Restored data without its excluded device key must not silently
            // create a replacement identity or enter a misleading migration loop.
            needsMigration = false
            error = Copy.text("device.error.identityUnavailable")
        } catch {
            self.error = Copy.userError(error)
        }
    }

    private static func protectDeviceOnlyFiles(_ model: ApplicationModel) throws {
        guard let directory = model.engine.repository.storageURL?.deletingLastPathComponent() else {
            throw IdentityStorageError.identityMismatch
        }
        // A device key must not silently travel to a replacement device in an
        // iCloud backup. Restored business data without its key follows the
        // existing missing-identity recovery path instead of rotating identity.
        var identity = directory.appendingPathComponent("Identity", isDirectory: true)
        if FileManager.default.fileExists(atPath: identity.path) {
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try identity.setResourceValues(values)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: identity.path)
        }
    }

    #if TOGETHER_IOS_QA
    private static func isolatedSession() throws -> ApplicationModel {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("together-native-app-ios-qa-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        guard root.resolvingSymlinksInPath().deletingLastPathComponent() ==
                FileManager.default.temporaryDirectory.resolvingSymlinksInPath() else {
            throw IdentityStorageError.identityMismatch
        }
        let repository = try TogetherRepository(url: root.appendingPathComponent("Together.store"))
        let metadata = LocalIdentityMetadata()
        let identity = try DeviceIdentity.persistent(deviceId: metadata.deviceId,
            userId: metadata.userId, spaceId: metadata.spaceId,
            directory: root.appendingPathComponent("Identity"), needsExistingIdentity: false,
            protocolVersion: 3)
        try repository.save(metadata, key: "local-identity")
        let engine = try ReplicaEngine(repository: repository, identity: identity,
                                      mediaRoot: root.appendingPathComponent("Media"), enrollmentRoot: root)
        let defaults = UserDefaults(suiteName: "com.together.ios.qa." + metadata.deviceId.uuidString)!
        let model = ApplicationModel(engine: engine, defaults: defaults, useBundledService: false)
        model.nativeNetwork = try NativeAppPeerService(engine: engine, root: root)
        return model
    }
    #endif
}
