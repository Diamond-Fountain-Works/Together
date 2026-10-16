import SwiftUI
import TogetherCore
import AppKit

@main struct TogetherApp: App {
    @State private var model: ApplicationModel?
    @State private var startupError: String?
    @State private var needsIdentityMigration = false
    @AppStorage("appearance") private var appearance = "system"
    @NSApplicationDelegateAdaptor(TogetherAppDelegate.self) private var delegate
    init() {
        #if TOGETHER_UI_TEST_HOST
        if !UIFixture.enabled { _startupError=State(initialValue:Copy.text("qa.error.isolatedLaunch")) }
        return
        #else
        #if DEBUG
        if UIFixture.enabled { return }
        #endif
        do { _model = State(initialValue: ApplicationModel(engine: try ReplicaEngine.production())) }
        catch IdentityStorageError.legacyMigrationRequired { _needsIdentityMigration = State(initialValue: true) }
        catch { _startupError = State(initialValue: error.localizedDescription) }
        #endif
    }
    var body: some Scene {
        WindowGroup("Together", id: "main") {
            #if DEBUG
            if UIFixture.enabled { UIFixtureRoot(model: $model).frame(minWidth: 900, minHeight: 620) }
            else { normalContent }
            #else
            normalContent
            #endif
        }
        .defaultSize(width: 1100, height: 760)
        .commands { appCommands }
    }
    @ViewBuilder private var normalContent: some View {
            if let model {
                RootView(model: model)
                    .id(model.engine.identity.descriptor.deviceId)
                    .frame(minWidth: 900, minHeight: 620)
                    .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
                    .onChange(of: model.requestedReplica?.identity.descriptor.deviceId) { _, _ in
                        if let engine = model.requestedReplica {
                            self.model = model.replacement(with: engine)
                        }
                    }
            } else {
                StartupIdentityView(needsMigration: needsIdentityMigration, error: startupError) {
                    do {
                        model = ApplicationModel(engine: try ReplicaEngine.production(migrateLegacyIdentity: needsIdentityMigration))
                        startupError = nil; needsIdentityMigration = false
                    } catch { startupError = error.localizedDescription }
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
@MainActor final class TogetherAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
