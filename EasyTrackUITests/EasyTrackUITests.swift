import XCTest

final class EasyTrackUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeAndActivitySearch() throws {
        let app = XCUIApplication()
        app.launch()
        try requireDemoOnly(app)
        XCTAssertTrue(app.staticTexts["EasyTrack"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Activity"].tap()
        let search = app.textFields["transactionSearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Coffee")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Demo · Coffee Shop")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Demo · Book Store"].exists)
        attach(app, name: "activity-demo-search")
    }

    @MainActor
    func testActivityKindFilter() throws {
        let app = XCUIApplication()
        app.launch()
        try requireDemoOnly(app)
        app.tabBars.buttons["Activity"].tap()
        app.buttons["Income"].tap()
        XCTAssertTrue(app.staticTexts["Demo · Salary"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Demo · Coffee Shop")).firstMatch.exists)
    }

    @MainActor
    func testEditPersistsAfterRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        try requireDemoOnly(app)
        app.tabBars.buttons["Activity"].tap()
        let coffee = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Demo · Coffee Shop")).firstMatch
        XCTAssertTrue(coffee.waitForExistence(timeout: 5))
        coffee.tap()
        let description = app.textFields["transactionDescriptionField"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        let before = description.value as? String ?? ""
        description.tap()
        description.typeText(" UI")
        let edited = description.value as? String ?? ""
        XCTAssertNotEqual(before, edited)
        app.buttons["Save"].tap()
        app.terminate()
        app.launch()
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts[edited].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAutomationsAndSettings() throws {
        let app = XCUIApplication()
        app.launch()
        try requireDemoOnly(app)
        app.tabBars.buttons["Automations"].tap()
        app.buttons["Send a demo test payload"].tap()
        let source = app.staticTexts["Demo payment app"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        XCTAssertTrue(app.staticTexts["Demo purchase"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Automations"].tap()

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Local database · available offline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose SQLite seed"].exists)
        attach(app, name: "settings-demo-only")
    }

    @MainActor
    func testSyntheticImportPreviewAndConfirm() throws {
        let app = XCUIApplication()
        app.launch()
        try requireDemoOnly(app)
        selectSyntheticSeed(in: app)
        let importButton = app.buttons["Import 1 movements"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 10), app.debugDescription)
        importButton.tap()
    }

    @MainActor
    func testSyntheticReimportShowsZeroNewMovements() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        let oneImported = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1 historical movements imported")).firstMatch
        guard oneImported.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires the synthetic imported fixture; skips on other data")
        }
        selectSyntheticSeed(in: app)
        let noChanges = app.buttons["Confirm no changes"]
        XCTAssertTrue(noChanges.waitForExistence(timeout: 10), app.debugDescription)
        noChanges.tap()
    }

    @MainActor
    func testSyntheticEditorRejectsInvalidAmounts() throws {
        let app = XCUIApplication()
        app.launch()
        try openSyntheticTransaction(in: app)
        let amount = app.textFields["transactionAmountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        replaceText(in: amount, with: "")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Enter an amount."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Edit transaction"].exists)

        replaceText(in: amount, with: "0,00")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Amount must be greater than zero."].waitForExistence(timeout: 5))

        replaceText(in: amount, with: "-1,00")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Use a positive amount")).firstMatch.waitForExistence(timeout: 5))

        replaceText(in: amount, with: "12,3456")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "valid amount")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Edit transaction"].exists)
    }

    @MainActor
    func testSyntheticEditorSavesEURAndRelaunches() throws {
        let app = XCUIApplication()
        app.launch()
        try openSyntheticTransaction(in: app)
        let amount = app.textFields["transactionAmountField"]
        let description = app.textFields["transactionDescriptionField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertTrue(description.exists)
        replaceText(in: amount, with: "18,75")
        replaceText(in: description, with: "Synthetic Edited Purchase")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Synthetic Edited Purchase"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "18,75")).firstMatch.exists)

        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "18,75")).firstMatch.exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "18,75")).firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic Edited Purchase"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "18,75")).firstMatch.exists)
    }

    @MainActor
    func testFolderProbeWriteAndRead() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        let oneImported = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1 historical movements imported")).firstMatch
        guard oneImported.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires the synthetic imported fixture")
        }
        app.swipeUp()
        if !app.staticTexts["Folder bookmark saved"].exists {
            let chooseFolder = app.buttons["Choose folder in Files"]
            for _ in 0..<3 where !chooseFolder.isHittable { app.swipeUp() }
            XCTAssertTrue(chooseFolder.waitForExistence(timeout: 5))
            chooseFolder.tap()
            let browse = app.buttons["Browse"]
            XCTAssertTrue(browse.waitForExistence(timeout: 20))
            browse.tap()
            let local = app.staticTexts["On My iPhone"]
            if local.exists { local.tap() }
            let folder = app.staticTexts["EasyTrack"]
            XCTAssertTrue(folder.waitForExistence(timeout: 10), app.debugDescription)
            folder.tap()
            for label in ["Open", "Choose", "Done"] where app.buttons[label].exists {
                app.buttons[label].tap()
                break
            }
        }
        XCTAssertTrue(app.staticTexts["Folder bookmark saved"].waitForExistence(timeout: 10), app.debugDescription)
        app.tabBars.buttons["Home"].tap()
        app.tabBars.buttons["Settings"].tap()
        app.swipeUp()
        runFolderProbe(in: app)
        app.terminate()
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Folder bookmark saved"].waitForExistence(timeout: 10))
        runFolderProbe(in: app)
    }

    @MainActor
    private func runFolderProbe(in app: XCUIApplication) {
        let button = app.buttons["Write and read test file"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(button.isEnabled, "The folder test button is disabled despite a saved bookmark")
        button.tap()
        let success = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Read back OK")).firstMatch
        XCTAssertTrue(success.waitForExistence(timeout: 15), app.debugDescription)
    }

    @MainActor
    func testSyntheticJSONBackupExport() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        let oneImported = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1 historical movements imported")).firstMatch
        guard oneImported.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires the one-movement synthetic simulator fixture")
        }
        let export = app.buttons["Export local data as JSON"]
        for _ in 0..<3 where !export.isHittable { app.swipeUp() }
        XCTAssertTrue(export.isHittable, app.debugDescription)
        export.tap()
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 25), app.debugDescription)
        save.tap()
        let success = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Exported EasyTrack-backup-")).firstMatch
        XCTAssertTrue(success.waitForExistence(timeout: 15), app.debugDescription)
    }

    @MainActor
    private func selectSyntheticSeed(in app: XCUIApplication) {
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Choose SQLite seed"].tap()
        let seed = app.cells.matching(NSPredicate(format: "identifier CONTAINS[c] %@", "synthetic_seed")).firstMatch
        if !seed.waitForExistence(timeout: 8) {
            let browse = app.buttons["Browse"]
            XCTAssertTrue(browse.waitForExistence(timeout: 12))
            browse.tap()
            if !seed.exists {
                let local = app.staticTexts["On My iPhone"]
                if local.exists { local.tap() }
                let folder = app.staticTexts["EasyTrack"]
                if folder.exists { folder.tap() }
            }
        }
        XCTAssertTrue(seed.waitForExistence(timeout: 10), app.debugDescription)
        seed.tap()
    }

    @MainActor
    private func requireDemoOnly(_ app: XCUIApplication) throws {
        let marker = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "History not imported")).firstMatch
        guard marker.waitForExistence(timeout: 5) else {
            throw XCTSkip("Demo-only UI test skipped because historical data is present")
        }
    }

    @MainActor
    private func openSyntheticTransaction(in app: XCUIApplication) throws {
        app.tabBars.buttons["Settings"].tap()
        let oneImported = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1 historical movements imported")).firstMatch
        guard oneImported.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires the one-movement synthetic simulator fixture")
        }
        app.tabBars.buttons["Activity"].tap()
        if app.buttons["Clear search"].exists { app.buttons["Clear search"].tap() }
        app.buttons["All"].tap()
        let cells = app.collectionViews.cells
        XCTAssertGreaterThan(cells.count, 0)
        let row = cells.element(boundBy: cells.count - 1)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
    }

    @MainActor
    private func replaceText(in field: XCUIElement, with replacement: String) {
        field.tap()
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let count = (field.value as? String ?? "").count
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count + 2))
        if !replacement.isEmpty { field.typeText(replacement) }
        if !replacement.isEmpty { XCTAssertEqual(field.value as? String, replacement) }
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
