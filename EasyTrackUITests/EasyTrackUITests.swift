import XCTest

final class EasyTrackUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func englishApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-easyTrackLanguage", "en"]
        return app
    }

    @MainActor
    func testItalianDefaultAndEnglishSwitchPreservesSyntheticLedger() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Attività"].waitForExistence(timeout: 10), app.debugDescription)
        app.tabBars.buttons["Impostazioni"].tap()
        let language = app.descendants(matching: .any)["settingsLanguagePicker"]
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        language.tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.tabBars.buttons["Activity"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Activity"].tap()
        let search = app.textFields["transactionSearchField"]
        replaceText(in: search, with: "Willowmere Home")
        XCTAssertTrue(app.staticTexts["Willowmere Home"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Activity"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()
        app.buttons["settingsAppearanceLink"].tap()
        let density = app.descendants(matching: .any)["settingsDisplayDensityPicker"]
        for _ in 0..<8 where !density.isHittable { app.swipeUp() }
        XCTAssertTrue(density.waitForExistence(timeout: 5))
        app.buttons["Compact"].tap()
        app.navigationBars["Appearance"].buttons["Settings"].tap()
        let languageAgain = app.descendants(matching: .any)["settingsLanguagePicker"]
        languageAgain.tap()
        app.buttons["Italiano"].tap()
        XCTAssertTrue(app.navigationBars["Impostazioni"].waitForExistence(timeout: 5))
        let italianActivityTab = app.tabBars.buttons["Attività"]
        if !italianActivityTab.exists {
            let collapsedSettingsTab = app.tabBars.buttons["Impostazioni"]
            if collapsedSettingsTab.exists { collapsedSettingsTab.tap() }
        }
        for _ in 0..<4 where !italianActivityTab.exists { app.swipeDown() }
        XCTAssertTrue(italianActivityTab.waitForExistence(timeout: 5))
        italianActivityTab.tap()
        let italianSearch = app.textFields["transactionSearchField"]
        replaceText(in: italianSearch, with: "Willowmere Home")
        XCTAssertTrue(app.staticTexts["Willowmere Home"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testReview35FirstCapturePromptAndDeletionPersist() throws {
        #if EASYTRACK_REVIEW35
        let suffix = String(UUID().uuidString.prefix(8))
        let sourceName = "Review Wallet \(suffix) (fictional)"
        let app = englishApp()
        app.launchEnvironment["EASYTRACK_TEST_SAMPLE_SOURCE"] = sourceName
        app.launchEnvironment["EASYTRACK_TEST_MERCHANT_SUFFIX"] = suffix
        app.launch()
        app.tabBars.buttons["Automations"].tap()
        app.buttons["Try fictional notification"].tap()
        app.buttons["Northstar Pay sample"].tap()
        let prompt = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "firstCaptureSetup-")).firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(prompt.label.contains("not a recorded transaction"))
        XCTAssertTrue(prompt.label.contains("separate formats"))
        prompt.tap()
        XCTAssertTrue(app.navigationBars["Automation setup"].waitForExistence(timeout: 8))
        app.buttons["Cancel"].tap()

        let source = app.buttons["automationSource-\(sourceName)"]
        XCTAssertTrue(source.waitForExistence(timeout: 8))
        source.tap()
        let delete = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "deleteCapture-")).firstMatch
        for _ in 0..<7 where !delete.isHittable { app.swipeUp() }
        XCTAssertTrue(delete.isHittable)
        delete.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "This capture disappears from the list")).firstMatch.exists)
        app.buttons["Delete notification"].tap()
        XCTAssertTrue(app.staticTexts["0 captured · 0 active"].waitForExistence(timeout: 8))
        app.terminate()
        app.launch()
        app.tabBars.buttons["Automations"].tap()
        source.tap()
        XCTAssertTrue(app.staticTexts["0 captured · 0 active"].waitForExistence(timeout: 8))
        XCTAssertFalse(prompt.exists)
        #else
        throw XCTSkip("Run on an isolated PR #35 test bundle")
        #endif
    }

    @MainActor
    func testReview35CrossAccountSettlementPickerAndCancel() throws {
        #if EASYTRACK_REVIEW35
        let app = englishApp()
        let description = "Fictional review expense \(UUID().uuidString.prefix(8))"
        app.launch()
        app.buttons["homeAddTransactionButton"].tap()
        XCTAssertTrue(app.navigationBars["New transaction"].waitForExistence(timeout: 8))
        replaceText(in: app.textFields["transactionOriginalAmountField"], with: "50,00")
        replaceText(in: app.textFields["transactionDescriptionField"], with: description)
        let expecting = app.switches["expectsReimbursementToggle"]
        for _ in 0..<8 where !expecting.isHittable { app.swipeUp() }
        XCTAssertTrue(expecting.isHittable)
        XCTAssertEqual(expecting.value as? String, "0")
        expecting.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(expecting.value as? String, "1")
        app.buttons["Save"].tap()

        app.tabBars.buttons["Activity"].tap()
        let search = app.textFields["transactionSearchField"]
        search.tap()
        search.typeText(description)
        let row = app.staticTexts[description]
        XCTAssertTrue(row.waitForExistence(timeout: 8), app.debugDescription)
        row.tap()
        let receive = app.buttons["receiveReimbursementButton"]
        for _ in 0..<8 where !receive.isHittable { app.swipeUp() }
        XCTAssertTrue(receive.isHittable)
        receive.tap()
        XCTAssertTrue(app.navigationBars["Reimbursement received"].waitForExistence(timeout: 8))
        let picker = app.buttons["reimbursementReceivingAccountPicker"]
        for _ in 0..<6 where !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(picker.label.contains("Sample Checking"))
        picker.tap()
        XCTAssertTrue(app.navigationBars["Choose account"].waitForExistence(timeout: 5))
        app.buttons["Sample Savings"].tap()
        XCTAssertTrue(picker.label.contains("Sample Savings"))
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.navigationBars["Reimbursement received"].exists)
        XCTAssertTrue(receive.exists)
        let unlink = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Unlink reimbursement")).firstMatch
        XCTAssertFalse(unlink.exists)

        receive.tap()
        picker.tap()
        app.buttons["Sample Savings"].tap()
        let record = app.buttons["recordAndLinkReimbursementButton"]
        for _ in 0..<6 where !record.isHittable { app.swipeUp() }
        XCTAssertTrue(record.isEnabled)
        record.tap()
        XCTAssertTrue(unlink.waitForExistence(timeout: 8))
        XCTAssertFalse(receive.exists)
        #else
        throw XCTSkip("Run on an isolated PR #35 test bundle")
        #endif
    }

    @MainActor
    private func showcaseApp() throws -> XCUIApplication {
        #if EASYTRACK_SHOWCASE_CAPTURE
        let app = englishApp()
        app.launch()
        return app
        #else
        throw XCTSkip("Run only from scripts/capture_showcase.py with an isolated sample app")
        #endif
    }

    @MainActor
    func testCaptureShowcaseHomeActivityAndEntry() throws {
        let app = try showcaseApp()
        XCTAssertTrue(app.staticTexts["homePersonalSpendingTotal"].waitForExistence(timeout: 10))
        attach(app, name: "home")
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        attach(app, name: "activity")
        app.tabBars.buttons["Home"].tap()
        app.buttons["homeAddTransactionButton"].tap()
        XCTAssertTrue(app.navigationBars["New transaction"].waitForExistence(timeout: 5))
        let amount = app.textFields["transactionOriginalAmountField"]
        amount.tap()
        amount.typeText("32,40")
        let description = app.textFields["transactionDescriptionField"]
        description.tap()
        description.typeText("Weekly groceries")
        app.swipeDown()
        attach(app, name: "quick-entry")
    }

    @MainActor
    func testCaptureShowcaseAnalytics() throws {
        let app = try showcaseApp()
        XCTAssertTrue(app.staticTexts["homePersonalSpendingTotal"].waitForExistence(timeout: 10))
        app.swipeUp()
        attach(app, name: "analytics")
    }

    @MainActor
    func testCaptureShowcaseAccounts() throws {
        let app = try showcaseApp()
        app.tabBars.buttons["Settings"].tap()
        let accounts = app.buttons["settingsAccountsLink"]
        for _ in 0..<8 where !accounts.isHittable { app.swipeUp() }
        XCTAssertTrue(accounts.isHittable)
        accounts.tap()
        XCTAssertTrue(app.navigationBars["Accounts"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Selected"].exists)
        attach(app, name: "accounts")
    }

    @MainActor
    func testCaptureShowcaseAutomation() throws {
        let app = try showcaseApp()
        app.tabBars.buttons["Automations"].tap()
        let source = app.buttons["automationSource-Sample Wallet"]
        for _ in 0..<5 where !source.isHittable { app.swipeUp() }
        XCTAssertTrue(source.isHittable)
        source.tap()
        let edit = app.buttons["Edit Card payments"]
        for _ in 0..<5 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        XCTAssertTrue(app.navigationBars["Automation setup"].waitForExistence(timeout: 5))
        attach(app, name: "automation")
    }

    @MainActor
    func testHomeAndActivitySearch() throws {
        let app = englishApp()
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
        let app = englishApp()
        app.launch()
        try requireDemoOnly(app)
        app.tabBars.buttons["Activity"].tap()
        app.buttons["Income"].tap()
        XCTAssertTrue(app.staticTexts["Demo · Salary"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Demo · Coffee Shop")).firstMatch.exists)
    }

    @MainActor
    func testUpdatedMonthHeroAndUnifiedEverydayNavigation() throws {
        let app = englishApp()
        app.launch()
        let total = app.staticTexts["homePersonalSpendingTotal"]
        XCTAssertTrue(total.waitForExistence(timeout: 10), app.debugDescription)

        let month = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Selected month,")).firstMatch
        let previous = app.buttons["Previous month"]
        let next = app.buttons["Next month"]
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        for _ in 0..<73 where next.isEnabled { next.tap() }
        let currentLabel = month.label
        previous.tap()
        XCTAssertNotEqual(month.label, currentLabel)
        XCTAssertTrue(total.exists)
        XCTAssertFalse(app.buttons["homeCurrentMonthButton"].exists)

        var foundEmptyMonth = app.staticTexts["No transactions"].exists
        for _ in 0..<72 where !foundEmptyMonth {
            previous.tap()
            foundEmptyMonth = app.staticTexts["No transactions"].exists
        }
        XCTAssertTrue(foundEmptyMonth, "Expected to reach a visually empty historical month")
        XCTAssertTrue(total.exists)
        for _ in 0..<73 where next.isEnabled { next.tap() }
        XCTAssertEqual(month.label, currentLabel)

        app.tabBars.buttons["Settings"].tap()
        XCTAssertFalse(app.staticTexts["Local database · available offline"].exists)
        XCTAssertFalse(app.buttons["Choose folder in Files"].exists)
        XCTAssertFalse(app.buttons["Write and read test file"].exists)
        let categories = app.buttons["settingsCategoriesLink"]
        for _ in 0..<5 where !categories.isHittable { app.swipeUp() }
        XCTAssertTrue(categories.isHittable, app.debugDescription)
        XCTAssertFalse(app.buttons["settingsCategorySuggestionsLink"].exists)
        categories.tap()
        XCTAssertTrue(app.navigationBars["Categories"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["addCategoryButton"].exists)
        let suggestionToggle = app.switches["Category suggestions"]
        for _ in 0..<8 where !suggestionToggle.exists { app.swipeUp() }
        XCTAssertTrue(suggestionToggle.waitForExistence(timeout: 5), app.debugDescription)
        app.navigationBars.buttons["Settings"].tap()

        let trips = app.buttons["settingsTripsLink"]
        for _ in 0..<5 where !trips.isHittable { app.swipeUp() }
        XCTAssertTrue(trips.isHittable)
        trips.tap()
        XCTAssertTrue(app.navigationBars["Trips"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["addTripButton"].exists)
        app.navigationBars.buttons["Settings"].tap()

        let accounts = app.buttons["settingsAccountsLink"]
        for _ in 0..<5 where !accounts.isHittable { app.swipeDown() }
        XCTAssertTrue(accounts.isHittable)
        accounts.tap()
        XCTAssertTrue(app.navigationBars["Accounts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["defaultExpenseAccountPicker"].exists)
        XCTAssertFalse(app.staticTexts["Selected"].exists)
        app.navigationBars.buttons["Settings"].tap()
        let seedImport = app.buttons["Choose SQLite seed"]
        for _ in 0..<10 where !seedImport.exists { app.swipeUp() }
        XCTAssertTrue(seedImport.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testHeroCustomizationPersistsAndRestores() throws {
        let app = englishApp()
        app.launch()
        app.buttons["customizeHomeButton"].tap()
        XCTAssertTrue(app.navigationBars["Customize Home"].waitForExistence(timeout: 5))
        let reset = app.buttons["Restore default layout"]
        for _ in 0..<8 where !reset.isHittable { app.swipeUp() }
        reset.tap()
        app.buttons["Restore defaults"].tap()

        let picker = app.descendants(matching: .any)["homePrimaryMetricPicker"]
        for _ in 0..<8 where !picker.isHittable { app.swipeDown() }
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons["Expenses"].tap()
        let previewTotal = app.staticTexts.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@",
            "homePersonalSpendingTotal", "Expenses")).firstMatch
        XCTAssertTrue(previewTotal.exists)
        app.buttons["Done"].tap()
        let total = app.staticTexts["homePersonalSpendingTotal"]
        XCTAssertTrue(total.label.contains("Expenses"))
        app.terminate()
        app.launch()
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.contains("Expenses"))

        app.buttons["customizeHomeButton"].tap()
        for _ in 0..<8 where !reset.isHittable { app.swipeUp() }
        reset.tap()
        app.buttons["Restore defaults"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(total.label.contains("Net"))
    }

    @MainActor
    func testHomeIncomeAndExpensesOpenCompletePeriodActivity() throws {
        #if EASYTRACK_ACCOUNTING_AUDIT
        let app = englishApp()
        app.launch()
        let income = app.buttons["homeIncomeMetric"]
        XCTAssertTrue(income.waitForExistence(timeout: 10), app.debugDescription)
        income.tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["activityChartFilter"].exists)
        let search = app.textFields["transactionSearchField"]
        replaceText(in: search, with: "Shared weekend refund")
        XCTAssertTrue(app.staticTexts["Shared weekend refund"].waitForExistence(timeout: 5))
        replaceText(in: search, with: "Willowmere Home")
        XCTAssertFalse(app.staticTexts["Willowmere Home"].exists)
        app.navigationBars["Activity"].buttons["EasyTrack"].tap()

        app.buttons["customizeHomeButton"].tap()
        XCTAssertTrue(app.navigationBars["Customize Home"].waitForExistence(timeout: 5))
        let picker = app.descendants(matching: .any)["homePrimaryMetricPicker"]
        for _ in 0..<8 where !picker.isHittable { app.swipeDown() }
        picker.tap()
        app.buttons["Expenses"].tap()
        app.buttons["Done"].tap()
        let expenses = app.buttons["homeExpensesMetric"]
        XCTAssertTrue(expenses.waitForExistence(timeout: 5))
        expenses.tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["activityChartFilter"].exists)
        replaceText(in: app.textFields["transactionSearchField"], with: "Willowmere Home")
        XCTAssertTrue(app.staticTexts["Willowmere Home"].waitForExistence(timeout: 5))
        replaceText(in: app.textFields["transactionSearchField"], with: "Shared weekend refund")
        XCTAssertFalse(app.staticTexts["Shared weekend refund"].exists)
        app.navigationBars["Activity"].buttons["EasyTrack"].tap()

        app.buttons["customizeHomeButton"].tap()
        let netPicker = app.descendants(matching: .any)["homePrimaryMetricPicker"]
        for _ in 0..<8 where !netPicker.isHittable { app.swipeDown() }
        netPicker.tap()
        app.buttons["Net"].tap()
        app.buttons["Done"].tap()
        app.buttons["homeNetMetric"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["activityContributionTotal"].waitForExistence(timeout: 5))
        replaceText(in: app.textFields["transactionSearchField"], with: "Shared weekend refund")
        XCTAssertTrue(app.staticTexts["Shared weekend refund"].waitForExistence(timeout: 5))
        app.navigationBars["Activity"].buttons["EasyTrack"].tap()

        app.buttons["customizeHomeButton"].tap()
        let personalPicker = app.descendants(matching: .any)["homePrimaryMetricPicker"]
        for _ in 0..<8 where !personalPicker.isHittable { app.swipeDown() }
        personalPicker.tap()
        app.buttons["Net Expenses"].tap()
        app.buttons["Done"].tap()
        app.buttons["homeNetExpensesMetric"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["activityContributionTotal"].waitForExistence(timeout: 5))
        replaceText(in: app.textFields["transactionSearchField"], with: "Willowmere Home")
        XCTAssertTrue(app.staticTexts["Willowmere Home"].waitForExistence(timeout: 5))
        #else
        throw XCTSkip("Run with the isolated accounting UI fixture")
        #endif
    }

    @MainActor
    func testAccountsDefaultPickerHasNoDuplicateSelectionRow() throws {
        let app = englishApp()
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        let accounts = app.buttons["settingsAccountsLink"]
        for _ in 0..<8 where !accounts.isHittable { app.swipeUp() }
        accounts.tap()
        XCTAssertTrue(app.navigationBars["Accounts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["defaultExpenseAccountPicker"].exists)
        XCTAssertFalse(app.staticTexts["Selected"].exists)
    }

    @MainActor
    func testEditPersistsAfterRelaunch() throws {
        let app = englishApp()
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
        let app = englishApp()
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
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose SQLite seed"].exists)
        attach(app, name: "settings-demo-only")
    }

    @MainActor
    func testSyntheticImportPreviewAndConfirm() throws {
        let app = englishApp()
        app.launch()
        try requireDemoOnly(app)
        selectSyntheticSeed(in: app)
        let importButton = app.buttons["Import 1 movements"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 10), app.debugDescription)
        importButton.tap()
    }

    @MainActor
    func testSyntheticReimportShowsZeroNewMovements() throws {
        let app = englishApp()
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
        let app = englishApp()
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
        let app = englishApp()
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

        let homeTab = app.tabBars.buttons["Home"]
        homeTab.tap()
        if !homeTab.isSelected { homeTab.tap() }
        XCTAssertTrue(homeTab.isSelected)
        for _ in 0..<5 where !homeTotal.exists { app.swipeDown() }
        XCTAssertTrue(homeTotal.waitForExistence(timeout: 5))
        let afterTotal = homeTotal.label
        XCTAssertNotEqual(afterTotal, beforeTotal)
        app.terminate()
        app.launch()
        if !homeTab.isSelected { homeTab.tap() }
        XCTAssertTrue(homeTab.isSelected)
        for _ in 0..<5 where !homeTotal.exists { app.swipeDown() }
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
    func testSyntheticJSONBackupExport() throws {
        let app = englishApp()
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
    func testDemoBackupRestorePreviewAndReplace() throws {
        let app = englishApp()
        app.launch()
        try requireDemoOnly(app)
        app.tabBars.buttons["Settings"].tap()
        let export = app.buttons["Export local data as JSON"]
        for _ in 0..<4 where !export.isHittable { app.swipeUp() }
        XCTAssertTrue(export.isHittable, app.debugDescription)
        export.tap()
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 20), app.debugDescription)
        save.tap()
        let success = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Exported EasyTrack-backup-")).firstMatch
        XCTAssertTrue(success.waitForExistence(timeout: 20), app.debugDescription)
        let filename = success.label.replacingOccurrences(of: "Exported ", with: "")

        let choose = app.buttons["chooseBackupToRestore"]
        for _ in 0..<4 where !choose.isHittable { app.swipeUp() }
        XCTAssertTrue(choose.isHittable, app.debugDescription)
        choose.tap()
        var file = app.staticTexts[filename]
        if !file.waitForExistence(timeout: 8) {
            let browse = app.buttons["Browse"]
            if browse.exists { browse.tap() }
            let local = app.staticTexts["On My iPhone"]
            if local.exists { local.tap() }
            let folder = app.staticTexts["EasyTrack"]
            if folder.exists { folder.tap() }
            file = app.staticTexts[filename]
        }
        XCTAssertTrue(file.waitForExistence(timeout: 15), app.debugDescription)
        let fileCell = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", filename)).firstMatch
        XCTAssertTrue(fileCell.exists, app.debugDescription)
        fileCell.tap()
        let preview = app.otherElements["backupRestorePreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "3 transactions")).firstMatch.exists)
        attach(app, name: "backup-restore-preview-demo")
        let replace = app.buttons["replaceFromBackup"]
        for _ in 0..<3 where !replace.isHittable { app.swipeUp() }
        replace.tap()
        XCTAssertTrue(app.buttons["Replace local ledger"].waitForExistence(timeout: 5))
        app.buttons["Replace local ledger"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Restore complete.")).firstMatch.waitForExistence(timeout: 30), app.debugDescription)
        app.terminate()
        app.launch()
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Demo · Coffee Shop")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Demo · Book Store"].exists)
        XCTAssertTrue(app.staticTexts["Demo · Salary"].exists)
    }

    @MainActor
    func testDemoExportScreenOpens() throws {
        let app = englishApp()
        app.launch()
        try requireDemoOnly(app)
        app.tabBars.buttons["Settings"].tap()
        let link = app.buttons["settingsTransactionExport"]
        for _ in 0..<6 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable, app.debugDescription)
        link.tap()
        XCTAssertTrue(app.navigationBars["Export transactions"].waitForExistence(timeout: 8), app.debugDescription)
        attach(app, name: "transaction-export-screen")
    }

    @MainActor
    func testFictionalCSVSave() throws {
        let app = englishApp()
        app.launch()
        try requireDemoOnly(app)
        try ensureFictionalExportTransaction(in: app)
        app.tabBars.buttons["Settings"].tap()
        let link = app.buttons["settingsTransactionExport"]
        for _ in 0..<6 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable, app.debugDescription)
        link.tap()
        XCTAssertTrue(app.navigationBars["Export transactions"].waitForExistence(timeout: 8))
        let saveExport = app.buttons["saveTransactionExport"]
        for _ in 0..<8 where !saveExport.isHittable { app.swipeUp() }
        XCTAssertTrue(saveExport.isHittable, app.debugDescription)
        XCTAssertTrue(saveExport.isEnabled, app.debugDescription)
        attach(app, name: "csv-export-ready")
        saveExport.tap()
        let saveFile = app.buttons["Save"]
        XCTAssertTrue(saveFile.waitForExistence(timeout: 20), app.debugDescription)
        saveFile.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Saved EasyTrack-transactions-")).firstMatch.waitForExistence(timeout: 15), app.debugDescription)
    }

    @MainActor
    func testFictionalXLSXSave() throws {
        let app = englishApp()
        app.launch()
        try requireDemoOnly(app)
        try ensureFictionalExportTransaction(in: app)
        app.tabBars.buttons["Settings"].tap()
        let link = app.buttons["settingsTransactionExport"]
        for _ in 0..<6 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable, app.debugDescription)
        link.tap()
        XCTAssertTrue(app.navigationBars["Export transactions"].waitForExistence(timeout: 8))
        app.buttons["XLSX"].tap()
        let summary = app.switches["Include Riepilogo summary sheet"]
        for _ in 0..<6 where !summary.isHittable { app.swipeUp() }
        XCTAssertTrue(summary.isHittable, app.debugDescription)
        if summary.value as? String != "1" {
            summary.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        XCTAssertEqual(summary.value as? String, "1", app.debugDescription)
        let saveExport = app.buttons["saveTransactionExport"]
        for _ in 0..<6 where !saveExport.isHittable { app.swipeUp() }
        XCTAssertTrue(saveExport.isHittable, app.debugDescription)
        XCTAssertTrue(saveExport.isEnabled, app.debugDescription)
        attach(app, name: "xlsx-export-ready")
        saveExport.tap()
        let saveFile = app.buttons["Save"]
        XCTAssertTrue(saveFile.waitForExistence(timeout: 20), app.debugDescription)
        saveFile.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Saved EasyTrack-transactions-")).firstMatch.waitForExistence(timeout: 15), app.debugDescription)
    }

    @MainActor
    func testActivityExportKeepsCurrentFilters() throws {
        let app = englishApp()
        app.launch()
        try requireDemoOnly(app)
        try ensureFictionalExportTransaction(in: app)
        let row = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Fictional Export Purchase")).firstMatch
        guard row.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires isolated fictional export transactions")
        }
        let selectedDescription = row.label
        let search = app.textFields["transactionSearchField"]
        search.tap()
        search.typeText(selectedDescription)
        XCTAssertTrue(app.staticTexts[selectedDescription].waitForExistence(timeout: 5))
        app.buttons["activityExportTransactions"].tap()
        XCTAssertTrue(app.navigationBars["Export transactions"].waitForExistence(timeout: 8))
        let notice = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Current Activity filters also apply.")).firstMatch
        for _ in 0..<6 where !notice.exists { app.swipeUp() }
        XCTAssertTrue(notice.waitForExistence(timeout: 5), app.debugDescription)
        let count = app.descendants(matching: .any)["transactionExportCount"]
        for _ in 0..<5 where !count.exists { app.swipeUp() }
        XCTAssertTrue(count.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(count.label.contains("1"), app.debugDescription)
    }

    @MainActor
    func testSyntheticNotificationSetupCreatesOnceAndAutoProcessesLaterPayment() throws {
        let app = englishApp()
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
        let app = englishApp()
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
        let app = englishApp()
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
        let app = englishApp()
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
        XCTAssertFalse(app.staticTexts[ruleName].exists)
        app.terminate()
        app.launch()
        app.tabBars.buttons["Activity"].tap()
        XCTAssertFalse(app.staticTexts[ruleName].exists)
    }

    @MainActor
    func testRecurringControlsPreservePastSyntheticTransactions() throws {
        let app = englishApp()
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
        app.buttons["Record paid manually"].tap()
        app.buttons["Record paid manually"].tap()
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
    func testExpectedRecurringManualPaymentPersistsWithoutDueDateSpending() throws {
        let app = englishApp()
        app.launch()
        try requireDemoOnly(app)
        let total = app.staticTexts["homePersonalSpendingTotal"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        let before = total.label
        let suffix = String(UUID().uuidString.prefix(8))
        let accountName = "Fictional Scenario Wallet \(suffix)"
        let ruleName = "Fictional Scenario Pass \(suffix)"

        app.tabBars.buttons["Settings"].tap()
        app.buttons["settingsAccountsLink"].tap()
        app.buttons["addAccountButton"].tap()
        let accountField = app.textFields["accountNameField"]
        XCTAssertTrue(accountField.waitForExistence(timeout: 5))
        accountField.tap()
        accountField.typeText(accountName)
        app.buttons["saveAccountButton"].tap()
        app.navigationBars.buttons["Settings"].tap()
        app.buttons["settingsRecurringLink"].tap()
        app.buttons["addRecurringRuleButton"].tap()
        app.textFields["recurringNameField"].tap()
        app.textFields["recurringNameField"].typeText(ruleName)
        replaceText(in: app.textFields["recurringAmountField"], with: "2,50")
        let picker = app.buttons["recurringAccountPicker"]
        for _ in 0..<4 where !picker.isHittable { app.swipeUp() }
        picker.tap()
        for _ in 0..<8 where !app.buttons[accountName].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons[accountName].waitForExistence(timeout: 5))
        app.buttons[accountName].tap()
        app.buttons["saveRecurringRuleButton"].tap()
        XCTAssertTrue(app.navigationBars["Recurring"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Home"].tap()
        XCTAssertEqual(total.label, before, "A due expectation must not enter personal spending")
        app.tabBars.buttons["Activity"].tap()
        XCTAssertFalse(app.staticTexts[ruleName].exists)
        app.tabBars.buttons["Settings"].tap()
        if !app.navigationBars["Recurring"].exists {
            app.buttons["settingsRecurringLink"].tap()
        }
        let history = app.buttons["Occurrence history for \(ruleName)"]
        XCTAssertTrue(history.waitForExistence(timeout: 5), app.debugDescription)
        history.tap()
        let occurrence = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recurringOccurrence-")).firstMatch
        XCTAssertTrue(occurrence.waitForExistence(timeout: 5), app.debugDescription)
        occurrence.tap()
        XCTAssertTrue(app.buttons["recordExpectedRecurringButton"].waitForExistence(timeout: 5))
        app.buttons["recordExpectedRecurringButton"].tap()
        app.buttons["Confirm manual recording"].tap()
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts[ruleName].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts[ruleName].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRecurringStatusControlsAtCurrentAppearanceAndTextSize() throws {
        let app = englishApp()
        app.launch()
        try requireDemoOnly(app)
        app.tabBars.buttons["Settings"].tap()
        app.buttons["settingsRecurringLink"].tap()
        let history = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@",
            "Occurrence history for Fictional Scenario Pass")).firstMatch
        for _ in 0..<10 where !history.isHittable { app.swipeUp() }
        guard history.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires the isolated fictional recurring UI fixture")
        }
        XCTAssertTrue(history.isHittable)
        history.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@",
            "recurringOccurrence-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Expected") || row.label.contains("Recorded manually"))
        row.tap()
        XCTAssertTrue(app.staticTexts["Scheduled payment"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Expected"].exists || app.staticTexts["Recorded manually"].exists)
        attach(app, name: "recurring-status-fictional")
    }

    @MainActor
    func testCollectiveRecurringImportReviewAndCancellation() throws {
        let app = englishApp()
        app.launch()
        try requireDemoOnly(app)
        selectSyntheticSeed(in: app, token: "issue4_collective_fixture")
        let conflictHeading = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            "Recurring overlaps · 2")).firstMatch
        XCTAssertTrue(conflictHeading.waitForExistence(timeout: 10), app.debugDescription)
        let importButton = app.buttons["Import 2 movements"]
        for _ in 0..<8 where !importButton.exists { app.swipeUp() }
        XCTAssertTrue(importButton.exists)
        XCTAssertFalse(importButton.isEnabled)
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@",
            "recurringConflictDecision-"))
        for _ in 0..<8 where choices.count < 2 { app.swipeDown() }
        XCTAssertEqual(choices.count, 2)
        choices.element(boundBy: 0).tap()
        app.buttons["Same payment"].tap()
        choices.element(boundBy: 1).tap()
        app.buttons["Same payment"].tap()
        for _ in 0..<8 where !importButton.exists { app.swipeUp() }
        XCTAssertFalse(importButton.isEnabled, "One source movement cannot settle the same occurrence twice")
        for _ in 0..<8 where !choices.element(boundBy: 1).isHittable { app.swipeDown() }
        XCTAssertTrue(choices.element(boundBy: 1).isHittable)
        choices.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["Separate payment"].waitForExistence(timeout: 5))
        app.buttons["Separate payment"].tap()
        for _ in 0..<8 where !importButton.exists { app.swipeUp() }
        XCTAssertTrue(importButton.isEnabled)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            "2 imported, 1 provisional records replaced")).firstMatch.exists)
        let discard = app.buttons["Discard preview"]
        for _ in 0..<8 where !discard.isHittable { app.swipeUp() }
        XCTAssertTrue(discard.isHittable)
        discard.tap()
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            "2 historical movements imported")).firstMatch.exists)

        selectSyntheticSeed(in: app, token: "issue4_collective_fixture")
        XCTAssertTrue(conflictHeading.waitForExistence(timeout: 10))
        for _ in 0..<8 where !choices.element(boundBy: 0).isHittable { app.swipeDown() }
        choices.element(boundBy: 0).tap()
        app.buttons["Same payment"].tap()
        for _ in 0..<8 where !choices.element(boundBy: 1).isHittable { app.swipeDown() }
        choices.element(boundBy: 1).tap()
        app.buttons["Separate payment"].tap()
        for _ in 0..<8 where !importButton.exists { app.swipeUp() }
        XCTAssertTrue(importButton.isEnabled)
        importButton.tap()
        let success = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            "Imported 2 movements")).firstMatch
        for _ in 0..<8 where !success.exists { app.swipeDown() }
        XCTAssertTrue(success.waitForExistence(timeout: 15), app.debugDescription)
        app.terminate()
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            "2 historical movements imported")).firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testRecurringReviewFromAutomationSourceAndUnlinkPersists() throws {
        let app = englishApp()
        app.launch()
        guard app.staticTexts["Historical seed not imported"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires the isolated fictional pending-review fixture")
        }
        let total = app.staticTexts["homePersonalSpendingTotal"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        let before = total.label
        let homeReview = app.descendants(matching: .any)["homeRecurringNeedsReview"]
        for _ in 0..<6 where !homeReview.exists { app.swipeUp() }
        XCTAssertTrue(homeReview.waitForExistence(timeout: 5), app.debugDescription)
        app.tabBars.buttons["Automations"].tap()
        let source = app.staticTexts["Northstar Pay (fictional)"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        XCTAssertTrue(app.staticTexts["Review recurring match"].waitForExistence(timeout: 5))
        let review = app.buttons["reviewRecurringMatch"]
        for _ in 0..<8 where !review.isHittable { app.swipeUp() }
        XCTAssertTrue(review.isHittable)
        review.tap()
        XCTAssertTrue(app.staticTexts["Needs review"].waitForExistence(timeout: 5))
        let confirm = app.buttons["Confirm payment"]
        for _ in 0..<8 where !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.isHittable)
        confirm.tap()
        app.buttons["Confirm this payment"].tap()
        app.tabBars.buttons["Home"].tap()
        let homePaid = app.descendants(matching: .any)["homeRecurringPaidStatus"]
        XCTAssertTrue(homePaid.waitForExistence(timeout: 5))
        let paidTotal = total.label
        XCTAssertNotEqual(paidTotal, before)
        homePaid.tap()
        XCTAssertTrue(app.buttons["Unlink recurring payment"].waitForExistence(timeout: 5))
        app.buttons["Unlink recurring payment"].tap()
        app.buttons["Unlink payment"].tap()
        app.tabBars.buttons["Home"].tap()
        XCTAssertEqual(total.label, paidTotal)
        app.terminate()
        app.launch()
        XCTAssertEqual(total.label, paidTotal)
        XCTAssertFalse(homeReview.exists)
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["Fictional Plan"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRecurringManualLinkSkipAndMissedPersist() throws {
        let app = englishApp()
        app.launch()
        guard app.staticTexts["Historical seed not imported"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires the isolated fictional manual-action fixture")
        }
        let total = app.staticTexts["homePersonalSpendingTotal"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        let before = total.label
        app.tabBars.buttons["Settings"].tap()
        app.buttons["settingsRecurringLink"].tap()
        let history = app.buttons["Occurrence history for Fictional Plan"]
        for _ in 0..<8 where !history.isHittable { app.swipeUp() }
        XCTAssertTrue(history.isHittable)
        history.tap()
        let january = app.buttons.matching(NSPredicate(format: "identifier CONTAINS %@",
            "|2026-01-31")).firstMatch
        XCTAssertTrue(january.waitForExistence(timeout: 5))
        january.tap()
        let skip = app.buttons["Skip this payment"]
        for _ in 0..<6 where !skip.isHittable { app.swipeUp() }
        skip.tap()
        app.buttons["Skip payment"].tap()
        let choose = app.buttons["Choose an existing transaction"]
        for _ in 0..<6 where !choose.isHittable { app.swipeUp() }
        XCTAssertTrue(choose.isHittable)
        choose.tap()
        let actual = app.buttons.matching(NSPredicate(format: "label CONTAINS %@",
            "Fictional Manual Charge")).firstMatch
        XCTAssertTrue(actual.waitForExistence(timeout: 5))
        actual.tap()
        app.buttons["Link payment"].tap()
        let unlink = app.buttons["Unlink actual transaction"]
        for _ in 0..<6 where !unlink.isHittable { app.swipeUp() }
        XCTAssertTrue(unlink.isHittable)
        unlink.tap()
        app.buttons["Unlink transaction"].tap()
        app.navigationBars["Recurring occurrence"].buttons.firstMatch.tap()
        let february = app.buttons.matching(NSPredicate(format: "identifier CONTAINS %@",
            "|2026-02-28")).firstMatch
        XCTAssertTrue(february.waitForExistence(timeout: 5))
        february.tap()
        let missed = app.buttons["Mark missed"]
        for _ in 0..<6 where !missed.isHittable { app.swipeUp() }
        missed.tap()
        app.buttons["Confirm missed"].tap()
        app.tabBars.buttons["Home"].tap()
        XCTAssertEqual(total.label, before)
        app.terminate()
        app.launch()
        XCTAssertEqual(total.label, before)
        app.tabBars.buttons["Settings"].tap()
        app.buttons["settingsRecurringLink"].tap()
        app.buttons["Occurrence history for Fictional Plan"].tap()
        XCTAssertTrue(february.waitForExistence(timeout: 5))
        XCTAssertTrue(february.label.contains("Missed"))
        XCTAssertTrue(january.label.contains("Expected"))
    }

    @MainActor
    func testExactApprovedRecurringPaymentOpensOneActualTransaction() throws {
        let app = englishApp()
        app.launch()
        guard app.staticTexts["Historical seed not imported"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires the isolated fictional exact-match fixture")
        }
        let paid = app.descendants(matching: .any)["homeRecurringPaidStatus"]
        for _ in 0..<6 where !paid.exists { app.swipeUp() }
        XCTAssertTrue(paid.waitForExistence(timeout: 5))
        paid.tap()
        XCTAssertTrue(app.navigationBars["Edit transaction"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Fictional Plan"].exists ||
                      app.textFields["transactionDescriptionField"].value as? String == "Fictional Plan")
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["Fictional Plan"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        let paidAfter = app.descendants(matching: .any)["homeRecurringPaidStatus"]
        for _ in 0..<6 where !paidAfter.exists { app.swipeUp() }
        XCTAssertTrue(paidAfter.waitForExistence(timeout: 5))
    }

    @MainActor
    func testSeparateHeldNotificationCreatesSecondPaymentOnlyAfterChoice() throws {
        let app = englishApp()
        app.launch()
        guard app.staticTexts["Historical seed not imported"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires the isolated fictional held-notification fixture")
        }
        app.tabBars.buttons["Automations"].tap()
        let source = app.staticTexts["Northstar Pay (fictional)"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        let review = app.buttons["reviewRecurringMatch"]
        for _ in 0..<8 where !review.isHittable { app.swipeUp() }
        XCTAssertTrue(review.isHittable)
        review.tap()
        let separate = app.buttons["Separate payment"]
        for _ in 0..<8 where !separate.isHittable { app.swipeUp() }
        XCTAssertTrue(separate.isHittable)
        separate.tap()
        app.buttons["Treat as separate payment"].tap()
        app.tabBars.buttons["Activity"].tap()
        let payments = app.staticTexts.matching(NSPredicate(format: "label == %@",
            "Fictional Plan"))
        XCTAssertEqual(payments.count, 2)
        app.terminate()
        app.launch()
        app.tabBars.buttons["Activity"].tap()
        XCTAssertEqual(payments.count, 2)
    }

    @MainActor
    func testTwoCandidatesKeepEarlyDateForExplicitReview() throws {
        let app = englishApp()
        app.launch()
        guard app.staticTexts["Historical seed not imported"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires the isolated fictional two-candidate fixture")
        }
        app.tabBars.buttons["Settings"].tap()
        app.buttons["settingsRecurringLink"].tap()
        XCTAssertTrue(app.staticTexts["Needs review · 2"].waitForExistence(timeout: 5))
        let early = app.buttons.matching(NSPredicate(format: "label CONTAINS %@",
            "2026-10-16")).firstMatch
        for _ in 0..<8 where !early.isHittable { app.swipeUp() }
        XCTAssertTrue(early.isHittable)
        early.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",
            "Payment date differs by 1 day")).firstMatch.waitForExistence(timeout: 5))
        let confirm = app.buttons["Confirm payment"]
        for _ in 0..<8 where !confirm.isHittable { app.swipeUp() }
        confirm.tap()
        app.buttons["Confirm this payment"].tap()
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["homeRecurringPaidStatus"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["Fictional Plan"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["Fictional Plan"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testManualCancelDoesNotCreateTransaction() throws {
        let app = englishApp()
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
        let app = englishApp()
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
    func testManagedAppearanceAndCategoryOrderSynthetic() throws {
        let app = englishApp()
        let suffix = String(UUID().uuidString.prefix(8))
        let accountName = "Fictional Color Wallet \(suffix)"
        let categoryName = "Fictional Color Category \(suffix)"
        app.launch()
        try requireSyntheticHistory(app)

        app.buttons["settingsAccountsLink"].tap()
        app.buttons["addAccountButton"].tap()
        let accountIcon = app.buttons["accountIconPicker"]
        XCTAssertTrue(accountIcon.waitForExistence(timeout: 5), app.debugDescription)
        accountIcon.tap()
        let banknote = app.buttons["Banknote"]
        XCTAssertTrue(banknote.waitForExistence(timeout: 5), app.debugDescription)
        banknote.tap()
        let accountColor = app.buttons["accountColorPicker"]
        accountColor.tap()
        let purple = app.buttons["Purple"]
        XCTAssertTrue(purple.waitForExistence(timeout: 5), app.debugDescription)
        purple.tap()
        let accountNameField = app.textFields["accountNameField"]
        accountNameField.tap()
        accountNameField.typeText(accountName)
        app.buttons["saveAccountButton"].tap()
        let accountRow = app.buttons["accountRow-\(accountName)"]
        for _ in 0..<12 where !accountRow.exists { app.swipeUp() }
        XCTAssertTrue(accountRow.waitForExistence(timeout: 5))
        XCTAssertEqual(accountRow.label, accountName)
        accountRow.tap()
        XCTAssertEqual(app.buttons["accountIconPicker"].value as? String, "Banknote")
        XCTAssertEqual(app.buttons["accountColorPicker"].value as? String, "Purple")
        app.buttons["Cancel"].tap()
        app.navigationBars.buttons["Settings"].tap()

        app.buttons["settingsCategoriesLink"].tap()
        app.buttons["addCategoryButton"].tap()
        let categoryIcon = app.buttons["categoryIconPicker"]
        categoryIcon.tap()
        let gift = app.buttons["Gift"]
        XCTAssertTrue(gift.waitForExistence(timeout: 5), app.debugDescription)
        gift.tap()
        let categoryColor = app.buttons["categoryColorPicker"]
        categoryColor.tap()
        let orange = app.buttons["Orange"]
        XCTAssertTrue(orange.waitForExistence(timeout: 5), app.debugDescription)
        orange.tap()
        let categoryNameField = app.textFields["categoryNameField"]
        categoryNameField.tap()
        categoryNameField.typeText(categoryName)
        app.buttons["saveCategoryButton"].tap()
        let categoryRow = app.buttons["categoryRow-\(categoryName)"]
        for _ in 0..<12 where !categoryRow.exists { app.swipeUp() }
        XCTAssertTrue(categoryRow.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(categoryRow.label, categoryName)
        let earlier = app.buttons["Move \(categoryName) earlier"]
        XCTAssertTrue(earlier.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(earlier.isEnabled)
        earlier.tap()
        categoryRow.tap()
        XCTAssertEqual(app.buttons["categoryIconPicker"].value as? String, "Gift")
        XCTAssertEqual(app.buttons["categoryColorPicker"].value as? String, "Orange")
        app.buttons["Cancel"].tap()

        app.terminate()
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        app.buttons["settingsAccountsLink"].tap()
        for _ in 0..<12 where !accountRow.exists { app.swipeUp() }
        accountRow.tap()
        XCTAssertEqual(app.buttons["accountIconPicker"].value as? String, "Banknote")
        XCTAssertEqual(app.buttons["accountColorPicker"].value as? String, "Purple")
        app.buttons["Cancel"].tap()
        app.navigationBars.buttons["Settings"].tap()
        app.buttons["settingsCategoriesLink"].tap()
        for _ in 0..<12 where !categoryRow.exists { app.swipeUp() }
        categoryRow.tap()
        XCTAssertEqual(app.buttons["categoryIconPicker"].value as? String, "Gift")
        XCTAssertEqual(app.buttons["categoryColorPicker"].value as? String, "Orange")
    }

    @MainActor
    func testManagedAccessibilityAtLargeTextSynthetic() throws {
        let app = englishApp()
        app.launch()
        try requireSyntheticHistory(app)
        let accountsLink = app.buttons["settingsAccountsLink"]
        XCTAssertEqual(accountsLink.elementType, .button)
        XCTAssertTrue(accountsLink.label.contains("Accounts"))
        accountsLink.tap()
        attach(app, name: "large-type-accounts")
        let addAccount = app.buttons["addAccountButton"]
        XCTAssertEqual(addAccount.label, "Add account")
        XCTAssertTrue(addAccount.isEnabled)
        addAccount.tap()
        let accountIcon = app.buttons["accountIconPicker"]
        let accountColor = app.buttons["accountColorPicker"]
        XCTAssertEqual(accountIcon.elementType, .button)
        XCTAssertEqual(accountIcon.label, "Icon")
        XCTAssertEqual(accountIcon.value as? String, "Creditcard")
        XCTAssertEqual(accountColor.elementType, .button)
        XCTAssertEqual(accountColor.label, "Color")
        XCTAssertEqual(accountColor.value as? String, "Teal")
        XCTAssertEqual(app.textFields["accountNameField"].elementType, .textField)
        XCTAssertEqual(app.buttons["saveAccountButton"].label, "Save")
        attach(app, name: "large-type-account-editor")
        app.buttons["Cancel"].tap()
        app.navigationBars.buttons["Settings"].tap()

        let categoriesLink = app.buttons["settingsCategoriesLink"]
        XCTAssertEqual(categoriesLink.elementType, .button)
        XCTAssertTrue(categoriesLink.label.contains("Categories"))
        categoriesLink.tap()
        attach(app, name: "large-type-categories")
        let groceries = app.buttons["categoryRow-Groceries"]
        XCTAssertTrue(groceries.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(groceries.elementType, .button)
        XCTAssertEqual(groceries.label, "Groceries")
        let earlier = app.buttons["Move Groceries earlier"]
        let later = app.buttons["Move Groceries later"]
        XCTAssertEqual(earlier.elementType, .button)
        XCTAssertFalse(earlier.isEnabled)
        XCTAssertEqual(later.elementType, .button)
        XCTAssertTrue(later.isEnabled)
        groceries.tap()
        XCTAssertEqual(app.buttons["categoryIconPicker"].value as? String, "Cart")
        XCTAssertEqual(app.buttons["categoryColorPicker"].value as? String, "Green")
        attach(app, name: "large-type-category-editor")
        app.buttons["Cancel"].tap()

        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.staticTexts["homePersonalSpendingTotal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["homeAddTransactionButton"].isEnabled)
        attach(app, name: "large-type-home")
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.textFields["transactionSearchField"].waitForExistence(timeout: 5))
        let transaction = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "Expense", "€")).firstMatch
        XCTAssertTrue(transaction.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(transaction.elementType, .button)
        XCTAssertTrue(transaction.isEnabled)
        attach(app, name: "large-type-activity")
    }

    @MainActor
    private func requireSyntheticHistory(_ app: XCUIApplication) throws {
        app.tabBars.buttons["Settings"].tap()
        let marker = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1 historical movements imported")).firstMatch
        for _ in 0..<10 where !marker.exists { app.swipeUp() }
        guard marker.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires the synthetic one-row simulator database")
        }
        let accounts = app.buttons["settingsAccountsLink"]
        for _ in 0..<10 where !accounts.isHittable { app.swipeDown() }
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
    private func selectSyntheticSeed(in app: XCUIApplication, token: String = "synthetic_seed") {
        app.tabBars.buttons["Settings"].tap()
        let choose = app.buttons["Choose SQLite seed"]
        for _ in 0..<6 where !choose.isHittable { app.swipeDown() }
        choose.tap()
        let seed = app.cells.matching(NSPredicate(format: "identifier CONTAINS[c] %@", token)).firstMatch
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
    private func ensureFictionalExportTransaction(in app: XCUIApplication) throws {
        app.tabBars.buttons["Activity"].tap()
        let existing = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Fictional Export Purchase")).firstMatch
        if existing.waitForExistence(timeout: 3) { return }

        let suffix = String(UUID().uuidString.prefix(8))
        let accountName = "Fictional Export Wallet \(suffix)"
        let description = "Fictional Export Purchase \(suffix)"
        app.tabBars.buttons["Settings"].tap()
        app.buttons["settingsAccountsLink"].tap()
        app.buttons["addAccountButton"].tap()
        let field = app.textFields["accountNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(accountName)
        app.buttons["saveAccountButton"].tap()
        app.navigationBars.buttons["Settings"].tap()
        app.tabBars.buttons["Home"].tap()
        app.buttons["homeAddTransactionButton"].tap()
        replaceText(in: app.textFields["transactionAmountField"], with: "12,34")
        replaceText(in: app.textFields["transactionDescriptionField"], with: description)
        let picker = app.buttons["transactionAccountPicker"]
        for _ in 0..<4 where !picker.isHittable { app.swipeUp() }
        picker.tap()
        XCTAssertTrue(app.navigationBars["Choose account"].waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<8 where !app.buttons[accountName].exists { app.swipeUp() }
        app.buttons[accountName].tap()
        app.buttons["Save"].tap()
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts[description].waitForExistence(timeout: 5), app.debugDescription)
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
