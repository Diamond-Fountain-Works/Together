import SwiftUI
import TogetherCore

struct RootView: View {
    @ObservedObject var model: ApplicationModel
    @Environment(\.colorScheme) private var scheme
    @TogetherMotionPreference private var reduceMotion
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        navigation
            .togetherTint(TogetherTheme.rose)
            .togetherAnimation(TogetherTheme.motion(reduceMotion), value: model.section)
            .transaction { if reduceMotion { $0.animation = nil } }
            .sheet(item: $model.sheet, onDismiss: model.sheetDismissed) { sheet in
                sheetContent(sheet).togetherTint(TogetherTheme.rose)
                    .environment(\.locale, LanguageSettings.shared.language.locale)
            }
            .alert(isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Alert(title: Text(Copy.text("copy.guidance.1f0a01abb190")), message: Text(model.errorMessage ?? ""),
                      dismissButton: .default(Text(Copy.text("copy.action.f867f3417859"))) { model.errorMessage = nil })
            }
            .togetherTask { model.start() }
            .onChange(of: model.completedSyncCount) { _ in model.checkStartupGifts() }
            .onChange(of: model.engine.changeNumber) { _ in model.checkStartupGifts(); model.refreshFinancialState(); model.refreshSharedChanges() }
            .onChange(of: model.section) { _ in model.noteUserInteraction() }
            .onReceive(NotificationCenter.default.publisher(for: TogetherPlatform.becameActive)) { _ in model.currentDate = model.engine.dateProvider.now() }
    }

    @ViewBuilder private var navigation: some View {
        #if os(macOS)
        if #available(macOS 13, *) {
            NavigationSplitView { sidebar.navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270) } detail: { detail }
        } else {
            NavigationView { sidebar.frame(minWidth: 190, idealWidth: 220, maxWidth: 270); detail }
        }
        #else
        if horizontalSizeClass == .regular {
            if #available(iOS 16, *) {
                NavigationSplitView { sidebar } detail: { detail }
            } else {
                NavigationView { sidebar; detail }.navigationViewStyle(DoubleColumnNavigationViewStyle())
            }
        } else {
            NavigationView {
                detail.toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Menu {
                            ForEach(AppSection.allCases) { section in
                                Button { model.section = section } label: { Label(section.title, systemImage: TogetherSymbols.name(section.icon)) }
                            }
                        } label: { Image(systemName: TogetherSymbols.name("sidebar.left")).accessibilityLabel(Copy.text("navigation.menu")) }
                        .accessibilityIdentifier("navigation.menu")
                    }
                }
            }.navigationViewStyle(StackNavigationViewStyle())
        }
        #endif
    }
    private var sectionBinding: Binding<AppSection?> {
        Binding(get: { model.section }, set: { if let section = $0 { model.section = section } })
    }
    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: sectionBinding) {
                ForEach([AppSection.home, .plans, .wishes, .finances]) { sidebarRow($0) }
            }.listStyle(SidebarListStyle())
            Divider().padding(.horizontal, 14)
            List(selection: sectionBinding) {
                ForEach([AppSection.connection, .settings]) { sidebarRow($0) }
            }.listStyle(SidebarListStyle()).frame(height: 100)
            HStack {
                Circle().fill(model.isOnline ? Color.green : Color.secondary).frame(width: 6, height: 6)
                Text(model.connectionState.displayName).font(.caption).foregroundColor(.secondary)
                Spacer()
            }.padding(18)
        }
    }
    private var detail: some View {
        ZStack(alignment: .topLeading) {
            TogetherTheme.background(scheme).ignoresSafeArea()
            VStack(spacing: 0) {
                if !model.changeBannerEvents.isEmpty { SharedChangeBanner(model: model) }
                else if !model.financialBannerChanges.isEmpty { FinanceChangeBanner(model: model) }
                page.id(model.section == .wishes ? .plans : model.section)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(x: 12)))
            }
        }
        .navigationTitle(model.section.title)
        .toolbar { workspaceActions }
    }
    @ToolbarContentBuilder private var workspaceActions: some ToolbarContent {
        ToolbarItemGroup {
            if model.section == .plans && model.taskFilter == .pending {
                TogetherIconButton(Copy.text("copy.action.718e58cc20d6"), systemImage: TogetherSymbols.name("plus")) { model.newTask() }
                    .disabled(model.sheet != nil).accessibilityIdentifier("task.new")
            } else if model.section == .wishes {
                TogetherIconButton(Copy.text("plans.action.addWishes"), systemImage: TogetherSymbols.name("plus")) { model.show(.grant) }
                    .disabled(model.engine.context.peer == nil || model.sheet != nil).accessibilityIdentifier("wish.grant.new")
            } else if model.section == .finances {
                TogetherIconButton(Copy.text("finance.action.settings"), systemImage: TogetherSymbols.name("slider.horizontal.3")) { model.showFinance(.settings) }.accessibilityIdentifier("finance.settings")
                TogetherIconButton(Copy.text("finance.action.changes"), systemImage: TogetherSymbols.name("clock.arrow.circlepath")) { model.showFinance(.changes) }.accessibilityIdentifier("finance.changes")
                TogetherIconButton(Copy.text("finance.action.new." + model.financeTab.rawValue), systemImage: TogetherSymbols.name("plus")) {
                    switch model.financeTab { case .reserves: model.showFinance(.deposit(nil, false)); case .expenses: model.showFinance(.expense(nil)); case .bills: model.showFinance(.bill(nil)) }
                }.disabled(model.sheet != nil).accessibilityIdentifier("finance.new")
            }
            #if os(iOS)
            Menu {
                Button(Copy.text("copy.action.fb24523a7f34")) { model.show(.giftEditor(nil)) }
                Button(Copy.text("copy.action.1555373b2da2")) { model.show(.giftHistory) }
                Divider()
                Button(Copy.text("sync.changes.title")) { model.show(.changes) }
                Button(Copy.text("device.title")) { model.show(.devices) }
                Button(Copy.text("copy.action.58383b09e244")) { model.show(.advisor) }
                Button(Copy.text("copy.action.561b17edc33d")) { model.show(.whatsNew) }
            } label: { Image(systemName: TogetherSymbols.name("ellipsis.circle")).accessibilityLabel(Copy.text("navigation.more")) }
            .disabled(model.sheet != nil).accessibilityIdentifier("navigation.more")
            #endif
        }
    }
    @ViewBuilder private func sheetContent(_ sheet: AppSheet) -> some View {
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
        case .initialSetup: InitialSetupView(model: model).togetherInteractiveDismissDisabled()
        case .giftEditor(let reply): GiftEditorView(model: model, replyTo: reply)
        case .giftHistory: GiftHistoryView(model: model)
        case .giftReveal(let ids, let automatic): GiftRevealView(model: model, giftIds: ids, automatic: automatic)
        case .finance(let sheet): FinanceSheetView(model: model, sheet: sheet)
        case .changes: SharedChangeHistoryView(model: model)
        case .devices: DeviceManagementView(model: model)
        }
    }
    @ViewBuilder private var page: some View {
        switch model.section {
        case .home: HomeView(model: model)
        case .plans, .wishes: OurPlansView(model: model)
        case .finances: OurFinancesView(model: model)
        case .connection: ConnectionView(model: model)
        case .settings: SettingsView(model: model)
        }
    }
    private func sidebarRow(_ section: AppSection) -> some View {
        Button { model.section = section } label: { Label(section.title, systemImage: TogetherSymbols.name(section.icon)).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading) }
            .buttonStyle(PlainButtonStyle()).tag(section)
            .accessibilityIdentifier("nav." + section.rawValue.lowercased())
    }
}

/// A scene may own an optional model in State. Observe the concrete session here
/// so an enrollment replacement is received on old systems as well as modern UI.
struct TogetherSessionView: View {
    @ObservedObject var model: ApplicationModel
    let replace: (ApplicationModel) -> Void
    var body: some View {
        RootView(model: model)
            .onChange(of: model.requestedReplica?.identity.descriptor.deviceId) { _ in
                if let engine = model.requestedReplica { replace(model.replacement(with: engine)) }
            }
    }
}
