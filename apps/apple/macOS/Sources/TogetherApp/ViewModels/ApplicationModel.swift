import Combine
import SwiftUI
import TogetherCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import UniformTypeIdentifiers
#if TOGETHER_NATIVE_TRANSPORT || TOGETHER_NATIVE_P2P_QA
import TogetherP2P
#endif

enum AppSection: String, CaseIterable, Identifiable {
    case home = "Home", plans = "Plans", wishes = "Wishes", finances = "Finances", connection = "Connection", settings = "Settings"
    var id: String { rawValue }
    var title: String { switch self {
        case .home: Copy.text("nav.home"); case .plans: Copy.text("nav.plans"); case .wishes: Copy.text("nav.wishes"); case .finances: Copy.text("finance.title"); case .connection: Copy.text("nav.connection"); case .settings: Copy.text("nav.settings")
    } }
    var icon: String {
        switch self {
        case .home: "house"
        case .plans: "checklist"
        case .wishes: "sparkles"
        case .finances: "chart.pie"
        case .connection: "point.3.connected.trianglepath.dotted"
        case .settings: "person.crop.circle"
        }
    }
}
enum AppSheet: Identifiable {
    case task(UUID?), nextTime(UUID), grant, grantDetail(UUID), wish(UUID), adjustment(UUID), crop, advisor, whatsNew, initialSetup, giftEditor(UUID?), giftHistory, giftReveal([UUID], Bool)
    case changes, devices
    case finance(FinanceSheet)
    var id: String {
        switch self {
        case .task(let id): "task-\(id?.uuidString ?? "new")"
        case .nextTime(let id): "next-\(id)"
        case .wish(let id): "wish-\(id)"
        case .adjustment(let id): "adjust-\(id)"
        case .grant: "grant"
        case .grantDetail(let id): "grantDetail-\(id)"
        case .crop: "crop"
        case .advisor: "advisor"
        case .whatsNew: "whatsNew"
        case .initialSetup: "initialSetup"
        case .giftEditor(let id): "giftEditor-\(id?.uuidString ?? "new")"
        case .giftHistory: "giftHistory"
        case .giftReveal(let ids, _): "giftReveal-\(ids.first?.uuidString ?? "empty")"
        case .changes: "changes"
        case .devices: "devices"
        case .finance(let sheet): sheet.id
        }
    }
    var automaticKind: AutomaticModal? {
        switch self { case .initialSetup: .initialSetup; case .giftReveal: .giftReveal; case .whatsNew: .whatsNew; case .advisor: .advisor; default: nil }
    }
}
@MainActor final class ApplicationModel: ObservableObject {
    private var observationTokens: Set<AnyCancellable> = []
    let engine: ReplicaEngine
    @Published var requestedReplica: ReplicaEngine?
    #if DEBUG
    var qaC1Peers: [C1ReplicationService] = []
    var qaLegacyPeers: [PairingService] = []
    var qaDeviceTask: Task<Void, Never>?
    @Published var qaAllowsLocalNetwork = false
    #endif
    let changeReview:ChangeReviewService
    @Published var changeBannerEvents:[ChangeEvent]=[]
    var changeReviewTask:Task<Void,Never>?
    let network: PairingService
    #if TOGETHER_NATIVE_TRANSPORT || TOGETHER_NATIVE_P2P_QA
    @Published var nativeNetwork: NativeAppPeerService? { didSet { bindNestedPublishers() } }
    #endif
    var usesNativeTransport: Bool {
        #if TOGETHER_NATIVE_TRANSPORT || TOGETHER_NATIVE_P2P_QA
        nativeNetwork != nil
        #else
        false
        #endif
    }
    var connectionState: PairingConnectionState {
        #if TOGETHER_NATIVE_TRANSPORT || TOGETHER_NATIVE_P2P_QA
        if let nativeNetwork { return nativeNetwork.state }
        #endif
        return network.state
    }
    var isOnline: Bool {
        #if TOGETHER_NATIVE_TRANSPORT || TOGETHER_NATIVE_P2P_QA
        if let nativeNetwork { return nativeNetwork.isOnline }
        #endif
        return network.isOnline
    }
    var partnerIsOnline: Bool {
        #if TOGETHER_NATIVE_TRANSPORT || TOGETHER_NATIVE_P2P_QA
        if let nativeNetwork { return nativeNetwork.isOnline }
        #endif
        return network.partnerIsOnline
    }
    var completedSyncCount: Int {
        #if TOGETHER_NATIVE_TRANSPORT || TOGETHER_NATIVE_P2P_QA
        if let nativeNetwork { return nativeNetwork.completedSyncCount }
        #endif
        return network.completedSyncCount
    }
    func synchronize() {
        #if TOGETHER_NATIVE_TRANSPORT || TOGETHER_NATIVE_P2P_QA
        if let nativeNetwork { nativeNetwork.synchronize(); return }
        #endif
        network.synchronize()
    }
    let preferences: LocalAppPreferences
    let localDefaults: UserDefaults
    let version: String
    @Published var section: AppSection = .home
    var plansMode: PlansMode { section == .wishes ? .wishes : .tasks }
    @Published var financeTab: FinanceTab = .reserves
    @Published var financialReminders: [FinanceReminder] = []
    @Published var financialBannerChanges: [FinanceChange] = []
    @Published var financialExpenseSearch = ""
    @Published var financialPaymentFilter = "all"
    @Published var financialSourceFilter = "all"
    @Published var financialStatusFilter = "all"
    @Published var financialCategoryFilter = "all"
    @Published var financialDateFilter = "all"
    @Published var financialRangeStart = Date()
    @Published var financialRangeEnd = Date()
    var lastFinancialOperationCount = -1
    var financialNotificationSignature = ""
    var financialNotificationTask: Task<Void, Never>?
    @Published var taskFilter: TaskListFilter = .pending
    @Published var taskSearch = ""
    @Published var taskScrollAnchors: [TaskListFilter: UUID] = [:]
    @Published var grantScrollAnchor: String?
    @Published var sheet: AppSheet?
    @Published var errorMessage: String?
    @Published var cropAsset: MediaAsset?
    @Published var importingMedia = false
    @Published var lovePulse = 0
    @Published var currentDate = Date()
    private var clockTask: Task<Void, Never>?
    private var pendingSheets: [AppSheet] = []
    private var lastSheet: AppSheet?
    private var started = false
    let filePanelDirectory: URL?
    private var giftLaunchPolicy = GiftLaunchPolicy(cachedInboxIds: [])

    init(engine: ReplicaEngine, defaults: UserDefaults = .standard, serviceURL: URL? = nil, useBundledService: Bool = true, filePanelDirectory: URL? = nil) {
        self.engine = engine
        changeReview=ChangeReviewService(repository:engine.repository)
        // Seed presentation history once on upgrade; this is not a read receipt
        // and does not mark any legacy business change as approved/reviewed.
        if (try? engine.repository.load(ChangeReviewState.self,key:"replication4/change-review")) == nil {
            var state=ChangeReviewState();state.presentedOperationIds=Set(engine.operations.map(\.id));try? engine.repository.save(state,key:"replication4/change-review")
        }
        localDefaults = defaults
        self.filePanelDirectory = filePanelDirectory
        let configured = serviceURL ?? (useBundledService ? (Bundle.main.object(forInfoDictionaryKey: "TogetherRelayURL") as? String).flatMap(URL.init(string:)) : nil)
        network = PairingService(engine: engine, serviceURL: configured); preferences = LocalAppPreferences(defaults: defaults)
        version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.1"
        pendingSheets = preferences.processLaunch(version: version).map { $0 == .advisor ? .advisor : .whatsNew }
        if !preferences.hasCompletedInitialSetup { pendingSheets.insert(.initialSetup, at: 0) }
        giftLaunchPolicy = GiftLaunchPolicy(cachedInboxIds: engine.receivedGifts.map(\.id), clock: engine.dateProvider)
        currentDate = engine.dateProvider.now()
        financialRangeStart = currentDate; financialRangeEnd = currentDate
        bindNestedPublishers()
    }
    /// Combine is supported on the oldest M-series system. Forward nested
    /// publishers because the prior Observation graph tracked these implicitly.
    private func bindNestedPublishers() {
        observationTokens.removeAll()
        engine.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observationTokens)
        network.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observationTokens)
        LanguageSettings.shared.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observationTokens)
        #if TOGETHER_NATIVE_TRANSPORT || TOGETHER_NATIVE_P2P_QA
        nativeNetwork?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &observationTokens)
        #endif
    }
    func start() {
        guard !started else { return }; started = true
        #if TOGETHER_NATIVE_TRANSPORT || TOGETHER_NATIVE_P2P_QA
        if let nativeNetwork { nativeNetwork.restore() }
        else { restoreLegacyNetwork() }
        #else
        restoreLegacyNetwork()
        #endif
        checkStartupGifts(); refreshFinancialState(); refreshSharedChanges(); presentNext()
        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: self.engine.sharedSpace.timeZoneIdentifier) ?? .current
                let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date().addingTimeInterval(30)
                try? await Task.sleep(nanoseconds: UInt64(max(0.05, min(30, nextDay.timeIntervalSinceNow)) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.currentDate = self.engine.dateProvider.now()
                self.checkStartupGifts()
                self.refreshFinancialState()
            }
        }
    }
    /// Foreground resume reuses the existing identity and route. It does not
    /// rerun Initial Setup, Advisor timing or the process-launch gift policy.
    func resumeNetworking() {
        guard started else { return }
        #if TOGETHER_NATIVE_TRANSPORT || TOGETHER_NATIVE_P2P_QA
        if let nativeNetwork { nativeNetwork.restore() } else { restoreLegacyNetwork() }
        #else
        restoreLegacyNetwork()
        #endif
        currentDate = engine.dateProvider.now()
    }
    func suspendNetworking() {
        #if TOGETHER_NATIVE_TRANSPORT || TOGETHER_NATIVE_P2P_QA
        nativeNetwork?.disconnect()
        #endif
        network.disconnect()
    }
    private func restoreLegacyNetwork() {
        #if DEBUG && os(macOS)
        // Persisted C1 addresses must not activate from isolated UI fixtures.
        if !UIFixture.enabled || qaAllowsLocalNetwork { network.restore() }
        #else
        network.restore()
        #endif
    }
    func perform(_ action: () throws -> Void) { do { try action() } catch { errorMessage = Copy.userError(error) } }
    func show(_ value: AppSheet) {
        switch value { case .task, .nextTime, .grant, .grantDetail, .wish, .adjustment, .giftEditor, .finance: noteUserInteraction(); default: break }
        if sheet != nil { pendingSheets.append(value) }
        else { sheet = value; lastSheet = value }
    }
    func dismissSheet() { sheet = nil }
    func switchToEnrolledReplica(_ engine: ReplicaEngine) {
        clockTask?.cancel(); changeReviewTask?.cancel(); network.disconnect()
        #if TOGETHER_NATIVE_TRANSPORT || TOGETHER_NATIVE_P2P_QA
        nativeNetwork?.disconnect()
        #endif
        requestedReplica = engine
    }
    func replacement(with engine: ReplicaEngine) -> ApplicationModel {
        let result = ApplicationModel(engine: engine, defaults: localDefaults, useBundledService: false, filePanelDirectory: filePanelDirectory)
        #if DEBUG
        result.qaC1Peers = qaC1Peers; result.qaLegacyPeers = qaLegacyPeers
        result.qaDeviceTask = qaDeviceTask; result.qaAllowsLocalNetwork = qaAllowsLocalNetwork
        #endif
        return result
    }
    func replaceSheet(_ next: AppSheet) { pendingSheets.insert(next, at: 0); dismissSheet() }
    func giftRevealDidAppear(automatic: Bool) { if automatic { giftLaunchPolicy.didPresentAutomatically() } }
    func noteUserInteraction() {
        giftLaunchPolicy.noteUserInteraction()
        pendingSheets.removeAll { if case .giftReveal(_, true) = $0 { true } else { false } }
    }
    func sheetDismissed() {
        if case .advisor = lastSheet { preferences.finishAdvisor(neverAgain: false) }
        lastSheet = nil; presentNext()
    }
    private func presentNext() {
        guard sheet == nil, !pendingSheets.isEmpty else { return }
        let next = pendingSheets.removeFirst(); sheet = next; lastSheet = next
        if case .whatsNew = next { preferences.sawRelease(version: version) }
    }
    func finishSetup() { preferences.finishInitialSetup(); dismissSheet() }
    func checkStartupGifts() {
        guard giftLaunchPolicy.canPresentAutomatically else { return }
        if completedSyncCount > 0 { giftLaunchPolicy.noteFirstSync(inboxIds: engine.receivedGifts.map(\.id)) }
        let inbox = engine.receivedGifts
        let states = Dictionary(uniqueKeysWithValues: inbox.map { ($0.id, engine.presentation($0.id)) })
        let pending = giftLaunchPolicy.pendingIds(inbox: inbox, presentations: states)
        let ready = pending.filter { engine.snapshot.gifts[$0].map(engine.giftReady) ?? false }
        guard !ready.isEmpty else { return }
        if case .giftReveal = sheet { return }
        if pendingSheets.contains(where: { if case .giftReveal = $0 { true } else { false } }) { return }
        let insertion = pendingSheets.firstIndex { ($0.automaticKind ?? .advisor) > .giftReveal } ?? pendingSheets.count
        pendingSheets.insert(.giftReveal(ready, true), at: insertion)
        if sheet == nil { presentNext() }
    }
    var unreadGifts: [DailyLoveGift] { engine.receivedGifts.filter { engine.presentation($0.id).openedAt == nil } }
    func openGift(_ gift: DailyLoveGift) {
        guard engine.giftReady(gift) else { errorMessage = Copy.text("copy.status.77965761b32c"); synchronize(); return }
        if gift.recipientId == engine.identity.descriptor.userId && !engine.validReceivedGift(gift) { errorMessage = Copy.text("copy.status.bf8ae92630fb"); return }
        show(.giftReveal([gift.id], false))
    }
    func reply(to id: UUID) { noteUserInteraction(); pendingSheets.insert(.giftEditor(id), at: 0); dismissSheet() }
    var tasks: [TodoTask] { engine.snapshot.tasks.values.filter { $0.deletedAt == nil }.sorted {
        let left = $0.dueAt ?? .distantFuture, right = $1.dueAt ?? .distantFuture
        return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
    } }
    var pendingTasks: [TodoTask] { tasks.filter { $0.status != .completed } }
    var upcomingTasks: [TodoTask] { tasks.filter { $0.status != .completed && ($0.dueAt.map { $0 > currentDate } ?? false) } }
    var completedTasks: [TodoTask] { tasks.filter { $0.status == .completed }.sorted {
        let left = $0.completedAt ?? .distantPast, right = $1.completedAt ?? .distantPast
        return left == right ? $0.id.uuidString < $1.id.uuidString : left > right
    } }
    func openPlans(_ mode: PlansMode, filter: TaskListFilter = .pending) {
        if mode == .tasks { taskFilter = filter }
        section = mode == .wishes ? .wishes : .plans
        noteUserInteraction()
    }
    func newTask() {
        guard sheet == nil else { return }
        show(.task(nil))
    }
    func name(_ id: UUID) -> String { engine.snapshot.profiles[id]?.displayName ?? Copy.text("status.member.other") }
    func toggle(_ task: TodoTask) {
        perform { try setTaskCompleted(task, completed: task.status != .completed) }
    }
    func setTaskCompleted(_ task: TodoTask, completed: Bool) throws {
        try engine.setCompleted(task.id, completed: completed)
        if completed, let id = task.recurrenceRuleId, engine.snapshot.rules[id]?.mode == .flexible { show(.nextTime(task.id)) }
    }
    func chooseMedia(_ type: MediaType) async -> URL? {
        do {
            guard let url = try await TogetherFilePanels.choose(types: type == .audio ? [.audio] : [.image], directory: filePanelDirectory) else { return nil }
            if type != .audio {
                guard await TogetherFilePanels.confirm(title: Copy.text("copy.status.aed97e682ab9"), message: Copy.text("copy.guidance.fdb33a105fcd"), action: Copy.text("copy.action.08ff51a8822a")) else { return nil }
            }
            return url
        } catch { errorMessage = Copy.userError(error); return nil }
    }
    func importAvatar(showCrop: Bool = true) {
        guard !importingMedia else { return }; importingMedia = true
        Task { @MainActor in
            defer { importingMedia = false }
            guard let url = await chooseMedia(.avatar) else { return }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                cropAsset = try await engine.importMedia(from: url, type: .avatar)
                if showCrop { show(.crop) } else if let cropAsset { try engine.setAvatar(assetId: cropAsset.id) }
            } catch { errorMessage = Copy.userError(error) }
        }
    }
    func savePhoto(_ asset: MediaAsset) {
        guard asset.mediaType == .photo, engine.mediaStore.hasVerified(asset) else { errorMessage = Copy.text("copy.status.d01432dc56c6"); return }
        Task { @MainActor in
            do { try await TogetherFilePanels.exportOriginal(asset, store: engine.mediaStore, directory: filePanelDirectory) }
            catch { errorMessage = Copy.format("copy.guidance.6b5df256e07f", Copy.userError(error)) }
        }
    }
}
