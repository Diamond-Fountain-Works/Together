#if DEBUG
import SwiftUI
import TogetherCore
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Explicit debug-only test data. No production database, Keychain or preferences are opened.
struct UIFixture {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") }
    let page: String
    let populated: Bool
    let dark: Bool
    let reduceMotion: Bool
    let root: URL
    let snapshotName: String
    init() throws {
        let env = ProcessInfo.processInfo.environment
        page = env["TOGETHER_UI_PAGE"] ?? "home"
        guard ["home","tasks","upcoming","completed","wishes","gifts","reveal","settings","setup","reserves","expenses","bills","finance-settings"].contains(page),
              let path = env["TOGETHER_UI_ROOT"], URL(fileURLWithPath: path).lastPathComponent.hasPrefix("together-ui-") else { throw TogetherError.invalid("Invalid isolated UI fixture configuration") }
        root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        guard root.path.hasPrefix(temporary + "/") || root.path.hasPrefix("/private/tmp/together-ui-") || root.path.hasPrefix("/tmp/together-ui-") || root.path.contains("/Library/Containers/com.together.app.UITests.xctrunner/Data/tmp/together-ui-") else { throw TogetherError.invalid("UI fixture root must be private temporary storage") }
        populated = env["TOGETHER_UI_STATE"] == "populated"; dark = env["TOGETHER_UI_MODE"] == "dark"; reduceMotion = env["TOGETHER_UI_REDUCE_MOTION"] == "1"
        snapshotName = env["TOGETHER_UI_CASE"] ?? "fixture"
    }
    @MainActor func build() async throws -> ApplicationModel {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if root.lastPathComponent.hasPrefix("together-ui-existing-") {
            // An explicit DEBUG-only upgrade rehearsal. Never resolves the
            // production Application Support path or starts a relay session.
            let expected = try CanonicalJSON.decode(ExistingUIStore.self, from: Data(contentsOf: root.appendingPathComponent("existing-expected.json")))
            let m = expected.metadata
            let identity = try DeviceIdentity.persistent(deviceId: m.deviceId, userId: m.userId, spaceId: m.spaceId, directory: root.appendingPathComponent("Identity"), needsExistingIdentity: true, migrateLegacy: true, timeZoneIdentifier: expected.timeZone, protocolVersion: 3)
            let engine = try ReplicaEngine(repository: TogetherRepository(url: root.appendingPathComponent("legacy.store")), identity: identity, mediaRoot: root.appendingPathComponent("Media"), dateProvider: FixedDateProvider(expected.capturedAt))
            let defaults = UserDefaults(suiteName: "com.together.upgrade-fixture." + UUID().uuidString)!
            let preferences = LocalAppPreferences(defaults: defaults)
            preferences.finishAdvisor(neverAgain: true); preferences.finishInitialSetup()
            let model = ApplicationModel(engine: engine, defaults: defaults, serviceURL: nil, useBundledService: false, filePanelDirectory: root.appendingPathComponent("user-export"))
            model.currentDate = expected.capturedAt
            return model
        }
        let now = ISO8601DateFormatter().date(from: "2026-10-09T04:00:00Z")!, clock = FixedDateProvider(now)
        let ia = try DeviceIdentity(deviceId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, userId: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!, initialSpaceId: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!, privateKeyData: Data(repeating: 1, count: 32), timeZoneIdentifier: "Asia/Shanghai", protocolVersion: 3)
        let ib = try DeviceIdentity(deviceId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, userId: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!, initialSpaceId: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!, privateKeyData: Data(repeating: 2, count: 32), timeZoneIdentifier: "Asia/Shanghai", protocolVersion: 3)
        let a = try ReplicaEngine(repository: TogetherRepository(url: root.appendingPathComponent("fixture.store")), identity: ia, mediaRoot: root.appendingPathComponent("media"), dateProvider: clock)
        let b = try ReplicaEngine(repository: TogetherRepository(inMemory: true), identity: ib, mediaRoot: root.appendingPathComponent("partner-media"), dateProvider: clock)
        if (try a.repository.load(Bool.self, key: "ui-fixture-built")) != true {
        try a.setProfile(name: "测试成员 A", label: .boyfriend)
        if populated || page == "reveal" {
            try b.setProfile(name: "测试成员 B", label: .girlfriend)
            try a.authorize(PairedPeer(descriptor: ib.descriptor, host: "127.0.0.1", port: 0))
            try b.authorize(PairedPeer(descriptor: ia.descriptor, host: "127.0.0.1", port: 0))
            try a.merge(b.operations); try b.merge(a.operations)
            _ = try a.createTask(title: "一起买菜", notes: "UI Test Fixture", assignedTo: ib.descriptor.userId, dueAt: now.addingTimeInterval(86400))
            _ = try a.createTask(title: "OVERDUE_FIXTURE", dueAt: now.addingTimeInterval(-86400))
            _ = try a.createTask(title: "UNDATED_FIXTURE")
            _ = try a.createTask(title: "FUTURE_FIXTURE", dueAt: now.addingTimeInterval(12 * 86400))
            let done = try a.createTask(title: "整理书架", dueAt: now.addingTimeInterval(172800)); try a.setCompleted(done, completed: true)
            let grant = try b.grant(fulfiller: ia.descriptor.userId, beneficiary: ib.descriptor.userId, quantity: 3, date: CivilDate(year: 2026, month: 10, day: 9), notes: "UI Test Fixture")
            _ = try b.createWish(grantId: grant, title: "一起看日落", description: "UI Test Fixture")
            let image = try makePhoto()
            let asset = try await b.importMedia(from: image, type: .photo)
            let audio = try await b.importMedia(from: makeAudio(), type: .audio)
            var gift = LoveGiftDraft(); gift.text = "PRIVATE_FIXTURE_GIFT_CONTENT"; gift.photoAssetId = asset.id; gift.audioAssetId = audio.id
            let giftId = try b.sendGift(gift); try a.merge(b.operations)
            for sourceAsset in [asset, audio] {
                let incoming = try requireAsset(a, sourceAsset.id)
                var offset: Int64 = 0
                while offset < incoming.byteCount { let chunk = try b.mediaStore.readChunk(sourceAsset, offset: offset); offset = try a.mediaStore.appendChunk(chunk, to: incoming, offset: offset) }
                try a.mediaStore.finishDownload(incoming)
            }
            if page == "gifts" {
                let ownPhoto = try await a.importMedia(from: image, type: .photo)
                let ownAudio = try await a.importMedia(from: makeAudio(), type: .audio)
                var draft = LoveGiftDraft(); draft.text = "UI_EDITOR_FIXTURE_TEXT"; draft.photoAssetId = ownPhoto.id; draft.audioAssetId = ownAudio.id
                try a.saveDraft(draft)
            }
            if page != "reveal" { try a.markGiftPresented(giftId, automatic: true); try a.markGiftOpened(giftId) }
            if ["reserves", "expenses", "bills", "finance-settings"].contains(page) {
                let today = CivilDate(year: 2026, month: 10, day: 9), month = FinanceMonth(year: 2026, month: 10)
                try a.setOpeningBalance(FinanceAmount(original: "500"), on: today)
                _ = try a.deposit(FinanceAmount(original: "2000"), by: ia.descriptor.userId, on: today, id: StableID.make("fixture-deposit-a"))
                _ = try b.deposit(FinanceAmount(original: "280", currency: "USD", actualCNY: "2000"), by: ib.descriptor.userId, on: today, id: StableID.make("fixture-deposit-b"))
                let event = try a.createDateEvent(title: "FINANCE_DATE_FIXTURE", on: today, id: StableID.make("fixture-finance-date"))
                _ = try a.createExpense(title: "FINANCE_SHARED_FIXTURE", amount: FinanceAmount(original: "218"), payment: .init(kind: .reserves), on: today, category: "餐饮", dateEventId: event, id: StableID.make("fixture-shared-expense"))
                _ = try a.createExpense(title: "FINANCE_AA_FIXTURE", amount: FinanceAmount(original: "100.01"), payment: .init(kind: .equalSplit, userIds: [ia.descriptor.userId, ib.descriptor.userId]), on: today, category: "出行", id: StableID.make("fixture-aa-expense"))
                _ = try a.createExpense(title: "FINANCE_FOREIGN_FIXTURE", amount: FinanceAmount(original: "11", currency: "USD", actualCNY: "78"), payment: .init(kind: .personal, userIds: [ia.descriptor.userId]), on: today, category: "餐饮", id: StableID.make("fixture-foreign-expense"))
                _ = try a.createRecurringBill(title: "FINANCE_PROVISIONAL_FIXTURE", amount: FinanceAmount(original: "68"), payment: .init(kind: .reserves), day: 8, timeZone: "Asia/Shanghai", startMonth: month, category: "订阅", id: StableID.make("fixture-provisional-bill"))
                _ = try a.createRecurringBill(title: "FINANCE_FORECAST_FIXTURE", amount: FinanceAmount(original: "9.99", currency: "USD", actualCNY: "71"), payment: .init(kind: .personal, userIds: [ib.descriptor.userId]), day: 10, timeZone: "Asia/Shanghai", startMonth: month, category: "订阅", id: StableID.make("fixture-forecast-bill"))
                try a.setFinanceSettings(owner: ia.descriptor.userId, startDay: 15, timeZone: "Asia/Shanghai", salaryDay: 10, plannedDepositDay: 11)
                try a.savePaymentMethod(.init(id: StableID.make("fixture-finance-card"), ownerId: ia.descriptor.userId, holderId: ia.descriptor.userId, bankName: "FINANCE_BANK_FIXTURE", name: "FINANCE_CARD_FIXTURE", cardKind: .debit, lastFour: "1234", isShared: false))
                try a.merge(b.operations)
                if ProcessInfo.processInfo.environment["TOGETHER_FINANCE_BANNER"] != "1" {
                    var state = try a.financialReviewState(); state.presentedOperationIds.formUnion(a.financialChanges(limit: a.operations.count).map(\.id)); try a.saveFinancialReviewState(state)
                }
            }
        }
        try a.repository.save(true, key: "ui-fixture-built")
        }
        let defaults = UserDefaults(suiteName: "com.together.ui-fixture." + UUID().uuidString)!
        let preferences = LocalAppPreferences(defaults: defaults)
        preferences.finishAdvisor(neverAgain: true)
        if page != "setup" { preferences.finishInitialSetup() }
        let model = ApplicationModel(engine: a, defaults: defaults, serviceURL: nil, useBundledService: false, filePanelDirectory: root.appendingPathComponent("user-export"))
        model.currentDate = now
        switch page {
        case "tasks": model.openPlans(.tasks)
        case "upcoming": model.openPlans(.tasks, filter: .upcoming)
        case "completed": model.openPlans(.tasks, filter: .completed)
        case "wishes": model.openPlans(.wishes)
        case "settings": model.section = .settings
        case "reserves", "finance-settings": model.section = .finances; model.financeTab = .reserves
        case "expenses": model.section = .finances; model.financeTab = .expenses
        case "bills": model.section = .finances; model.financeTab = .bills
        default: model.section = .home
        }
        if page == "gifts" { model.show(.giftEditor(nil)) }
        if page == "finance-settings" { model.showFinance(.settings) }
        return model
    }
    private func makePhoto() throws -> URL {
        let source = root.appendingPathComponent("fixture-photo.png")
        let c = CGContext(data: nil, width: 1600, height: 1200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        c.setFillColor(CGColor(red: 0.92, green: 0.82, blue: 0.77, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
        let destination = CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, c.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { throw TogetherError.invalid("UI fixture image unavailable") }
        return source
    }
    private func makeAudio() throws -> URL {
        let url = root.appendingPathComponent("fixture-voice.wav"), count: UInt32 = 88_200
        func le(_ v: UInt32) -> Data { Data([UInt8(v & 255), UInt8((v >> 8) & 255), UInt8((v >> 16) & 255), UInt8((v >> 24) & 255)]) }
        var data = Data("RIFF".utf8); data.append(le(36 + count * 2)); data.append(Data("WAVEfmt ".utf8)); data.append(le(16)); data.append(Data([1,0,1,0])); data.append(le(44_100)); data.append(le(88_200)); data.append(Data([2,0,16,0])); data.append(Data("data".utf8)); data.append(le(count * 2)); data.append(Data(repeating: 0, count: Int(count * 2))); try data.write(to: url); return url
    }
    @MainActor private func requireAsset(_ engine: ReplicaEngine, _ id: UUID) throws -> MediaAsset {
        guard let asset = engine.snapshot.mediaAssets[id] else { throw TogetherError.invalid("UI fixture manifest unavailable") }; return asset
    }
}
private struct ExistingUIStore: Decodable {
    let metadata: LocalIdentityMetadata
    let capturedAt: Date
    let timeZone: String
}

struct UIFixtureRoot: View {
    @Binding var model: ApplicationModel?
    @State private var error: String?
    private var fixture: UIFixture? { try? UIFixture() }
    var body: some View {
        Group {
            if let model, let fixture {
                RootView(model: model).preferredColorScheme(fixture.dark ? .dark : .light)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                    .environment(\.togetherMotionOverride, fixture.reduceMotion)
                    .background(FixtureWindowSize())
                    .background(FixtureContentCapture(fixture: fixture))
            } else { ProgressView().accessibilityIdentifier("qa.loading") }
        }
        .task {
            guard model == nil else { return }
            do { let configuration = try UIFixture(); model = try await configuration.build() }
            catch { self.error = error.localizedDescription }
        }
        .alert("UI Fixture Error", isPresented: Binding(get: { error != nil }, set: { _ in })) { Button("Close") {} } message: { Text(error ?? "") }
    }
}
private struct FixtureWindowSize: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { SizingView() }
    func updateNSView(_ view: NSView, context: Context) {}
    private class SizingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // makeNSView can run before attachment, especially on finance tabs.
            // Size the actual attached window; never label a 1100pt capture compact.
            guard let window else { return }
            let compact = ProcessInfo.processInfo.environment["TOGETHER_UI_COMPACT"] == "1"
            DispatchQueue.main.async {
                window.setContentSize(NSSize(width: compact ? 900 : 1100, height: compact ? 620 : 760))
                window.setFrameOrigin(NSPoint(x: 80, y: compact ? 180 : 80))
            }
        }
    }
}
#endif
