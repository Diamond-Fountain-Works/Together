import SwiftUI
import TogetherCore
#if os(iOS)
import UIKit
#endif

struct RootView: View {
    @ObservedObject var model: ApplicationModel
    @Environment(\.colorScheme) private var scheme
    @TogetherMotionPreference private var reduceMotion
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isDrawerOpen = false
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
        if usesSidebar {
            if #available(iOS 16, *) {
                NavigationSplitView { mobileNavigation(isDrawer: false) } detail: { detail }
            } else {
                NavigationView { mobileNavigation(isDrawer: false); detail }
                    .navigationViewStyle(DoubleColumnNavigationViewStyle())
            }
        } else {
            compactNavigation
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
        #if os(macOS)
        .navigationTitle(model.section.title)
        #else
        .navigationTitle(model.section == .home ? Copy.text("copy.status.330e6de0a0e3") : model.section.title)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { workspaceActions }
    }
    @ToolbarContentBuilder private var workspaceActions: some ToolbarContent {
        #if os(macOS)
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
                    createFinanceRecord()
                }.disabled(model.sheet != nil).accessibilityIdentifier("finance.new")
            }
        }
        #else
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            mobileCreateAction
            mobileActions
        }
        #endif
    }
    private func createFinanceRecord() {
        switch model.financeTab {
        case .reserves: model.showFinance(.deposit(nil, false))
        case .expenses: model.showFinance(.expense(nil))
        case .bills: model.showFinance(.bill(nil))
        }
    }

    #if os(iOS)
    // An iPhone in landscape can have a regular size class. Keep its drawer;
    // only an iPad with room for both columns receives the persistent sidebar.
    private var usesSidebar: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }
    private var compactNavigation: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                NavigationView {
                    detail.toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                model.noteUserInteraction()
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                withAnimation(TogetherTheme.quickMotion(reduceMotion)) { isDrawerOpen = true }
                            } label: {
                                Image(systemName: TogetherSymbols.name("line.3.horizontal"))
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel(Copy.text("navigation.menu"))
                            }
                            .disabled(model.sheet != nil)
                            .accessibilityIdentifier("navigation.open")
                        }
                    }
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .accessibilityHidden(isDrawerOpen)
                .allowsHitTesting(!isDrawerOpen)
                if isDrawerOpen {
                    Button(action: closeDrawer) { Color.black.opacity(0.25).ignoresSafeArea() }
                        .buttonStyle(.plain)
                        .accessibilityHidden(true)
                    mobileNavigation(isDrawer: true)
                        .frame(width: min(360, max(240, geometry.size.width - 44)))
                        .background(TogetherPlatform.surface.ignoresSafeArea())
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: -12)))
                        .accessibilityIdentifier("navigation.drawer")
                        .accessibilityAction(.escape, closeDrawer)
                        .zIndex(1)
                }
            }
        }
        .onChange(of: model.section) { _ in closeDrawer() }
        .onChange(of: model.sheet?.id) { value in if value != nil { closeDrawer() } }
        .onChange(of: horizontalSizeClass) { _ in closeDrawer() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in closeDrawer() }
    }
    private func closeDrawer() {
        withAnimation(TogetherTheme.quickMotion(reduceMotion)) { isDrawerOpen = false }
    }
    private func mobileNavigation(isDrawer: Bool) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .center) {
                        Text(Copy.text("copy.status.330e6de0a0e3")).font(.title2.weight(.semibold))
                        Spacer(minLength: 8)
                        if isDrawer {
                            Button(action: closeDrawer) {
                                Image(systemName: TogetherSymbols.name("xmark"))
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel(Copy.text("copy.action.3fd47edce45b"))
                            }.buttonStyle(.plain).accessibilityIdentifier("navigation.close")
                        }
                    }
                    VStack(spacing: 4) {
                        ForEach([AppSection.home, .plans, .wishes, .finances]) { mobileNavigationRow($0) }
                    }
                    Spacer(minLength: 24)
                    VStack(spacing: 4) {
                        Divider().padding(.bottom, 8)
                        ForEach([AppSection.connection, .settings]) { mobileNavigationRow($0) }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: TogetherSymbols.name(model.isOnline ? "circle.fill" : "circle"))
                            .font(.system(size: 7)).foregroundColor(model.isOnline ? .green : .secondary)
                            .accessibilityHidden(true)
                        Text(model.connectionState.displayName).font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }.accessibilityElement(children: .combine)
                }
                .padding(16)
                .frame(minHeight: geometry.size.height, alignment: .topLeading)
            }
        }
        .accessibilityElement(children: .contain)
    }
    private func mobileNavigationRow(_ section: AppSection) -> some View {
        Button {
            model.noteUserInteraction()
            model.section = section
            closeDrawer()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Image(systemName: TogetherSymbols.name(section.icon))
                    .frame(width: 24).accessibilityHidden(true)
                Text(section.title).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if model.section == section {
                    Image(systemName: TogetherSymbols.name("checkmark")).font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .font(.body.weight(model.section == section ? .semibold : .regular))
            .foregroundColor(model.section == section ? TogetherTheme.rose : .primary)
            .padding(.horizontal, 12).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(model.section == section ? TogetherTheme.rose.opacity(0.12) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("nav." + section.rawValue.lowercased())
        .accessibilityAddTraits(model.section == section ? [.isSelected] : [])
    }
    @ViewBuilder private var mobileCreateAction: some View {
        if model.section == .plans && model.taskFilter == .pending {
            mobileToolbarButton(Copy.text("copy.action.718e58cc20d6"), identifier: "task.new") { model.newTask() }
        } else if model.section == .wishes {
            mobileToolbarButton(Copy.text("plans.action.addWishes"), identifier: "wish.grant.new") { model.show(.grant) }
                .disabled(model.engine.context.peer == nil)
        } else if model.section == .finances {
            mobileToolbarButton(Copy.text("finance.action.new." + model.financeTab.rawValue), identifier: "finance.new", action: createFinanceRecord)
        }
    }
    private func mobileToolbarButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: TogetherSymbols.name("plus")).frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(title)
        }
        .disabled(model.sheet != nil)
        .accessibilityIdentifier(identifier)
    }
    private var mobileActions: some View {
        Menu {
            if model.section == .finances {
                Button { model.showFinance(.settings) } label: {
                    Label(Copy.text("finance.action.settings"), systemImage: TogetherSymbols.name("slider.horizontal.3"))
                }.accessibilityIdentifier("finance.settings")
                Button { model.showFinance(.changes) } label: {
                    Label(Copy.text("finance.action.changes"), systemImage: TogetherSymbols.name("clock.arrow.circlepath"))
                }.accessibilityIdentifier("finance.changes")
                Divider()
            }
            Button(Copy.text("copy.action.fb24523a7f34")) { model.show(.giftEditor(nil)) }
                .accessibilityIdentifier("menu.gift")
            Button(Copy.text("copy.action.1555373b2da2")) { model.show(.giftHistory) }
                .accessibilityIdentifier("menu.gifts")
            Divider()
            Button(Copy.text("sync.changes.title")) { model.show(.changes) }
                .accessibilityIdentifier("menu.changes")
            Button(Copy.text("device.title")) { model.show(.devices) }
            Button(Copy.text("copy.action.58383b09e244")) { model.show(.advisor) }
            Button(Copy.text("copy.action.561b17edc33d")) { model.show(.whatsNew) }
        } label: {
            Image(systemName: TogetherSymbols.name("ellipsis.circle")).frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(Copy.text("navigation.more"))
        }
        .disabled(model.sheet != nil)
        .accessibilityIdentifier("navigation.more")
    }
    #endif
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
