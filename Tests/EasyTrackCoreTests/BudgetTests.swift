import Foundation
import SQLite3
import XCTest
@testable import EasyTrackCore

final class BudgetTests: XCTestCase {
    private let zone = TimeZone(identifier: "Europe/Rome")!

    private func day(_ value: String) -> LocalDay { LocalDay(isoString: value)! }
    private func date(_ value: String) -> Date { day(value).noon(in: zone)! }

    private func category(_ name: String, index: Int, archived: Bool = false) -> LedgerCategory {
        LedgerCategory(id: UUID(), name: name, symbolName: "square.grid.2x2.fill",
            colorName: "teal", sortIndex: index, createdAt: .now, updatedAt: .now,
            archivedAt: archived ? .now : nil, revision: 0)
    }

    private func transaction(_ id: Int, kind: TransactionKind = .expense, amount: Int64,
                             personal: Int64?, day: String, category: LedgerCategory? = nil,
                             currency: String = "EUR") -> Transaction {
        var item = Transaction(id: UUID(uuidString: String(format: "00000000-0000-4007-8000-%012d", id))!,
            kind: kind, amountMinor: amount, currency: currency, merchant: "Fictional budget \(id)",
            account: "Fictional account", category: category?.name ?? "", note: "",
            occurredAt: date(day), updatedAt: date(day), deletedAt: nil, isDemo: false,
            revision: 1, sourceEventID: nil)
        item.eurMinor = currency == "EUR" ? amount : nil
        item.personalExpenseEURMinor = personal
        item.categoryID = category?.id
        return item
    }

    private func budget(scope: MonthlyBudgetScope, limit: Int64,
                        categoryID: UUID? = nil, archived: Bool = false) -> MonthlyBudget {
        MonthlyBudget(id: UUID(), scope: scope, categoryID: categoryID,
            limitEURMinor: limit, createdAt: .now, updatedAt: .now,
            archivedAt: archived ? .now : nil, revision: 0)
    }

    func testOverallCategoryUncategorizedNegativeAndMissingFXUseExistingNetSnapshot() throws {
        let food = category("Food renamed", index: 0)
        let rows = [
            transaction(1, amount: 10_000, personal: 2_000, day: "2026-10-02", category: food),
            transaction(2, amount: 5_000, personal: 5_000, day: "2026-10-03", category: food),
            transaction(3, amount: 4_000, personal: 4_000, day: "2026-10-04", category: food),
            transaction(4, kind: .reimbursement, amount: 1_000, personal: -1_000,
                        day: "2026-10-05", category: food),
            transaction(5, amount: 2_000, personal: 2_000, day: "2026-10-06"),
            transaction(6, amount: 9_000, personal: nil, day: "2026-10-07", currency: "USD")
        ]
        let financial = try FinancialAnalytics.snapshot(transactions: rows,
            period: .month(year: 2026, month: 10), timeZone: zone, now: date("2026-10-20"))
        let overall = budget(scope: .overall, limit: 15_000)
        let foodBudget = budget(scope: .category, limit: 9_000, categoryID: food.id)
        let snapshot = try BudgetAnalytics.snapshot(financial: financial,
            budgets: [overall, foodBudget], categories: [food])
        XCTAssertEqual(snapshot.overall?.spentEURMinor, 12_000)
        XCTAssertEqual(snapshot.overall?.remainingEURMinor, 3_000)
        XCTAssertEqual(snapshot.categories.first?.spentEURMinor, 10_000)
        XCTAssertEqual(snapshot.categories.first?.remainingEURMinor, -1_000)
        XCTAssertTrue(snapshot.categories.first?.isOverLimit == true)
        XCTAssertEqual(snapshot.missingConversionCount, 1)
    }

    func testNoRolloverNoProrationAndEmptyMonth() throws {
        let monthly = budget(scope: .overall, limit: 10_000)
        let january = try FinancialAnalytics.snapshot(
            transactions: [transaction(10, amount: 3_000, personal: 3_000, day: "2026-01-10")],
            period: .month(year: 2026, month: 1), timeZone: zone, now: date("2026-03-01"))
        let february = try FinancialAnalytics.snapshot(transactions: [],
            period: .month(year: 2026, month: 2), timeZone: zone, now: date("2026-03-01"))
        let first = try BudgetAnalytics.snapshot(financial: january, budgets: [monthly], categories: [])
        let second = try BudgetAnalytics.snapshot(financial: february, budgets: [monthly], categories: [])
        XCTAssertEqual(first.overall?.remainingEURMinor, 7_000)
        XCTAssertEqual(second.overall?.remainingEURMinor, 10_000)
        XCTAssertEqual(try february.period.effective.dayCount(timeZone: zone), 28)
    }

    func testArchivedCategoryAndReimbursementWriteOffStayOnOriginalMonth() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyTrack-budget-writeoff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try SQLiteDatabase(url: folder.appendingPathComponent("ledger.sqlite"))
        let archived = try database.saveLedgerCategory(category("Archived travel", index: 0, archived: true))
        var expense = transaction(20, amount: 5_000, personal: 5_000,
                                  day: "2026-09-15", category: archived)
        expense = try database.save(expense, expectedReimbursementEURMinor: 5_000)
        try database.writeOffOutstandingReimbursement(expense.id)
        let financial = try FinancialAnalytics.snapshot(transactions: try database.transactions(),
            period: .month(year: 2026, month: 9), timeZone: zone, now: date("2026-10-10"))
        let limit = budget(scope: .category, limit: 4_000, categoryID: archived.id)
        let snapshot = try BudgetAnalytics.snapshot(financial: financial,
            budgets: [limit], categories: [archived])
        XCTAssertEqual(snapshot.categories.first?.title, "Archived travel")
        XCTAssertEqual(snapshot.categories.first?.spentEURMinor, 5_000)
        XCTAssertEqual(snapshot.categories.first?.remainingEURMinor, -1_000)
        XCTAssertEqual(try database.transactions().count, 1)
    }

    func testBudgetGoalPersistenceEditArchiveAndManualProgressDoNotChangeLedger() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyTrack-budget-persistence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("ledger.sqlite")
        let database = try SQLiteDatabase(url: url)
        try database.seedDemoIfNeeded()
        let ledgerBefore = try database.transactions()
        var savedBudget = try database.saveMonthlyBudget(budget(scope: .overall, limit: 50_000))
        savedBudget.limitEURMinor = 60_000
        savedBudget = try database.saveMonthlyBudget(savedBudget)
        let now = Date()
        var goal = try database.saveSavingsGoal(SavingsGoal(id: UUID(), name: "Fictional reserve",
            targetEURMinor: 100_000, progressEURMinor: 12_500, dueDate: day("2027-06-30"),
            createdAt: now, updatedAt: now, archivedAt: nil, revision: 0))
        goal.progressEURMinor = 20_000
        goal = try database.saveSavingsGoal(goal)
        XCTAssertEqual(goal.progressEURMinor, 20_000)
        goal.archivedAt = .now
        _ = try database.saveSavingsGoal(goal)
        savedBudget.archivedAt = .now
        _ = try database.saveMonthlyBudget(savedBudget)

        let reopened = try SQLiteDatabase(url: url)
        XCTAssertEqual(try reopened.monthlyBudgets().first?.limitEURMinor, 60_000)
        XCTAssertNotNil(try reopened.monthlyBudgets().first?.archivedAt)
        XCTAssertEqual(try reopened.savingsGoals().first?.progressEURMinor, 20_000)
        XCTAssertNotNil(try reopened.savingsGoals().first?.archivedAt)
        XCTAssertEqual(try reopened.transactions(), ledgerBefore)
    }

    func testBackupReplaceMergeConflictOldFormatRepeatAndMigration() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyTrack-budget-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try SQLiteDatabase(url: folder.appendingPathComponent("source.sqlite"))
        let target = try SQLiteDatabase(url: folder.appendingPathComponent("target.sqlite"))
        try source.seedDemoIfNeeded(); try target.seedDemoIfNeeded()
        let sourceBudget = try source.saveMonthlyBudget(budget(scope: .overall, limit: 25_000))
        let now = Date(timeIntervalSince1970: 100)
        let sourceGoal = try source.saveSavingsGoal(SavingsGoal(id: UUID(), name: "Fictional goal",
            targetEURMinor: 80_000, progressEURMinor: 10_000, dueDate: nil,
            createdAt: now, updatedAt: now, archivedAt: nil, revision: 0))
        let backup = try source.exportBackup()
        XCTAssertEqual(backup.schemaVersion, 15)
        XCTAssertEqual(backup.databaseSchemaVersion, 13)
        _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .replace)
        XCTAssertEqual(try target.monthlyBudgets().first?.id, sourceBudget.id)
        XCTAssertEqual(try target.savingsGoals().first?.id, sourceGoal.id)
        _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .merge)
        XCTAssertEqual(try target.monthlyBudgets().count, 1)

        var local = try XCTUnwrap(target.monthlyBudgets().first)
        local.limitEURMinor = 30_000
        _ = try target.saveMonthlyBudget(local)
        let before = try target.backupTables()
        let preview = try target.previewBackup(backup)
        XCTAssertNotNil(preview.mergeConflict)
        XCTAssertThrowsError(try target.restoreBackup(backup, preview: preview, mode: .merge))
        XCTAssertEqual(try target.backupTables(), before)

        let oldTables = Array(BackupArchive.schemaElevenShape(backup.tables).prefix(31))
        let old = BackupArchive(schemaVersion: 11, databaseSchemaVersion: 10,
            exportID: UUID(), exportedAt: .now,
            contentSHA256: try SQLiteDatabase.digest(oldTables), tables: oldTables,
            sourceFormatVersion: nil)
        let upgraded = try BackupArchive.decode(JSONEncoder().encode(old))
        XCTAssertEqual(upgraded.schemaVersion, 15)
        XCTAssertEqual(upgraded.sourceFormatVersion, 11)
        XCTAssertTrue(upgraded.tables[31].rows.isEmpty)
        XCTAssertTrue(upgraded.tables[32].rows.isEmpty)

        let migrationURL = folder.appendingPathComponent("migration.sqlite")
        let migration = try SQLiteDatabase(url: migrationURL)
        try migration.execute("DROP TABLE savings_goals")
        try migration.execute("DROP TABLE monthly_budgets")
        try migration.execute("PRAGMA user_version=10")
        let migrated = try SQLiteDatabase(url: migrationURL)
        XCTAssertTrue(try migrated.monthlyBudgets().isEmpty)
        XCTAssertTrue(try migrated.savingsGoals().isEmpty)
    }
}
