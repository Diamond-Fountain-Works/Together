import SwiftUI
import TogetherCore
import AppKit

struct RootView: View {
    @Bindable var model: ApplicationModel
    @Environment(\.colorScheme) private var scheme
    @TogetherMotionPreference private var reduceMotion

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $model.section) {
                    ForEach([AppSection.home, .plans, .wishes]) { sidebarRow($0) }
                }
                .listStyle(.sidebar)
                Divider().padding(.horizontal, 14)
                List(selection: $model.section) {
                    ForEach([AppSection.connection, .settings]) { sidebarRow($0) }
                }.listStyle(.sidebar).frame(height: 100)
                HStack {
                    Circle().fill(model.network.isOnline ? .green : .secondary).frame(width: 6, height: 6)
                    Text(model.network.state.displayName).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }.padding(18)
            }.navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
        } detail: {
            ZStack(alignment: .topLeading) {
                TogetherTheme.background(scheme).ignoresSafeArea()
                page.id(model.section == .wishes ? .plans : model.section)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(x: 12)))
            }
            .navigationTitle(model.section.title)
            .toolbar {
                if model.section == .plans && model.taskFilter == .pending {
                    Button(Copy.text("copy.action.718e58cc20d6"), systemImage: "plus") { model.newTask() }
                        .disabled(model.sheet != nil).accessibilityIdentifier("task.new")
                } else if model.section == .wishes {
                    Button(Copy.text("plans.action.addWishes"), systemImage: "plus") { model.show(.grant) }
                        .disabled(model.engine.peer == nil || model.sheet != nil).accessibilityIdentifier("wish.grant.new")
                }
            }
        }
        .tint(TogetherTheme.rose)
        .animation(TogetherTheme.motion(reduceMotion), value: model.section)
        .transaction { if reduceMotion { $0.animation = nil } }
        .sheet(item: $model.sheet, onDismiss: model.sheetDismissed) { sheet in
            Group {
            switch sheet {
            case .task(let id): TaskEditorView(model: model, task: id.flatMap { model.engine.snapshot.tasks[$0] })
            case .nextTime(let id): NextTimeView(model: model, taskId: id)
            case .grant: GrantEditorView(model: model)
            case .grantDetail(let id): GrantDetailView(model: model, grantId: id)
            case .wish(let id): WishEditorView(model: model, grantId: id)
            case .adjustment(let id): GrantAdjustmentView(model: model, grantId: id)
            case .crop: AvatarCropView(model: model)
            case .advisor: AdvisorView(model: model)
            case .whatsNew: WhatsNewView(model: model)
            case .initialSetup: InitialSetupView(model: model).interactiveDismissDisabled()
            case .giftEditor(let reply): GiftEditorView(model: model, replyTo: reply)
            case .giftHistory: GiftHistoryView(model: model)
            case .giftReveal(let ids, let automatic): GiftRevealView(model: model, giftIds: ids, automatic: automatic)
            }
            }.tint(TogetherTheme.rose)
        }
        .alert(Copy.text("copy.guidance.1f0a01abb190"), isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(Copy.text("copy.action.f867f3417859")) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .task { model.start() }
        .onChange(of: model.network.completedSyncCount) { _, _ in model.checkStartupGifts() }
        .onChange(of: model.engine.changeNumber) { _, _ in model.checkStartupGifts() }
        .onChange(of: model.section) { _, _ in model.noteUserInteraction() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.currentDate = model.engine.dateProvider.now() }
    }

    @ViewBuilder private var page: some View {
        switch model.section {
        case .home: HomeView(model: model)
        case .plans, .wishes: OurPlansView(model: model)
        case .connection: ConnectionView(model: model)
        case .settings: SettingsView(model: model)
        }
    }
    private func sidebarRow(_ section: AppSection) -> some View {
        Label(section.title, systemImage: section.icon)
            .padding(.vertical, 6).tag(section)
            .accessibilityIdentifier("nav." + section.rawValue.lowercased())
    }
}
