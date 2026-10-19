import XCTest
import AppKit
import CryptoKit

@MainActor final class TogetherUITests: XCTestCase {
    private var app: XCUIApplication!
    private var root: URL!
    private func dismissRunnerDocumentsRequest() {
        let system = XCUIApplication(bundleIdentifier: "com.apple.UserNotificationCenter")
        let dialog = system.dialogs.firstMatch
        guard dialog.exists else { return }
        let texts = dialog.staticTexts.allElementsBoundByIndex.map { $0.value as? String ?? $0.label }.joined(separator: " ")
        if texts.contains("TogetherUITests-Runner") && (texts.contains("文稿") || texts.contains("Documents")) && texts.contains("automated testing") {
            dialog.buttons["action-button-2"].click()
        }
    }
    override func tearDown() {
        app?.terminate()
        if let root { try? FileManager.default.removeItem(at: root) }
        super.tearDown()
    }
    private func launch(page: String = "home", populated: Bool = false, dark: Bool = false, reduce: Bool = false, compact: Bool = false, name: String = "behavior") {
        dismissRunnerDocumentsRequest()
        app?.terminate()
        if let root { try? FileManager.default.removeItem(at: root) }
        root = FileManager.default.temporaryDirectory.appendingPathComponent("together-ui-" + UUID().uuidString)
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-NSDoubleLocalizedStrings", "NO"]
        app.launchEnvironment = ["TOGETHER_UI_ROOT":root.path, "TOGETHER_UI_PAGE":page, "TOGETHER_UI_STATE":populated ? "populated" : "empty", "TOGETHER_UI_MODE":dark ? "dark" : "light", "TOGETHER_UI_REDUCE_MOTION":reduce ? "1" : "0", "TOGETHER_UI_COMPACT":compact ? "1" : "0", "TOGETHER_UI_CASE":name]
        continueAfterFailure = false
        app.launch()
        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["nav.home"].waitForExistence(timeout: 15))
        if compact { XCTAssertEqual(app.windows.firstMatch.frame.width, 900, accuracy: 2, "Compact fixture must actually resize the window") }
    }
    private func screenshot(_ name: String) throws {
        // Presence of the final button precedes the end of the spring and
        // delayed content transitions. Snapshot the settled state while the
        // behavior tests continue to exercise the actual animation.
        if name.hasSuffix("-normal-opened") {
            // Opening changes layout underneath the pointer; keep photo-hover
            // controls out of this resting-state fixture, without hiding them
            // in the product or changing system pointer preferences.
            app.sheets.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).hover()
            Thread.sleep(forTimeInterval: 1)
        }
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
        XCTAssertLessThanOrEqual(app.sheets.count, 1, "Only one modal sheet may be presented")
        // Native sheets/popovers may extend beyond a compact parent window.
        // Screenshot the actual owned element, not a clipped parent-window crop.
        let target = app.popovers.firstMatch.exists ? app.popovers.firstMatch : app.sheets.firstMatch.exists ? app.sheets.firstMatch : window
        let scope = target.elementType == .popover ? "popover" : target.elementType == .sheet ? "sheet" : "window"
        let targetFrame = target.frame, windowFrame = window.frame
        let shot = target.screenshot()
        let attachment = XCTAttachment(screenshot: shot); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let metadata = XCTAttachment(string: "Native XCTest scope: \(scope); frame: \(targetFrame); fixture window: \(windowFrame)")
        metadata.name = name + "-capture-scope"; metadata.lifetime = .keepAlways; add(metadata)
    }
    private func enterCommittedSearch(_ text: String) {
        // Test locale does not select the Mac's keyboard input source. Pinyin
        // can keep typeText's Latin fixture in marked composition. A native
        // Cmd+V commits the exact deterministic query without changing the
        // user's input method, and the complete clipboard is restored.
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let bytes = item.data(forType: type) { copy.setData(bytes, forType: type) } }
            return copy
        }
        pasteboard.clearContents(); pasteboard.setString(text, forType: .string)
        let testChange = pasteboard.changeCount
        defer {
            if pasteboard.changeCount == testChange {
                pasteboard.clearContents()
                if !saved.isEmpty { pasteboard.writeObjects(saved) }
            }
        }
        let field = app.textFields["finance.currency.search"]
        field.click(); field.typeKey("v", modifierFlags: .command)
        // The Pinyin input indicator is a short-lived AX dialog near the field.
        // Waiting on the application's live query avoids retaining its identity
        // while XCTest's automatic interruption handler attempts the next click.
        // A genuine persistent dialog fails this wait; no permission is granted.
        let inputUIClosed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 0"), object: app.dialogs)
        XCTAssertEqual(XCTWaiter.wait(for: [inputUIClosed], timeout: 8), .completed, "Native input UI must settle before resolving a currency row")
    }
    func testCurrencySearchWithCurrentInputMethod() throws {
        for dark in [false, true] {
            launch(page: "bills", dark: dark, reduce: true, compact: true)
            app.buttons["finance.new"].click()
            app.buttons["finance.currency.open"].click()
            XCTAssertTrue(app.textFields["finance.currency.search"].waitForExistence(timeout: 5))
            enterCommittedSearch(dark ? "日元" : "JPY")
            let filtered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["finance.currency.CNY"])
            XCTAssertEqual(XCTWaiter.wait(for: [filtered], timeout: 5), .completed)
            let yen = app.buttons.matching(identifier: "finance.currency.JPY").firstMatch
            XCTAssertTrue(yen.waitForExistence(timeout: 5))
            XCTAssertTrue(yen.isHittable)
            yen.click()
            XCTAssertFalse(app.textFields["finance.currency.search"].exists)
            XCTAssertTrue(app.buttons["finance.currency.open"].label.contains("JPY"))
            app.buttons["sheet.cancel"].click()
            XCTAssertEqual(app.sheets.count, 0)
        }
    }
    func testNavigationAndNoPersistentGiftUI() {
        launch()
        XCTAssertFalse(app.staticTexts["Daily Love Gift"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["nav.gifts"].exists)
        for id in ["nav.tasks", "nav.upcoming", "nav.completed", "nav.story"] {
            XCTAssertFalse(app.descendants(matching: .any)[id].exists)
        }
        let plans = app.descendants(matching: .any)["nav.plans"].firstMatch
        let wishes = app.descendants(matching: .any)["nav.wishes"].firstMatch
        XCTAssertLessThan(plans.frame.minY, wishes.frame.minY)
        XCTAssertEqual(plans.frame.minX, wishes.frame.minX, accuracy: 2)
        for id in ["nav.plans", "nav.wishes", "nav.connection", "nav.settings", "nav.home"] {
            let item = app.descendants(matching: .any)[id].firstMatch; XCTAssertTrue(item.isHittable); item.click()
        }
        XCTAssertFalse(app.radioGroups["plans.mode"].exists)
    }
    private func filter(_ title: String) {
        let control = app.radioGroups["plans.taskFilter"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        control.radioButtons[title].click()
    }
    private func taskButton(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'task.open.' AND label CONTAINS %@", title)).firstMatch
    }
    private func mode(_ name: String) {
        dismissRunnerDocumentsRequest()
        let item = app.descendants(matching: .any)[name == "wishes" ? "nav.wishes" : "nav.plans"].firstMatch
        XCTAssertTrue(item.isHittable)
        item.click()
        if name == "wishes" {
            XCTAssertTrue(app.buttons["wish.grant.new"].waitForExistence(timeout: 5))
        } else {
            XCTAssertTrue(app.radioGroups["plans.taskFilter"].waitForExistence(timeout: 5))
        }
    }
    func testPlansFiltersSharedEditorAndHomeRouting() {
        launch(populated: true)
        app.buttons["home.pending"].click()
        XCTAssertTrue(app.buttons["task.new"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "task.new").count, 1)
        XCTAssertTrue(taskButton("OVERDUE_FIXTURE").exists)
        XCTAssertTrue(taskButton("UNDATED_FIXTURE").exists)
        XCTAssertFalse(taskButton("整理书架").exists)
        filter("Upcoming")
        XCTAssertFalse(app.buttons["task.new"].exists)
        XCTAssertTrue(taskButton("一起买菜").exists)
        XCTAssertTrue(taskButton("FUTURE_FIXTURE").exists)
        XCTAssertFalse(taskButton("OVERDUE_FIXTURE").exists)
        XCTAssertFalse(taskButton("UNDATED_FIXTURE").exists)
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.textFields["task.title"].waitForExistence(timeout: 5))
        app.buttons["sheet.cancel"].click()
        filter("Completed")
        XCTAssertFalse(app.buttons["task.new"].exists)
        let completed = taskButton("整理书架")
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: completed)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed)
        completed.click()
        XCTAssertTrue(app.textFields["task.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["task.title"].value as? String, "整理书架")
        app.checkBoxes["task.completed"].click()
        app.buttons["task.save"].click()
        XCTAssertTrue(app.descendants(matching: .any)["plans.tasks.empty"].waitForExistence(timeout: 5))
        filter("Pending")
        XCTAssertTrue(taskButton("整理书架").exists)
        let search = app.textFields["plans.taskSearch"]; search.click()
        search.typeText("UNDATED")
        XCTAssertEqual(search.value as? String, "UNDATED")
        mode("wishes")
        XCTAssertTrue(app.buttons["wish.grant.new"].waitForExistence(timeout: 5))
        mode("tasks")
        XCTAssertEqual(app.textFields["plans.taskSearch"].value as? String, "UNDATED")
        app.descendants(matching: .any)["nav.home"].firstMatch.click()
        app.buttons["home.upcoming"].click()
        let upcoming = app.radioGroups["plans.taskFilter"].radioButtons["Upcoming"]
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1' OR value == 1"), object: upcoming)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        app.descendants(matching: .any)["nav.home"].firstMatch.click()
        app.buttons["home.wishes"].click()
        XCTAssertTrue(app.buttons["wish.grant.new"].waitForExistence(timeout: 5))
    }
    func testWishLedgerDetailUsesExistingActions() {
        launch(page: "wishes", populated: true)
        XCTAssertTrue(app.staticTexts["2026-10-09"].exists)
        XCTAssertTrue(app.staticTexts["Grant History"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "wish.grant.new").count, 1)
        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'wish.grant.open.'")).firstMatch
        XCTAssertTrue(record.isHittable); record.click()
        XCTAssertTrue(app.buttons["wish.grant.detail.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["一起看日落"].exists)
        XCTAssertTrue(app.buttons["wish.grant.detail.close"].isHittable)
        app.buttons["wish.grant.detail.close"].click()
        XCTAssertEqual(app.sheets.count, 0)
    }
    func testCompactLayoutAndReduceMotion() throws {
        launch(page: "tasks", populated: true, reduce: true, compact: true)
        XCTAssertTrue(app.buttons["task.new"].isHittable)
        XCTAssertTrue(app.radioGroups["plans.taskFilter"].radioButtons["Pending"].isHittable)
        XCTAssertTrue(app.textFields["plans.taskSearch"].isHittable)
        try screenshot("tasks-populated-light-compact-reduced")
        app.buttons["task.new"].click()
        XCTAssertTrue(app.buttons["sheet.cancel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["task.save"].isHittable)
        app.buttons["sheet.cancel"].click()
        launch(page: "wishes", populated: true, dark: true, reduce: true, compact: true)
        XCTAssertTrue(app.buttons["wish.grant.new"].isHittable)
        try screenshot("wishes-populated-dark-compact-reduced")
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'wish.grant.open.'")).firstMatch.click()
        XCTAssertTrue(app.buttons["wish.grant.detail.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["wish.grant.detail.close"].isHittable)
        app.buttons["wish.grant.detail.close"].click()
        for dark in [false, true] {
            launch(page: "home", populated: true, dark: dark, reduce: true, compact: true)
            XCTAssertTrue(app.buttons["home.pending"].isHittable)
            try screenshot("home-populated-\(dark ? "dark" : "light")-compact-reduced")
        }
    }
    func testTaskActionAndClosableSheet() {
        launch(page: "tasks")
        app.buttons["task.new"].click()
        let title = app.textFields["task.title"]; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.click(); title.typeText("UI_BEHAVIOR_TASK"); app.textFields["task.notes"].click()
        XCTAssertEqual(title.value as? String, "UI_BEHAVIOR_TASK")
        let save = app.buttons["task.save"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        XCTAssertTrue(save.isHittable, "Save must be reachable in the task sheet")
        save.click()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UI_BEHAVIOR_TASK")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["task.new"].click(); XCTAssertTrue(app.buttons["sheet.cancel"].waitForExistence(timeout: 5)); app.buttons["sheet.cancel"].click()
        XCTAssertFalse(app.textFields["task.title"].exists)
    }
    func testMenuGiftEditorAndEmptySubmission() {
        launch()
        app.typeKey("l", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.textViews["gift.textInput"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["gift.send"].isEnabled)
        XCTAssertTrue(app.buttons["gift.editor.close"].isHittable); app.buttons["gift.editor.close"].click()
        XCTAssertFalse(app.textViews["gift.textInput"].exists)
    }
    func testSealedGiftPrivacyAndOneAutomaticModal() {
        launch(page: "reveal", populated: true)
        XCTAssertTrue(app.buttons["gift.open"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["PRIVATE_FIXTURE_GIFT_CONTENT"].exists)
        XCTAssertFalse(app.buttons["gift.savePhoto"].exists)
        XCTAssertFalse(app.buttons["audio.playPause"].exists)
        app.buttons["gift.open"].click()
        XCTAssertTrue(app.staticTexts["gift.privateText"].waitForExistence(timeout: 5))
        let savePhoto = app.buttons["gift.savePhoto"]
        if !savePhoto.isHittable { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -500) }
        XCTAssertTrue(savePhoto.isHittable)
        app.buttons["gift.received"].click()
        XCTAssertFalse(app.buttons["gift.open"].exists)
        XCTAssertEqual(app.sheets.count, 0)
    }
    private func openHistory() {
        app.typeKey("l", modifierFlags: [.command, .option])
        XCTAssertTrue(app.buttons["gift.history.close"].waitForExistence(timeout: 5))
    }
    func testSendPendingSyncQuotaAndManualHistory() {
        launch(page: "gifts", populated: true)
        let send = app.buttons["gift.send"]
        if !send.isHittable { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -500) }
        XCTAssertTrue(send.isEnabled); send.click()
        XCTAssertFalse(app.textViews["gift.textInput"].exists)
        openHistory()
        XCTAssertTrue(app.staticTexts["Pending Sync"].exists)
        XCTAssertFalse(app.staticTexts["Delivered"].exists)
        app.buttons["gift.history.close"].click()
        app.typeKey("l", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.textViews["gift.textInput"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["gift.send"].isEnabled)
        app.buttons["gift.editor.close"].click()
    }
    func testCachedRevealOnceRestartHistoryAndOriginalSavePanel() throws {
        executionTimeAllowance = 60
        launch(page: "reveal", populated: true)
        let destination = root.appendingPathComponent("user-export")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }
        app.buttons["gift.open"].click()
        XCTAssertTrue(app.buttons["audio.playPause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["audio.playPause"].label.contains("Play") || app.buttons["audio.playPause"].label.contains("播放"))
        let save = app.buttons["gift.savePhoto"]
        if !save.isHittable { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -500) }
        save.click()
        let nativeSave = app.dialogs["save-panel"].buttons["OKButton"]
        XCTAssertTrue(nativeSave.waitForExistence(timeout: 5)); nativeSave.click()
        let output = destination.appendingPathComponent("fixture-photo.png")
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: output.path) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 8), .completed)
        // The importer fixture source has identical bytes; compare with the verified receiver original too.
        let originals = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("media/assets"), includingPropertiesForKeys: nil).map { $0.appendingPathComponent("original.png") }.filter { FileManager.default.fileExists(atPath: $0.path) }
        XCTAssertEqual(originals.count, 1)
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: output)), SHA256.hash(data: try Data(contentsOf: originals[0])))
        app.buttons["gift.received"].click()
        app.terminate(); app.launch(); app.activate()
        XCTAssertTrue(app.descendants(matching: .any)["nav.home"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["gift.open"].exists)
        openHistory()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'gift.history.open.'")).firstMatch.click()
        XCTAssertTrue(app.buttons["gift.open"].waitForExistence(timeout: 5))
        app.buttons["gift.close"].click()
    }
    func testSnapshotMatrix() throws {
        for page in ["home", "tasks", "upcoming", "completed", "wishes", "gifts", "settings"] {
            for populated in [false, true] {
                for dark in [false, true] {
                    let name = "\(page)-\(populated ? "populated" : "empty")-\(dark ? "dark" : "light")-disconnected"
                    launch(page: page, populated: populated, dark: dark, reduce: true, name: name)
                    if page == "gifts" { XCTAssertTrue(app.textViews["gift.textInput"].waitForExistence(timeout: 8)) }
                    try screenshot(name)
                }
            }
        }
        for dark in [false, true] {
            for reduce in [false, true] {
                let name = "reveal-\(dark ? "dark" : "light")-\(reduce ? "reduced" : "normal")"
                launch(page: "reveal", populated: true, dark: dark, reduce: reduce, name: name)
                XCTAssertTrue(app.buttons["gift.open"].waitForExistence(timeout: 8))
                try screenshot(name + "-sealed")
                app.buttons["gift.open"].click()
                XCTAssertTrue(app.buttons["gift.received"].waitForExistence(timeout: 5))
                try screenshot(name + "-opened")
            }
        }
    }
    func testOurStoryNotImplemented() throws { throw XCTSkip("Our Story is absent; no placeholder screenshot is accepted.") }
    func testVisualTransientSurfaces() throws {
        // Narrow reproduction for capture timing/material differences; no
        // new product behavior and no mutation of approved reference images.
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            launch(page: "bills", dark: dark, reduce: true, compact: true)
            app.buttons["finance.new"].click()
            XCTAssertTrue(app.textFields["finance.bill.title"].waitForExistence(timeout: 5))
            app.buttons["finance.currency.open"].click()
            XCTAssertTrue(app.textFields["finance.currency.search"].waitForExistence(timeout: 5))
            Thread.sleep(forTimeInterval: 1)
            try screenshot("currency-picker-\(mode)-compact-reduced")
            launch(page: "reveal", populated: true, dark: dark, reduce: false)
            XCTAssertTrue(app.buttons["gift.open"].waitForExistence(timeout: 8))
            app.buttons["gift.open"].click()
            XCTAssertTrue(app.buttons["gift.received"].waitForExistence(timeout: 5))
            try screenshot("reveal-\(mode)-normal-opened")
            XCTAssertTrue(app.buttons["gift.received"].isHittable)
        }
    }
    private func financeTab(_ name: String) {
        let control = app.radioGroups["finance.tabs"]
        XCTAssertTrue(control.waitForExistence(timeout: 8))
        control.radioButtons[name].click()
    }
    func testFinanceTabsSingleEditorAndCurrencyValidation() throws {
        launch(page: "reserves")
        XCTAssertTrue(app.descendants(matching: .any)["nav.finances"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "finance.new").count, 1)
        XCTAssertTrue(app.descendants(matching: .any)["finance.empty"].waitForExistence(timeout: 5))
        financeTab("Expenses")
        app.buttons["finance.new"].click()
        let title = app.textFields["finance.expense.title"], original = app.textFields["finance.amount.original"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.click(); title.typeText("UI_FINANCE_EXPENSE")
        original.click(); original.typeText("218.01")
        app.buttons["finance.currency.open"].click()
        XCTAssertTrue(app.textFields["finance.currency.search"].waitForExistence(timeout: 5))
        enterCommittedSearch("USD")
        // Filtering moves USD to a different row. XCTest idle does not imply
        // that SwiftUI's next layout/snapshot is committed; wait for the real
        // result set before resolving a coordinate for the row.
        let filtered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["finance.currency.CNY"])
        XCTAssertEqual(XCTWaiter.wait(for: [filtered], timeout: 5), .completed)
        try screenshot("currency-search-before-click")
        app.buttons["finance.currency.USD"].click()
        try screenshot("currency-search-after-click")
        let debug = XCTAttachment(string: app.debugDescription); debug.name = "currency-click-hierarchy"; debug.lifetime = .keepAlways; add(debug)
        XCTAssertFalse(app.textFields["finance.currency.search"].exists, "Currency row center must activate selection and close the popover")
        // macOS SwiftUI can expose an empty TextField's prompt as its AX value
        // without setting AXPlaceholderValue. Wait for the data-bound change;
        // accept only the actual prompt, never arbitrary nonempty text.
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '' OR value == placeholderValue OR value == '原币金额'"), object: original)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 5), .completed, "Currency change left original value: \(String(describing: original.value)), placeholder: \(String(describing: original.placeholderValue))")
        app.buttons["finance.save"].click()
        XCTAssertTrue(app.staticTexts["finance.editor.error"].waitForExistence(timeout: 5))
        original.click(); original.typeText("10")
        app.textFields["finance.amount.cny"].click(); app.textFields["finance.amount.cny"].typeText("70.05")
        app.buttons["finance.save"].click()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'finance.expense.open.' AND label CONTAINS 'UI_FINANCE_EXPENSE'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["finance.save"].exists)
        financeTab("Recurring Bills")
        XCTAssertTrue(app.descendants(matching: .any)["finance.empty"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'finance.reminder.'")).firstMatch.exists)
        app.buttons["finance.new"].click()
        XCTAssertTrue(app.textFields["finance.bill.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["finance.dayWheel"].exists)
        app.buttons["sheet.cancel"].click()
        XCTAssertTrue(app.buttons["finance.new"].isHittable)
    }
    func testFinanceProvisionalConfirmationAndSettings() throws {
        launch(page: "expenses", populated: true, reduce: true)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'finance.expense.open.' AND label CONTAINS 'FINANCE_PROVISIONAL_FIXTURE'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.click()
        XCTAssertTrue(app.buttons["finance.review.correct"].waitForExistence(timeout: 5))
        let correct = app.buttons["finance.review.correct"]
        for _ in 0..<4 where !correct.isHittable {
            app.sheets.firstMatch.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -180)
        }
        XCTAssertTrue(correct.isHittable, "Reconciliation action must be visible after scrolling the native form")
        correct.click()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 0"), object: app.sheets)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed, "Successful reconciliation must close the editor")
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.click()
        XCTAssertFalse(app.buttons["finance.review.correct"].exists)
        app.buttons["sheet.cancel"].click()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'finance.expense.open.' AND label CONTAINS 'FINANCE_PROVISIONAL_FIXTURE'")).count, 1)
        app.buttons["finance.settings"].click()
        XCTAssertTrue(app.buttons["finance.save"].waitForExistence(timeout: 5)); app.buttons["sheet.cancel"].click()
        XCTAssertFalse(app.buttons["finance.save"].exists)
        try screenshot("expenses-confirmed-light-reduced")
    }
    func testFinanceSnapshotMatrix() throws {
        for page in ["reserves", "expenses", "bills", "finance-settings"] {
            for populated in [false, true] {
                for dark in [false, true] {
                    let name = "\(page)-\(populated ? "populated" : "empty")-\(dark ? "dark" : "light")-disconnected"
                    launch(page: page, populated: populated, dark: dark, reduce: true, name: name)
                    if page == "finance-settings" { XCTAssertTrue(app.buttons["finance.save"].waitForExistence(timeout: 8)) }
                    else { XCTAssertTrue(app.radioGroups["finance.tabs"].waitForExistence(timeout: 8)) }
                    try screenshot(name)
                }
            }
        }
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            for page in ["reserves", "expenses", "bills"] {
                let name = "\(page)-populated-\(mode)-compact-reduced"
                launch(page: page, populated: true, dark: dark, reduce: true, compact: true, name: name)
                XCTAssertTrue(app.buttons["finance.new"].isHittable)
                XCTAssertTrue(app.radioGroups["finance.tabs"].radioButtons["Recurring Bills"].isHittable)
                try screenshot(name)
            }
            app.buttons["finance.new"].click()
            XCTAssertTrue(app.textFields["finance.bill.title"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["finance.save"].isHittable)
            XCTAssertTrue(app.buttons["sheet.cancel"].isHittable)
            try screenshot("bill-editor-\(mode)-compact-reduced")
            app.buttons["finance.currency.open"].click()
            XCTAssertTrue(app.textFields["finance.currency.search"].waitForExistence(timeout: 5))
            try screenshot("currency-picker-\(mode)-compact-reduced")
            enterCommittedSearch("JPY")
            let filtered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["finance.currency.CNY"])
            XCTAssertEqual(XCTWaiter.wait(for: [filtered], timeout: 5), .completed)
            XCTAssertTrue(app.buttons["finance.currency.JPY"].isHittable)
            // Resolve a fresh identifier query after the input UI settles.
            app.buttons.matching(identifier: "finance.currency.JPY").firstMatch.click()
            XCTAssertFalse(app.textFields["finance.currency.search"].exists)
            XCTAssertTrue(app.buttons["finance.currency.open"].label.contains("JPY"))
            app.buttons["sheet.cancel"].click()
            XCTAssertEqual(app.sheets.count, 0)

            launch(page: "finance-settings", populated: true, dark: dark, reduce: true, compact: true)
            XCTAssertTrue(app.buttons["finance.save"].waitForExistence(timeout: 5))
            app.radioGroups["finance.cycle.scope"].radioButtons["我的周期"].click()
            let day = app.buttons.matching(identifier: "finance.day.15").firstMatch
            let centered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: day)
            XCTAssertEqual(XCTWaiter.wait(for: [centered], timeout: 5), .completed, "Personal cycle must center its persisted day 15")
            XCTAssertTrue(app.buttons["finance.save"].isHittable)
            try screenshot("finance-settings-personal-\(mode)-compact-reduced")
            app.buttons["sheet.cancel"].click()
            XCTAssertEqual(app.sheets.count, 0)
        }
    }
}
