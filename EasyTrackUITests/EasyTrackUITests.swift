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
        app.buttons["Try fictional notification"].tap()
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
        let homeTotal = app.staticTexts["homePersonalSpendingTotal"]
        XCTAssertTrue(homeTotal.waitForExistence(timeout: 5))
        let beforeTotal = homeTotal.label
        try openSyntheticTransaction(in: app)
        let amount = app.textFields["transactionAmountField"]
        let description = app.textFields["transactionDescriptionField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertTrue(description.exists)
        let newAmount = (amount.value as? String) == "18,75" ? "18,76" : "18,75"
        replaceText(in: amount, with: newAmount)
        replaceText(in: description, with: "Synthetic Edited Purchase")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Synthetic Edited Purchase"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", newAmount)).firstMatch.exists)

        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(homeTotal.waitForExistence(timeout: 5))
        let afterTotal = homeTotal.label
        XCTAssertNotEqual(afterTotal, beforeTotal)
        app.terminate()
        app.launch()
        XCTAssertTrue(homeTotal.waitForExistence(timeout: 5))
        XCTAssertEqual(homeTotal.label, afterTotal)
        app.tabBars.buttons["Activity"].tap()
        let search = app.textFields["transactionSearchField"]
        search.tap()
        search.typeText("Synthetic Account")
        XCTAssertTrue(app.staticTexts["Synthetic Edited Purchase"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", newAmount)).firstMatch.exists)
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
    func testSyntheticNotificationSetupCreatesOnceAndAutoProcessesLaterPayment() throws {
        let app = XCUIApplication()
        let suffix = String(UUID().uuidString.prefix(8))
        let source = "Northstar UI \(suffix) (fictional)"
        let alpha = "Merchant Alpha \(suffix)"
        let beta = "Merchant Beta \(suffix)"
        app.launchEnvironment["EASYTRACK_TEST_SAMPLE_SOURCE"] = source
        app.launchEnvironment["EASYTRACK_TEST_MERCHANT_SUFFIX"] = suffix
        app.launch()
        app.tabBars.buttons["Automations"].tap()
        app.buttons["Try fictional notification"].tap()
        app.buttons["Northstar Pay sample"].tap()
        let sourceCard = app.buttons["automationSource-\(source)"]
        XCTAssertTrue(sourceCard.waitForExistence(timeout: 8), app.debugDescription)
        sourceCard.tap()
        XCTAssertTrue(app.staticTexts["Set up notification format"].waitForExistence(timeout: 8))
        app.buttons["Set up format"].tap()
        XCTAssertTrue(app.navigationBars["Automation setup"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["parserStep-3"].label.contains("12,34"))
        XCTAssertTrue(app.buttons["parserStep-4"].label.contains(alpha))

        tapParserStep(1, in: app)
        let account = app.textFields["parserAccountField"]
        XCTAssertTrue(account.waitForExistence(timeout: 5), app.debugDescription)
        replaceText(in: account, with: "Fictional checking \(suffix)")
        app.swipeUp()
        let test = app.buttons["testAutomationButton"]
        for _ in 0..<8 where !test.isHittable { app.swipeUp() }
        XCTAssertTrue(test.isHittable, app.debugDescription)
        test.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Every step passed")).firstMatch.waitForExistence(timeout: 8))
        let activate = app.buttons["activateAutomationButton"]
        XCTAssertTrue(activate.isEnabled)
        activate.tap()
        app.buttons["Create first transaction"].tap()
        XCTAssertTrue(app.staticTexts["Transaction created"].waitForExistence(timeout: 8), app.debugDescription)

        app.tabBars.buttons["Home"].tap()
        let uncategorizedTitle = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label == %@",
                                                                      "homeUncategorizedSection", "Uncategorized")).firstMatch
        let alphaRow = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                                       "homeUncategorizedSection", alpha)).firstMatch
        XCTAssertTrue(uncategorizedTitle.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(alphaRow.exists)

        app.terminate()
        app.launch()
        XCTAssertTrue(uncategorizedTitle.waitForExistence(timeout: 8))
        app.tabBars.buttons["Automations"].tap()
        let sourceAgain = app.buttons["automationSource-\(source)"]
        XCTAssertTrue(sourceAgain.waitForExistence(timeout: 8))
        sourceAgain.tap()
        XCTAssertTrue(app.staticTexts["Transaction created"].waitForExistence(timeout: 8))
        app.navigationBars.buttons["Automations"].tap()

        app.buttons["Try fictional notification"].tap()
        app.buttons["Northstar Pay sample"].tap()
        sourceAgain.tap()
        XCTAssertTrue(app.staticTexts["Duplicate ignored"].waitForExistence(timeout: 8))
        app.navigationBars.buttons["Automations"].tap()

        app.buttons["Try fictional notification"].tap()
        app.buttons["Northstar Pay different merchant"].tap()
        sourceAgain.tap()
        XCTAssertTrue(app.staticTexts["Transaction created"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "3 captured · 1 active")).firstMatch.exists)
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts[beta].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "7,89")).firstMatch.exists)

        app.tabBars.buttons["Home"].tap()
        let betaRow = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                                      "homeUncategorizedSection", beta)).firstMatch
        XCTAssertTrue(alphaRow.waitForExistence(timeout: 8))
        XCTAssertTrue(betaRow.exists)
        alphaRow.tap()
        let category = app.textFields["transactionCategoryField"]
        for _ in 0..<4 where !category.isHittable { app.swipeUp() }
        XCTAssertTrue(category.waitForExistence(timeout: 5), app.debugDescription)
        category.tap()
        category.typeText("Shopping")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["EasyTrack"].waitForExistence(timeout: 8))
        XCTAssertTrue(betaRow.waitForExistence(timeout: 8))
        XCTAssertFalse(alphaRow.exists)
    }

    @MainActor
    func testFirstSampleFailureRemainsVisibleAndRetriesWithoutAnotherRule() throws {
        let app = XCUIApplication()
        let suffix = String(UUID().uuidString.prefix(8))
        let source = "Northstar failure \(suffix) (fictional)"
        app.launchEnvironment["EASYTRACK_TEST_SAMPLE_SOURCE"] = source
        app.launchEnvironment["EASYTRACK_TEST_MERCHANT_SUFFIX"] = suffix
        app.launchEnvironment["EASYTRACK_TEST_FAIL_PARSER_ONCE"] = suffix
        app.launch()
        app.tabBars.buttons["Automations"].tap()
        app.buttons["Try fictional notification"].tap()
        app.buttons["Northstar Pay sample"].tap()
        let sourceCard = app.buttons["automationSource-\(source)"]
        XCTAssertTrue(sourceCard.waitForExistence(timeout: 8))
        sourceCard.tap()
        app.buttons["Set up format"].tap()
        tapParserStep(1, in: app)
        let account = app.textFields["parserAccountField"]
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        replaceText(in: account, with: "Failure checking \(suffix)")
        app.swipeUp()
        let test = app.buttons["testAutomationButton"]
        for _ in 0..<8 where !test.isHittable { app.swipeUp() }
        test.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Every step passed")).firstMatch.waitForExistence(timeout: 8))
        app.buttons["activateAutomationButton"].tap()
        app.buttons["Create first transaction"].tap()
        XCTAssertTrue(app.navigationBars["Automation setup"].exists)
        XCTAssertTrue(app.staticTexts["Local save failed. Retry this sample."].waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Could not create transaction"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1 active")).firstMatch.exists)
        app.buttons["Retry"].tap()
        XCTAssertTrue(app.staticTexts["Transaction created"].waitForExistence(timeout: 8), app.debugDescription)
    }

    @MainActor
    func testDailyManualTransactionAndManagedReferences() throws {
        let app = XCUIApplication()
        let suffix = String(UUID().uuidString.prefix(8))
        let accountName = "Fictional Wallet \(suffix)"
        let renamedAccount = "Fictional Wallet Renamed \(suffix)"
        let categoryName = "Fictional Hobby \(suffix)"
        let description = "Fictional Notebook \(suffix)"
        app.launch()
        try requireSyntheticHistory(app)

        app.buttons["settingsAccountsLink"].tap()
        app.buttons["addAccountButton"].tap()
        let accountField = app.textFields["accountNameField"]
        XCTAssertTrue(accountField.waitForExistence(timeout: 5))
        accountField.tap()
        accountField.typeText(accountName)
        app.buttons["saveAccountButton"].tap()
        XCTAssertTrue(app.buttons["accountRow-\(accountName)"].waitForExistence(timeout: 5))
        app.buttons["accountRow-\(accountName)"].tap()
        replaceText(in: app.textFields["accountNameField"], with: renamedAccount)
        app.buttons["saveAccountButton"].tap()
        XCTAssertTrue(app.buttons["accountRow-\(renamedAccount)"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Settings"].tap()

        app.buttons["settingsCategoriesLink"].tap()
        app.buttons["addCategoryButton"].tap()
        let categoryField = app.textFields["categoryNameField"]
        XCTAssertTrue(categoryField.waitForExistence(timeout: 5))
        categoryField.tap()
        categoryField.typeText(categoryName)
        app.buttons["saveCategoryButton"].tap()
        XCTAssertTrue(app.navigationBars["Categories"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Home"].tap()

        let homeTotal = app.staticTexts["homePersonalSpendingTotal"]
        let before = homeTotal.label
        app.buttons["homeAddTransactionButton"].tap()
        XCTAssertTrue(app.navigationBars["New transaction"].waitForExistence(timeout: 5))
        replaceText(in: app.textFields["transactionAmountField"], with: "12,34")
        replaceText(in: app.textFields["transactionDescriptionField"], with: description)
        let accountPicker = app.buttons["transactionAccountPicker"]
        for _ in 0..<4 where !accountPicker.isHittable { app.swipeUp() }
        accountPicker.tap()
        if !app.navigationBars["Choose account"].waitForExistence(timeout: 2) { accountPicker.tap() }
        XCTAssertTrue(app.navigationBars["Choose account"].waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<8 where !app.buttons[renamedAccount].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons[renamedAccount].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons[renamedAccount].tap()
        let categoryPicker = app.buttons["transactionCategoryPicker"]
        for _ in 0..<4 where !categoryPicker.isHittable { app.swipeUp() }
        categoryPicker.tap()
        if !app.navigationBars["Choose category"].waitForExistence(timeout: 2) { categoryPicker.tap() }
        XCTAssertTrue(app.navigationBars["Choose category"].waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<8 where !app.buttons[categoryName].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons[categoryName].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons[categoryName].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["EasyTrack"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(homeTotal.label, before)
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts[description].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "12,34")).firstMatch.exists)

        app.terminate()
        app.launch()
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts[description].waitForExistence(timeout: 5))
        app.staticTexts[description].tap()
        XCTAssertTrue(app.navigationBars["Edit transaction"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["transactionAmountField"].value as? String, "12,34")
        XCTAssertEqual(app.textFields["transactionCategoryField"].value as? String, categoryName)
        XCTAssertTrue(app.staticTexts[renamedAccount].exists)
        app.navigationBars.buttons["Activity"].tap()

        app.tabBars.buttons["Home"].tap()
        app.buttons["homeAddTransactionButton"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.navigationBars["New transaction"].exists)
    }

    @MainActor
    func testRecurringSubscriptionCreatesOnceAndShowsUpcoming() throws {
        let app = XCUIApplication()
        let suffix = String(UUID().uuidString.prefix(8))
        let accountName = "Fictional Repeating Wallet \(suffix)"
        let ruleName = "Fictional Weekly Pass \(suffix)"
        app.launch()
        try requireSyntheticHistory(app)
        app.buttons["settingsAccountsLink"].tap()
        app.buttons["addAccountButton"].tap()
        let accountField = app.textFields["accountNameField"]
        XCTAssertTrue(accountField.waitForExistence(timeout: 5))
        accountField.tap()
        accountField.typeText(accountName)
        app.buttons["saveAccountButton"].tap()
        XCTAssertTrue(app.buttons["accountRow-\(accountName)"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Settings"].tap()

        app.buttons["settingsRecurringLink"].tap()
        attach(app, name: "recurring-list-synthetic")
        app.buttons["addRecurringRuleButton"].tap()
        attach(app, name: "recurring-editor-synthetic")
        let name = app.textFields["recurringNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(ruleName)
        replaceText(in: app.textFields["recurringAmountField"], with: "2,50")
        let picker = app.buttons["recurringAccountPicker"]
        for _ in 0..<4 where !picker.isHittable { app.swipeUp() }
        picker.tap()
        XCTAssertTrue(app.navigationBars["Choose account"].waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<8 where !app.buttons[accountName].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons[accountName].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons[accountName].tap()
        let frequency = app.buttons["recurringFrequencyPicker"]
        for _ in 0..<4 where !frequency.isHittable { app.swipeUp() }
        frequency.tap()
        XCTAssertTrue(app.navigationBars["Repeat"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Weekly"].tap()
        app.buttons["saveRecurringRuleButton"].tap()
        XCTAssertTrue(app.navigationBars["Recurring"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts[ruleName].waitForExistence(timeout: 5))
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.staticTexts["homeUpcomingSection"].waitForExistence(timeout: 5))
        attach(app, name: "home-with-upcoming-synthetic")
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts[ruleName].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts[ruleName].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDailyVisualNavigationSynthetic() throws {
        let app = XCUIApplication()
        app.launch()
        try requireSyntheticHistory(app)
        attach(app, name: "daily-settings")
        app.buttons["settingsAccountsLink"].tap()
        attach(app, name: "daily-accounts")
        app.navigationBars.buttons["Settings"].tap()
        app.buttons["settingsCategoriesLink"].tap()
        attach(app, name: "daily-categories")
        app.navigationBars.buttons["Settings"].tap()
        app.buttons["settingsRecurringLink"].tap()
        attach(app, name: "daily-recurring-list")
        app.buttons["addRecurringRuleButton"].tap()
        attach(app, name: "daily-recurring-editor")
        app.buttons["Cancel"].tap()

        app.tabBars.buttons["Automations"].tap()
        attach(app, name: "daily-automations")
        app.tabBars.buttons["Home"].tap()
        attach(app, name: "daily-home")
        app.buttons["homeAddTransactionButton"].tap()
        attach(app, name: "daily-new-transaction")
        app.buttons["Cancel"].tap()
        app.tabBars.buttons["Activity"].tap()
        attach(app, name: "daily-activity")
        let search = app.textFields["transactionSearchField"]
        search.tap()
        search.typeText("Fictional Notebook")
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Fictional Notebook")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.tap()
        XCTAssertTrue(app.navigationBars["Edit transaction"].waitForExistence(timeout: 5))
        attach(app, name: "daily-edit-transaction")
    }

    @MainActor
    func testRecurringControlsPreservePastSyntheticTransactions() throws {
        let app = XCUIApplication()
        app.launch()
        try requireSyntheticHistory(app)
        app.buttons["settingsRecurringLink"].tap()
        let more = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "More options for Fictional Weekly Pass")).firstMatch
        for _ in 0..<5 where !more.exists { app.swipeUp() }
        guard more.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires the fictional weekly rule created by the focused UI test")
        }
        let ruleName = String(more.label.dropFirst("More options for ".count))
        for _ in 0..<5 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.isHittable, app.debugDescription)
        let resume = app.buttons["Resume"]
        if resume.exists {
            resume.tap()
            XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        }
        more.tap()
        if !app.buttons["Pause"].waitForExistence(timeout: 2) { more.tap() }
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Pause"].tap()
        for _ in 0..<5 where !resume.exists { app.swipeUp() }
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))

        app.buttons["Edit \(ruleName)"].tap()
        let amount = app.textFields["recurringAmountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        replaceText(in: amount, with: "3,00")
        app.buttons["saveRecurringRuleButton"].tap()
        XCTAssertTrue(app.navigationBars["Recurring"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "3,00")).firstMatch.exists)

        app.buttons["Skip"].tap()
        app.buttons["Skip once"].tap()
        app.buttons["Create now"].tap()
        XCTAssertTrue(app.alerts["Recurring payment"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        more.tap()
        app.buttons["Archive"].tap()
        app.buttons["Archive rule"].tap()
        XCTAssertFalse(app.buttons["Edit \(ruleName)"].exists)
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Fictional Weekly Pass")).firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testManualCancelDoesNotCreateTransaction() throws {
        let app = XCUIApplication()
        let description = "Fictional Cancelled \(UUID().uuidString.prefix(8))"
        app.launch()
        try requireSyntheticHistory(app)
        app.tabBars.buttons["Home"].tap()
        let total = app.staticTexts["homePersonalSpendingTotal"]
        let before = total.label
        app.buttons["homeAddTransactionButton"].tap()
        replaceText(in: app.textFields["transactionAmountField"], with: "5.25")
        replaceText(in: app.textFields["transactionDescriptionField"], with: description)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["EasyTrack"].waitForExistence(timeout: 5))
        XCTAssertEqual(total.label, before)
        app.tabBars.buttons["Activity"].tap()
        let search = app.textFields["transactionSearchField"]
        search.tap()
        search.typeText(description)
        XCTAssertFalse(app.staticTexts[description].exists)
        app.terminate()
        app.launch()
        app.tabBars.buttons["Activity"].tap()
        let searchAgain = app.textFields["transactionSearchField"]
        searchAgain.tap()
        searchAgain.typeText(description)
        XCTAssertFalse(app.staticTexts[description].exists)
    }

    @MainActor
    func testManagedArchiveAndRestoreSynthetic() throws {
        let app = XCUIApplication()
        let suffix = String(UUID().uuidString.prefix(8))
        let accountName = "Fictional Archive Wallet \(suffix)"
        let categoryName = "Fictional Archive Category \(suffix)"
        app.launch()
        try requireSyntheticHistory(app)
        app.buttons["settingsAccountsLink"].tap()
        app.buttons["addAccountButton"].tap()
        let accountField = app.textFields["accountNameField"]
        accountField.tap()
        accountField.typeText(accountName)
        app.buttons["saveAccountButton"].tap()
        let accountRow = app.buttons["accountRow-\(accountName)"]
        for _ in 0..<12 where !accountRow.exists { app.swipeUp() }
        XCTAssertTrue(accountRow.waitForExistence(timeout: 5))
        accountRow.tap()
        let accountArchive = app.switches["Archived"]
        XCTAssertEqual(accountArchive.value as? String, "0")
        accountArchive.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(app.switches["Archived"].value as? String, "1")
        app.buttons["saveAccountButton"].tap()
        for _ in 0..<12 where !accountRow.exists { app.swipeUp() }
        XCTAssertTrue(accountRow.waitForExistence(timeout: 5))
        accountRow.tap()
        XCTAssertEqual(app.switches["Archived"].value as? String, "1")
        app.switches["Archived"].coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        app.buttons["saveAccountButton"].tap()
        app.navigationBars.buttons["Settings"].tap()

        app.buttons["settingsCategoriesLink"].tap()
        app.buttons["addCategoryButton"].tap()
        let categoryField = app.textFields["categoryNameField"]
        categoryField.tap()
        categoryField.typeText(categoryName)
        app.buttons["saveCategoryButton"].tap()
        let categoryRow = app.buttons["categoryRow-\(categoryName)"]
        for _ in 0..<12 where !categoryRow.exists { app.swipeUp() }
        XCTAssertTrue(categoryRow.waitForExistence(timeout: 5), app.debugDescription)
        categoryRow.tap()
        app.switches["Archived"].coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(app.switches["Archived"].value as? String, "1")
        app.buttons["saveCategoryButton"].tap()
        for _ in 0..<12 where !categoryRow.exists { app.swipeUp() }
        XCTAssertTrue(categoryRow.waitForExistence(timeout: 5))
        categoryRow.tap()
        XCTAssertEqual(app.switches["Archived"].value as? String, "1")
        app.switches["Archived"].coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        app.buttons["saveCategoryButton"].tap()
        XCTAssertTrue(app.navigationBars["Categories"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func requireSyntheticHistory(_ app: XCUIApplication) throws {
        app.tabBars.buttons["Settings"].tap()
        let marker = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1 historical movements imported")).firstMatch
        guard marker.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires the synthetic one-row simulator database")
        }
    }

    @MainActor
    private func tapParserStep(_ index: Int, in app: XCUIApplication) {
        let step = app.buttons["parserStep-\(index)"]
        XCTAssertTrue(step.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<8 {
            let y = step.frame.midY
            if y > 170 && y < app.frame.height * 0.72 { break }
            app.swipeUp()
        }
        XCTAssertTrue(step.frame.midY > 170 && step.frame.midY < app.frame.height * 0.72, app.debugDescription)
        for _ in 0..<3 {
            if (step.value as? String) == "Expanded" { break }
            step.tap()
        }
        XCTAssertEqual(step.value as? String, "Expanded", app.debugDescription)
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
        let search = app.textFields["transactionSearchField"]
        search.tap()
        search.typeText("Synthetic Account")
        let row = app.staticTexts.matching(NSPredicate(
            format: "label == %@ OR label == %@", "Synthetic Edited Purchase", "Synthetic Grocery")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
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
