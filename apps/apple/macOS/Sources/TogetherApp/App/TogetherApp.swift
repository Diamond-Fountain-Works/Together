#if os(macOS)
import SwiftUI
import Combine
import TogetherCore
import AppKit

@main struct TogetherApp: App {
    @StateObject private var session = TogetherSceneSession()
    private var model: ApplicationModel? {
        get { session.model }
        nonmutating set { session.model = newValue }
    }
    @State private var startupError: String?
    @State private var needsIdentityMigration = false
    @ObservedObject private var languageSettings = LanguageSettings.shared
    @AppStorage("appearance") private var appearance = "system"
    @NSApplicationDelegateAdaptor(TogetherAppDelegate.self) private var delegate
    init() {
        #if TOGETHER_NATIVE_P2P_QA
        do { let initialModel = try NativeAcceptance.build(); _session = StateObject(wrappedValue: TogetherSceneSession(model: initialModel)) }
        catch { _startupError = State(initialValue: Copy.userError(error)) }
        return
        #else
        #if TOGETHER_UI_TEST_HOST
        if !UIFixture.enabled { _startupError=State(initialValue:Copy.text("qa.error.isolatedLaunch")) }
        return
        #else
        #if DEBUG
        if UIFixture.enabled { return }
        #endif
        do {
            #if TOGETHER_NATIVE_TRANSPORT
            let initialModel = try NativeProduction.build()
            #else
            let initialModel = ApplicationModel(engine: try ReplicaEngine.production())
            #endif
            _session = StateObject(wrappedValue: TogetherSceneSession(model: initialModel))
        }
        catch IdentityStorageError.legacyMigrationRequired { _needsIdentityMigration = State(initialValue: true) }
        catch { _startupError = State(initialValue: Copy.userError(error)) }
        #endif
        #endif
    }
    var body: some Scene {
        WindowGroup("Together") {
            Group {
            #if DEBUG
            if UIFixture.enabled { UIFixtureRoot(model: $session.model).frame(minWidth: 900, minHeight: 620) }
            else { normalContent }
            #else
            normalContent
            #endif
            }.environment(\.locale, languageSettings.language.locale)
        }
        .commands { appCommands }
    }
    @ViewBuilder private var normalContent: some View {
            if let model {
                TogetherSessionView(model: model) { self.model = $0 }
                    .id(model.engine.identity.descriptor.deviceId)
                    .frame(minWidth: 900, idealWidth: 1100, minHeight: 620, idealHeight: 760)
                    .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
            } else {
                StartupIdentityView(needsMigration: needsIdentityMigration, error: startupError) {
                    do {
                        #if TOGETHER_NATIVE_P2P_QA
                        model = try NativeAcceptance.build()
                        #elseif TOGETHER_NATIVE_TRANSPORT
                        model = try NativeProduction.build(migrateLegacyIdentity: needsIdentityMigration)
                        #else
                        model = ApplicationModel(engine: try ReplicaEngine.production(migrateLegacyIdentity: needsIdentityMigration))
                        #endif
                        startupError = nil; needsIdentityMigration = false
                    } catch { startupError = Copy.userError(error) }
                }
            }
        }
    @CommandsBuilder private var appCommands: some Commands {
            CommandGroup(replacing: .newItem) {
                Button(Copy.text("copy.action.718e58cc20d6")) { model?.newTask() }
                    .keyboardShortcut("n", modifiers: .command).disabled(model == nil || model?.sheet != nil)
                Divider()
                Button(Copy.text("copy.action.fb24523a7f34")) { model?.show(.giftEditor(nil)) }
                    .keyboardShortcut("l", modifiers: [.command, .shift]).disabled(model == nil)
            }
            CommandGroup(after: .windowArrangement) {
                Button(Copy.text("device.title")) { model?.show(.devices) }.disabled(model == nil)
                Button(Copy.text("sync.changes.title")) {model?.show(.changes)}.disabled(model==nil)
                Button(Copy.text("copy.action.1555373b2da2")) { model?.show(.giftHistory) }.keyboardShortcut("l", modifiers: [.command, .option]).disabled(model == nil)
            }
            CommandGroup(replacing: .help) {
                Button(Copy.text("copy.action.58383b09e244")) { model?.show(.advisor) }.disabled(model == nil)
                Button(Copy.text("copy.action.561b17edc33d")) { model?.show(.whatsNew) }.disabled(model == nil)
            }
            CommandGroup(replacing: .appSettings) {
                Button(Copy.text("nav.settings")) { model?.section = .settings; NSApp.activate(ignoringOtherApps: true) }.keyboardShortcut(",", modifiers: .command).disabled(model == nil)
            }
    }
}
/// The Scene owns the optional session and follows its current model so native
/// Commands and their enabled states refresh after modal and replica changes.
@MainActor final class TogetherSceneSession: ObservableObject {
    @Published var model: ApplicationModel? { didSet { observeCurrentModel() } }
    private var modelChanges: AnyCancellable?
    init(model: ApplicationModel? = nil) { self.model = model; observeCurrentModel() }
    private func observeCurrentModel() {
        modelChanges = model?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
}

@MainActor final class TogetherAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

#endif
