import Foundation
import SQLite3
import XCTest
@testable import EasyTrackCore

final class CategorySuggestionTests: XCTestCase {
    private func category(_ name: String, _ index: Int, archived: Bool = false) -> LedgerCategory {
        LedgerCategory(id: UUID(), name: name, symbolName: "square.grid.2x2.fill",
            colorName: "teal", sortIndex: index, createdAt: .now, updatedAt: .now,
            archivedAt: archived ? .now : nil, revision: 1)
    }

    private func rule(_ pattern: String, categoryID: UUID, enabled: Bool = true,
                      id: UUID = UUID()) -> CategoryKeywordRule {
        CategoryKeywordRule(id: id, pattern: pattern, categoryID: categoryID,
            isEnabled: enabled, createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100), revision: 0)
    }

    func testWholeWordsUnicodePunctuationAndBuiltInExplanation() {
        let food = category("Eating Out", 0)
        let transport = category("Transport", 1)
        let categories = [food, transport]
        let accent = CategorySuggestionEngine.suggestions(description: "Caffè Roma — pranzo!",
            kind: .expense, categories: categories, userRules: [], isEnabled: true)
        XCTAssertEqual(accent.first?.categoryID, food.id)
        XCTAssertEqual(accent.first?.matchedText, "caffe")

        XCTAssertTrue(CategorySuggestionEngine.suggestions(description: "Noleggio barca",
            kind: .expense, categories: categories,
            userRules: [rule("bar", categoryID: food.id)], isEnabled: true).isEmpty)
        XCTAssertEqual(CategorySuggestionEngine.suggestions(description: "Taxi, aeroporto.",
            kind: .expense, categories: categories, userRules: [], isEnabled: true).first?.categoryID,
            transport.id)
    }

    func testUserPriorityAlternativesAmbiguityAndMaximumThree() {
        let categories = [category("Groceries", 0), category("Eating Out", 1),
                          category("Transport", 2), category("Travel", 3)]
        let rules = [
            rule("supermercato verde", categoryID: categories[3].id),
            rule("supermercato", categoryID: categories[1].id),
            rule("supermercato", categoryID: categories[2].id)
        ]
        let suggestions = CategorySuggestionEngine.suggestions(
            description: "Pagamento SUPERMERCATO VERDE, Milano", kind: .expense,
            categories: categories, userRules: rules, isEnabled: true)
        XCTAssertEqual(suggestions.count, 3)
        XCTAssertEqual(suggestions.map(\.source), [.userRule, .userRule, .userRule])
        XCTAssertEqual(suggestions.first?.categoryID, categories[3].id)
        XCTAssertEqual(suggestions.first?.matchedText, "supermercato verde")
    }

    func testDisabledArchivedRenamedMissingAndIncompatibleKindsAreSafe() {
        var renamed = category("Renamed category", 0)
        let archived = category("Health", 1, archived: true)
        let missing = UUID()
        let rules = [rule("specific shop", categoryID: renamed.id),
                     rule("specific shop", categoryID: archived.id),
                     rule("specific shop", categoryID: missing),
                     rule("specific shop", categoryID: renamed.id, enabled: false)]
        var suggestions = CategorySuggestionEngine.suggestions(description: "Specific Shop receipt",
            kind: .expense, categories: [renamed, archived], userRules: rules, isEnabled: true)
        XCTAssertEqual(suggestions.map(\.categoryName), ["Renamed category"])
        renamed.name = "Renamed again"
        suggestions = CategorySuggestionEngine.suggestions(description: "specific shop",
            kind: .expense, categories: [renamed, archived], userRules: rules, isEnabled: true)
        XCTAssertEqual(suggestions.first?.categoryName, "Renamed again")
        XCTAssertTrue(CategorySuggestionEngine.suggestions(description: "specific shop",
            kind: .income, categories: [renamed], userRules: rules, isEnabled: true).isEmpty)
        XCTAssertTrue(CategorySuggestionEngine.suggestions(description: "specific shop",
            kind: .reimbursement, categories: [renamed], userRules: rules, isEnabled: true).isEmpty)
        XCTAssertTrue(CategorySuggestionEngine.suggestions(description: "specific shop",
            kind: .expense, categories: [renamed], userRules: rules, isEnabled: false).isEmpty)
    }

    func testVisualIconFallbackNeverChangesClassification() {
        XCTAssertEqual(MovementIconResolver.fallback(description: "Farmácia Centrale", kind: .expense),
                       MovementIconAppearance(symbolName: "cross.case.fill", colorName: "red"))
        XCTAssertEqual(MovementIconResolver.fallback(description: "Barca Marina", kind: .expense),
                       MovementIconAppearance(symbolName: "creditcard.fill", colorName: "teal"))
        XCTAssertEqual(MovementIconResolver.fallback(description: "Monthly salary", kind: .income),
                       MovementIconAppearance(symbolName: "banknote.fill", colorName: "green"))
    }

    func testPersistenceMigrationManualUndoAndFinancialHistoryRemainUnchanged() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyTrack-category-rules-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("ledger.sqlite")
        let database = try SQLiteDatabase(url: url)
        try database.seedDemoIfNeeded()
        let category = try XCTUnwrap(database.ledgerCategories().first { $0.archivedAt == nil })
        let saved = try database.saveCategoryKeywordRule(rule("fictional merchant", categoryID: category.id))
        try database.setCategorySuggestionsEnabled(false)
        let transactionsBefore = try database.transactions()
        let totalsBefore = LedgerTotals(transactions: transactionsBefore)
        let reimbursementsBefore = try database.reimbursementStatuses()

        let reopened = try SQLiteDatabase(url: url)
        XCTAssertFalse(try reopened.categorySuggestionsEnabled())
        XCTAssertEqual(try reopened.categoryKeywordRules().first?.id, saved.id)
        var disabled = try XCTUnwrap(reopened.categoryKeywordRules().first)
        disabled.isEnabled = false
        _ = try reopened.saveCategoryKeywordRule(disabled)
        XCTAssertFalse(try XCTUnwrap(reopened.categoryKeywordRules().first).isEnabled)

        var movement = try XCTUnwrap(reopened.transactions().first)
        let original = movement
        movement.categoryID = category.id
        movement.category = category.name
        movement = try reopened.save(movement)
        movement.categoryID = original.categoryID
        movement.category = original.category
        _ = try reopened.save(movement)
        XCTAssertEqual(try reopened.transactions().map(\.id), transactionsBefore.map(\.id))
        XCTAssertEqual(LedgerTotals(transactions: try reopened.transactions()), totalsBefore)
        XCTAssertEqual(try reopened.reimbursementStatuses(), reimbursementsBefore)

        try reopened.deleteCategoryKeywordRule(saved.id)
        XCTAssertTrue(try reopened.categoryKeywordRules().isEmpty)
        try reopened.execute("DROP TABLE category_keyword_rules")
        try reopened.execute("DROP TABLE category_suggestion_settings")
        try reopened.execute("PRAGMA user_version=9")
        let migrated = try SQLiteDatabase(url: url)
        XCTAssertTrue(try migrated.categorySuggestionsEnabled())
        XCTAssertTrue(try migrated.categoryKeywordRules().isEmpty)
    }

    func testBackupReplaceMergeConflictOldFormatAndRepeatRestore() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyTrack-category-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try SQLiteDatabase(url: folder.appendingPathComponent("source.sqlite"))
        let target = try SQLiteDatabase(url: folder.appendingPathComponent("target.sqlite"))
        try source.seedDemoIfNeeded(); try target.seedDemoIfNeeded()
        let category = try XCTUnwrap(source.ledgerCategories().first)
        let stableID = UUID()
        let sourceRule = try source.saveCategoryKeywordRule(rule("fictional cafe", categoryID: category.id,
                                                                 id: stableID))
        let backup = try source.exportBackup()
        XCTAssertEqual(backup.schemaVersion, 11)
        XCTAssertEqual(backup.databaseSchemaVersion, 10)
        _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .replace)
        let restoredRule = try XCTUnwrap(target.categoryKeywordRules().first)
        XCTAssertEqual(restoredRule.id, sourceRule.id)
        XCTAssertEqual(restoredRule.pattern, sourceRule.pattern)
        XCTAssertEqual(restoredRule.categoryID, sourceRule.categoryID)
        XCTAssertEqual(restoredRule.revision, sourceRule.revision)
        _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .merge)
        XCTAssertEqual(try target.categoryKeywordRules().count, 1)

        var conflicting = try XCTUnwrap(target.categoryKeywordRules().first)
        conflicting.pattern = "different local phrase"
        _ = try target.saveCategoryKeywordRule(conflicting)
        let before = try target.backupTables()
        let preview = try target.previewBackup(backup)
        XCTAssertNotNil(preview.mergeConflict)
        XCTAssertThrowsError(try target.restoreBackup(backup, preview: preview, mode: .merge))
        XCTAssertEqual(try target.backupTables(), before)

        let oldTables = Array(backup.tables.prefix(29))
        let old = BackupArchive(schemaVersion: 10, databaseSchemaVersion: 9,
            exportID: UUID(), exportedAt: .now,
            contentSHA256: try SQLiteDatabase.digest(oldTables), tables: oldTables,
            sourceFormatVersion: nil)
        let upgraded = try BackupArchive.decode(JSONEncoder().encode(old))
        XCTAssertEqual(upgraded.schemaVersion, 11)
        XCTAssertEqual(upgraded.sourceFormatVersion, 10)
        XCTAssertEqual(upgraded.tables[29].rows.first?[1], "1")
        XCTAssertTrue(upgraded.tables[30].rows.isEmpty)
    }
}
