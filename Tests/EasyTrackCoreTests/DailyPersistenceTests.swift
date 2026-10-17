import SQLite3
import XCTest
@testable import EasyTrackCore

final class DailyPersistenceTests: XCTestCase {
    private let zone = TimeZone(identifier: "Europe/Rome")!

    private func withDatabase(_ body: (URL, SQLiteDatabase) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-daily-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("local.sqlite")
        try body(url, SQLiteDatabase(url: url))
    }

    private func account(_ database: SQLiteDatabase, name: String = "Fictional Checking") throws -> LocalAccount {
        try database.saveLocalAccount(LocalAccount(id: UUID(), name: name, createdAt: .now))
    }

    private func category(_ database: SQLiteDatabase, name: String = "Fictional category") throws -> LedgerCategory {
        try database.saveLedgerCategory(LedgerCategory(id: UUID(), name: name,
            symbolName: "cart.fill", colorName: "green", sortIndex: 30,
            createdAt: .now, updatedAt: .now, archivedAt: nil, revision: 0))
    }

    private func rule(account: LocalAccount, start: String = "2026-01-31",
                      type: RecurringType = .subscription,
                      frequency: RecurringFrequency = .monthly) -> RecurringRule {
        RecurringRule(id: UUID(), name: "Fictional monthly plan", type: type,
                      amountMinor: 1_250, accountID: account.id, categoryID: nil,
                      startDay: LocalDay(isoString: start)!, frequency: frequency,
                      nextIndex: 0, endDay: nil, timeZoneIdentifier: zone.identifier,
                      isActive: true, note: "Synthetic recurring rule",
                      createdAt: .now, updatedAt: .now, archivedAt: nil, revision: 0)
    }

    private func date(_ day: String) -> Date { LocalDay(isoString: day)!.noon(in: zone)! }

    private func sql(_ text: String, url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw NSError(domain: "sqlite", code: 1) }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, text, nil, nil, nil) == SQLITE_OK else { throw NSError(domain: "sqlite", code: 2) }
    }

    private func scalar(_ text: String, url: URL) throws -> Int {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw NSError(domain: "sqlite", code: 3) }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, text, -1, &stmt, nil) == SQLITE_OK else { throw NSError(domain: "sqlite", code: 4) }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw NSError(domain: "sqlite", code: 5) }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    func testAccountsAndCategoriesKeepStableReferencesThroughRenameAndArchive() throws {
        try withDatabase { url, database in
            XCTAssertEqual(try scalar("PRAGMA user_version", url: url), 6)
            XCTAssertEqual(try database.ledgerCategories().count, 12)
            var account = try self.account(database)
            var category = try self.category(database)
            var first = Transaction(id: UUID(), kind: .expense, amountMinor: 1_234,
                                    currency: "EUR", merchant: "Fictional purchase",
                                    account: account.name, category: category.name, note: "",
                                    occurredAt: self.date("2026-02-01"), updatedAt: .now,
                                    deletedAt: nil, isDemo: false, revision: 0, sourceEventID: nil)
            first.accountID = account.id
            first.categoryID = category.id
            try database.save(first)
            var second = first
            second.id = UUID()
            second.merchant = "Another fictional purchase"
            second.category = ""
            second.categoryID = nil
            try database.save(second)
            XCTAssertEqual(try scalar("SELECT COUNT(*) FROM transactions WHERE category IS NULL", url: url), 1)

            account.name = "Renamed Checking"
            account.symbolName = "banknote.fill"
            account.colorName = "blue"
            account = try database.saveLocalAccount(account)
            XCTAssertEqual(account.revision, 2)
            XCTAssertEqual(try database.transactions().first { $0.id == first.id }?.accountID, account.id)
            XCTAssertEqual(try database.transactions().first { $0.id == first.id }?.account, "Fictional Checking")
            category.name = "Renamed category"
            category = try database.saveLedgerCategory(category)
            XCTAssertEqual(try database.transactions().first { $0.id == first.id }?.categoryID, category.id)
            XCTAssertEqual(try scalar("SELECT COUNT(*) FROM transactions WHERE category IS NULL", url: url), 1)
            category.archivedAt = .now
            _ = try database.saveLedgerCategory(category)
            account.archivedAt = .now
            account = try database.saveLocalAccount(account)
            XCTAssertNotNil(account.archivedAt)
            XCTAssertEqual(try database.transactions().count, 2)
            XCTAssertThrowsError(try database.saveLocalAccount(LocalAccount(id: UUID(),
                name: "Renamed Checking", createdAt: .now)))
            account.archivedAt = nil
            let restored = try database.saveLocalAccount(account)
            XCTAssertNil(restored.archivedAt)
            XCTAssertEqual(restored.id, first.accountID)
        }
    }

    func testMonthlyCatchUpIsAtomicIdempotentAndSurvivesReopen() throws {
        try withDatabase { url, database in
            let account = try self.account(database)
            let plan = try database.saveRecurringRule(self.rule(account: account))
            XCTAssertEqual(try database.transactions().count, 0)
            XCTAssertEqual(try database.materializeDueRecurring(now: self.date("2026-03-15")), 2)
            XCTAssertEqual(try database.recurringOccurrences(ruleID: plan.id).map(\.scheduledDay.isoString).sorted(),
                           ["2026-01-31", "2026-02-28"])
            XCTAssertEqual(try database.transactions().count, 0)
            XCTAssertTrue(try database.recurringOccurrences(ruleID: plan.id).allSatisfy { $0.status == .expected })
            XCTAssertEqual(try database.materializeDueRecurring(now: self.date("2026-03-15")), 0)
            let reopened = try SQLiteDatabase(url: url)
            XCTAssertEqual(try reopened.materializeDueRecurring(now: self.date("2026-03-15")), 0)
            XCTAssertEqual(try reopened.recurringRules().first?.nextIndex, 2)
            XCTAssertEqual(try reopened.transactions().count, 0)
            XCTAssertEqual(try scalar("SELECT COUNT(DISTINCT recurring_occurrence_id) FROM transactions", url: url), 0)
            XCTAssertEqual(try LedgerTotals(transactions: reopened.transactions()).pacInvestedEURMinor, 0)
        }
    }

    func testPACIsSeparateFromExpensesAndPauseSkipEditArchiveKeepHistory() throws {
        try withDatabase { _, database in
            let account = try self.account(database)
            var plan = try database.saveRecurringRule(self.rule(account: account, start: "2026-06-01",
                                                               type: .pacInvestment))
            plan.isActive = false
            plan = try database.saveRecurringRule(plan)
            XCTAssertEqual(try database.materializeDueRecurring(now: self.date("2026-08-02")), 0)
            plan.isActive = true
            plan = try database.saveRecurringRule(plan)
            try database.skipNextRecurring(plan.id)
            XCTAssertEqual(try database.recurringOccurrences(ruleID: plan.id).first?.status, .skipped)
            XCTAssertEqual(try database.materializeDueRecurring(now: self.date("2026-08-02")), 2)
            let expected = try database.recurringOccurrences(ruleID: plan.id).filter { $0.status == .expected }
            XCTAssertEqual(expected.count, 2)
            XCTAssertEqual(try database.transactions().count, 0)
            let totals = LedgerTotals(transactions: try database.transactions())
            XCTAssertEqual(totals.totalExpensesEURMinor, 0)
            XCTAssertEqual(totals.pacInvestedEURMinor, 0)
            _ = try database.recordExpectedRecurringNow(expected[0].id, now: self.date("2026-08-03"))
            XCTAssertEqual(try LedgerTotals(transactions: database.transactions()).pacInvestedEURMinor, 1_250)
            plan = try XCTUnwrap(database.recurringRules().first)
            plan.amountMinor = 2_000
            plan = try database.saveRecurringRule(plan)
            XCTAssertEqual(try database.createNextRecurringNow(plan.id, now: self.date("2026-08-10")).amountMinor, 2_000)
            XCTAssertEqual(try database.transactions().filter { $0.amountMinor == 1_250 }.count, 1)
            plan = try XCTUnwrap(database.recurringRules().first)
            plan.archivedAt = .now
            _ = try database.saveRecurringRule(plan)
            XCTAssertTrue(try database.recurringRules().isEmpty)
            XCTAssertEqual(try database.transactions().count, 2)
        }
    }

    func testForcedRecurringInsertFailureRollsBackOccurrenceAndCursor() throws {
        try withDatabase { url, database in
            let account = try self.account(database)
            let plan = try database.saveRecurringRule(self.rule(account: account, start: "2026-01-31"))
            let beforeOperations = try database.operations().count
            try self.sql("CREATE TRIGGER synthetic_recurring_failure BEFORE INSERT ON recurring_occurrences_local BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END", url: url)
            XCTAssertThrowsError(try database.materializeDueRecurring(now: self.date("2026-02-01")))
            XCTAssertEqual(try database.transactions().count, 0)
            XCTAssertTrue(try database.recurringOccurrences(ruleID: plan.id).isEmpty)
            XCTAssertEqual(try database.recurringRules().first?.nextIndex, 0)
            XCTAssertEqual(try database.operations().count, beforeOperations)
            try self.sql("DROP TRIGGER synthetic_recurring_failure", url: url)
            XCTAssertEqual(try database.materializeDueRecurring(now: self.date("2026-02-01")), 1)
        }
    }

    func testSchemaFourUpgradePreservesExistingLedgerAndParserRows() throws {
        try withDatabase { url, database in
            let original = Transaction(id: UUID(), kind: .expense, amountMinor: 1_234,
                                       currency: "EUR", merchant: "Fictional legacy purchase",
                                       account: "Fictional legacy account", category: "", note: "",
                                       occurredAt: self.date("2026-02-01"), updatedAt: .now,
                                       deletedAt: nil, isDemo: false, revision: 0, sourceEventID: nil)
            try database.save(original)
            let event = try XCTUnwrap(NotificationEvent.make(sourceApp: "Fictional legacy source",
                title: "Purchase", subtitle: "", message: "12,34 EUR", receivedAt: self.date("2026-02-01")))
            XCTAssertEqual(try database.captureNotification(event).status, .setupRequired)
            for command in [
                "DROP TABLE recurring_reconciliation_audit",
                "DROP TABLE recurring_payee_aliases",
                "DROP TABLE recurring_candidates",
                "DROP TABLE recurring_occurrences_local",
                "DROP TABLE recurring_rules_local",
                "DROP TABLE ledger_categories",
                "DROP INDEX unique_transaction_recurring_occurrence",
                "ALTER TABLE transactions DROP COLUMN recurring_occurrence_id",
                "ALTER TABLE transactions DROP COLUMN category_id",
                "ALTER TABLE transactions DROP COLUMN account_id",
                "ALTER TABLE local_accounts DROP COLUMN symbol_name",
                "ALTER TABLE local_accounts DROP COLUMN color_name",
                "ALTER TABLE local_accounts DROP COLUMN updated_at",
                "ALTER TABLE local_accounts DROP COLUMN archived_at",
                "ALTER TABLE local_accounts DROP COLUMN revision",
                "PRAGMA user_version=4"
            ] { try self.sql(command, url: url) }
            XCTAssertEqual(try self.scalar("PRAGMA user_version", url: url), 4)
            let upgraded = try SQLiteDatabase(url: url)
            XCTAssertEqual(try self.scalar("PRAGMA user_version", url: url), 6)
            XCTAssertEqual(try upgraded.transactions().first?.id, original.id)
            XCTAssertEqual(try upgraded.transactions().first?.amountMinor, 1_234)
            XCTAssertEqual(try upgraded.notificationEvents().first?.id, event.id)
            XCTAssertEqual(try upgraded.ledgerCategories().count, 12)
            XCTAssertEqual(try self.scalar("SELECT COUNT(*) FROM pragma_foreign_key_check", url: url), 0)
        }
    }

    func testParserSourceMappingRetainsAccountIdentityThroughRenameAndArchive() throws {
        try withDatabase { _, database in
            var account = try self.account(database, name: "Fictional mapped checking")
            let event = try XCTUnwrap(NotificationEvent.make(sourceApp: "Fictional notification app",
                title: "Purchase", subtitle: "", message: "2,50 EUR", receivedAt: self.date("2026-02-01")))
            XCTAssertEqual(try database.captureNotification(event).status, .setupRequired)
            let sourceID = try XCTUnwrap(database.parserSources().first?.id)
            _ = try database.mapParserSource(sourceID, to: account.name)
            XCTAssertEqual(try database.parserSources().first?.accountID, account.id)
            account.name = "Fictional checking renamed"
            account = try database.saveLocalAccount(account)
            XCTAssertEqual(try database.parserSources().first?.accountID, account.id)
            XCTAssertEqual(try database.parserSources().first?.accountName, account.name)
            account.archivedAt = .now
            _ = try database.saveLocalAccount(account)
            XCTAssertEqual(try database.parserSources().first?.accountID, account.id)
        }
    }

    func testCategoryReorderPersistsAndKeepsStableIDs() throws {
        try withDatabase { url, database in
            let first = try self.category(database, name: "Fictional first category")
            var secondInput = LedgerCategory(id: UUID(), name: "Fictional second category",
                symbolName: "book.fill", colorName: "blue", sortIndex: 31,
                createdAt: .now, updatedAt: .now, archivedAt: nil, revision: 0)
            secondInput = try database.saveLedgerCategory(secondInput)
            let beforeOperations = try database.operations().count
            try database.swapCategoryOrder(first, secondInput)
            let reopened = try SQLiteDatabase(url: url)
            let categories = try reopened.ledgerCategories()
            XCTAssertEqual(categories.first { $0.id == first.id }?.sortIndex, 31)
            XCTAssertEqual(categories.first { $0.id == secondInput.id }?.sortIndex, 30)
            XCTAssertEqual(categories.first { $0.id == first.id }?.revision, first.revision + 1)
            XCTAssertEqual(try reopened.operations().count, beforeOperations + 2)
        }
    }
}
