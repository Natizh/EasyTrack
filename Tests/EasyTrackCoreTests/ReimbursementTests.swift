import Foundation
import SQLite3
import XCTest
@testable import EasyTrackCore

final class ReimbursementTests: XCTestCase {
    private let zone = TimeZone(identifier: "Europe/Rome")!

    private func withDatabase(_ body: (SQLiteDatabase, URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyTrack-reimbursement-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("ledger.sqlite")
        try body(SQLiteDatabase(url: url), url)
    }

    private func date(_ day: String) -> Date {
        LocalDay(isoString: day)!.noon(in: zone)!
    }

    private func transaction(kind: TransactionKind, cents: Int64, day: String,
                             accountID: UUID, merchant: String) -> Transaction {
        var item = Transaction(id: UUID(), kind: kind, amountMinor: cents, currency: "EUR",
            merchant: merchant, account: "Fictional \(accountID.uuidString)", category: "Travel", note: "",
            occurredAt: date(day), updatedAt: date(day), deletedAt: nil, isDemo: false,
            revision: 0, sourceEventID: nil)
        item.eurMinor = cents
        item.personalExpenseEURMinor = kind == .expense ? cents : (kind == .reimbursement ? -cents : 0)
        item.recoverableEURMinor = 0
        return item
    }

    func testNormalAndFullyExpectedExpenseKeepGrossCashAndNetDistinct() throws {
        try withDatabase { database, _ in
            let account = UUID()
            let normal = try database.save(transaction(kind: .expense, cents: 5_000,
                day: "2026-10-01", accountID: account, merchant: "Fictional normal"))
            XCTAssertEqual(LedgerTotals(transactions: try database.transactions()).personalSpendingEURMinor, 5_000)
            XCTAssertTrue(try database.reimbursementStatuses().isEmpty)

            let expected = try database.save(transaction(kind: .expense, cents: 5_000,
                day: "2026-10-02", accountID: account, merchant: "Fictional reimbursable"),
                expectedReimbursementEURMinor: 5_000)
            let totals = LedgerTotals(transactions: try database.transactions())
            XCTAssertEqual(totals.totalExpensesEURMinor, 10_000)
            XCTAssertEqual(totals.personalSpendingEURMinor, 5_000)
            XCTAssertEqual(try database.transactions().first { $0.id == expected.id }?.recoverableEURMinor, 5_000)
            XCTAssertEqual(try database.reimbursementStatuses().first?.outstandingEURMinor, 5_000)
            XCTAssertEqual(normal.personalExpenseEURMinor, 5_000)
        }
    }

    func testLinkExistingRefundDoesNotDuplicateIncomeOrReduceNetTwice() throws {
        try withDatabase { database, _ in
            let account = UUID()
            let expense = try database.save(transaction(kind: .expense, cents: 5_000,
                day: "2026-10-01", accountID: account, merchant: "Fictional hotel"),
                expectedReimbursementEURMinor: 5_000)
            let refund = try database.save(transaction(kind: .reimbursement, cents: 5_000,
                day: "2026-10-10", accountID: account, merchant: "Fictional refund"))
            XCTAssertEqual(LedgerTotals(transactions: try database.transactions()).personalSpendingEURMinor, -5_000)
            try database.linkReimbursement(expenseID: expense.id, reimbursementID: refund.id)

            let active = try database.transactions()
            let totals = LedgerTotals(transactions: active)
            XCTAssertEqual(active.count, 2)
            XCTAssertEqual(totals.totalExpensesEURMinor, 5_000)
            XCTAssertEqual(totals.personalSpendingEURMinor, 0)
            XCTAssertEqual(totals.incomeEURMinor, 0)
            XCTAssertEqual(active.first { $0.id == refund.id }?.personalExpenseEURMinor, 0)
            XCTAssertEqual(try database.reimbursementStatuses().first?.title, "Rimborsato")
            XCTAssertEqual(try database.reimbursementStatuses().first?.outstandingEURMinor, 0)
            XCTAssertThrowsError(try database.linkReimbursement(expenseID: expense.id,
                                                                 reimbursementID: refund.id))
        }
    }

    func testManualAndMultiplePartialRefundsRejectOverpaymentAndAccountMismatch() throws {
        try withDatabase { database, _ in
            let account = UUID()
            let expense = try database.save(transaction(kind: .expense, cents: 10_000,
                day: "2026-10-01", accountID: account, merchant: "Fictional trip"),
                expectedReimbursementEURMinor: 8_000)
            let first = transaction(kind: .reimbursement, cents: 3_000,
                day: "2026-10-10", accountID: account, merchant: "Fictional partial one")
            _ = try database.createAndLinkReimbursement(expenseID: expense.id, reimbursement: first)
            let second = try database.save(transaction(kind: .reimbursement, cents: 2_000,
                day: "2026-11-01", accountID: account, merchant: "Fictional partial two"))
            try database.linkReimbursement(expenseID: expense.id, reimbursementID: second.id)
            let status = try XCTUnwrap(database.reimbursementStatuses().first)
            XCTAssertEqual(status.receivedEURMinor, 5_000)
            XCTAssertEqual(status.outstandingEURMinor, 3_000)
            XCTAssertEqual(status.linkedTransactionIDs.count, 2)
            XCTAssertEqual(LedgerTotals(transactions: try database.transactions()).personalSpendingEURMinor, 2_000)

            let tooLarge = try database.save(transaction(kind: .reimbursement, cents: 3_001,
                day: "2026-11-02", accountID: account, merchant: "Fictional too large"))
            XCTAssertThrowsError(try database.linkReimbursement(expenseID: expense.id,
                                                                 reimbursementID: tooLarge.id)) {
                XCTAssertEqual($0 as? ReimbursementError, .overpayment)
            }
            let wrongAccount = try database.save(transaction(kind: .reimbursement, cents: 1_000,
                day: "2026-11-03", accountID: UUID(), merchant: "Fictional wrong account"))
            XCTAssertThrowsError(try database.linkReimbursement(expenseID: expense.id,
                                                                 reimbursementID: wrongAccount.id)) {
                XCTAssertEqual($0 as? ReimbursementError, .accountMismatch)
            }
        }
    }

    func testWriteOffUsesOriginalExpenseDateAndCanBeUndone() throws {
        try withDatabase { database, _ in
            let account = UUID()
            let expense = try database.save(transaction(kind: .expense, cents: 5_000,
                day: "2026-09-15", accountID: account, merchant: "Fictional cancelled refund"),
                expectedReimbursementEURMinor: 5_000)
            try database.writeOffOutstandingReimbursement(expense.id)
            var status = try XCTUnwrap(database.reimbursementStatuses().first)
            XCTAssertEqual(status.outstandingEURMinor, 0)
            XCTAssertEqual(status.writtenOffEURMinor, 5_000)
            let active = try database.transactions()
            XCTAssertEqual(active.count, 1)
            XCTAssertEqual(active[0].occurredAt, date("2026-09-15"))
            XCTAssertEqual(LedgerTotals(transactions: active).personalSpendingEURMinor, 5_000)

            try database.undoReimbursementWriteOff(expense.id)
            status = try XCTUnwrap(database.reimbursementStatuses().first)
            XCTAssertEqual(status.outstandingEURMinor, 5_000)
            XCTAssertEqual(LedgerTotals(transactions: try database.transactions()).personalSpendingEURMinor, 0)
        }
    }

    func testCrossCurrencyRequiresExplicitHistoricalEURConversion() throws {
        try withDatabase { database, _ in
            let account = UUID()
            let expense = try database.save(transaction(kind: .expense, cents: 2_000,
                day: "2026-10-01", accountID: account, merchant: "Fictional foreign refund"),
                expectedReimbursementEURMinor: 2_000)
            var converted = transaction(kind: .reimbursement, cents: 2_500,
                day: "2026-10-10", accountID: account, merchant: "Fictional converted credit")
            converted.currency = "USD"
            converted.eurMinor = 2_000
            converted.exchangeRateEUR = "0.8"
            converted = try database.save(converted)
            try database.linkReimbursement(expenseID: expense.id, reimbursementID: converted.id)
            XCTAssertEqual(try database.reimbursementStatuses().first?.outstandingEURMinor, 0)

            let secondExpense = try database.save(transaction(kind: .expense, cents: 1_000,
                day: "2026-10-02", accountID: account, merchant: "Fictional missing rate"),
                expectedReimbursementEURMinor: 1_000)
            var missingRate = transaction(kind: .reimbursement, cents: 1_200,
                day: "2026-10-11", accountID: account, merchant: "Fictional unvalued credit")
            missingRate.currency = "USD"
            missingRate.eurMinor = 1_000
            missingRate.exchangeRateEUR = nil
            missingRate = try database.save(missingRate)
            XCTAssertThrowsError(try database.linkReimbursement(expenseID: secondExpense.id,
                                                                 reimbursementID: missingRate.id)) {
                XCTAssertEqual($0 as? ReimbursementError, .conversionRequired)
            }
        }
    }

    func testDifferentMonthsGraphsUnlinkAndDeletionRemainConsistent() throws {
        try withDatabase { database, _ in
            let account = UUID()
            let expense = try database.save(transaction(kind: .expense, cents: 5_000,
                day: "2026-09-15", accountID: account, merchant: "Fictional autumn trip"),
                expectedReimbursementEURMinor: 5_000)
            let refund = try database.save(transaction(kind: .reimbursement, cents: 5_000,
                day: "2026-10-05", accountID: account, merchant: "Fictional October refund"))
            try database.linkReimbursement(expenseID: expense.id, reimbursementID: refund.id)
            let september = try FinancialAnalytics.snapshot(transactions: try database.transactions(),
                period: .month(year: 2026, month: 9), timeZone: zone, now: date("2026-11-01"))
            let october = try FinancialAnalytics.snapshot(transactions: try database.transactions(),
                period: .month(year: 2026, month: 10), timeZone: zone, now: date("2026-11-01"))
            XCTAssertEqual(september.totals.grossExpensesEURMinor, 5_000)
            XCTAssertEqual(september.totals.personalNetExpensesEURMinor, 0)
            XCTAssertEqual(october.totals.personalNetExpensesEURMinor, 0)
            XCTAssertEqual(october.totals.incomeEURMinor, 0)

            try database.unlinkReimbursement(refund.id)
            XCTAssertEqual(try database.reimbursementStatuses().first?.outstandingEURMinor, 5_000)
            var deletedRefund = try XCTUnwrap(database.transactions().first { $0.id == refund.id })
            deletedRefund.deletedAt = .now
            _ = try database.save(deletedRefund)
            XCTAssertEqual(try database.reimbursementStatuses().first?.outstandingEURMinor, 5_000)
            XCTAssertTrue(try database.reimbursementLinks().isEmpty)
            var deletedExpense = try XCTUnwrap(database.transactions().first { $0.id == expense.id })
            deletedExpense.deletedAt = .now
            _ = try database.save(deletedExpense)
            XCTAssertTrue(try database.reimbursementStatuses().isEmpty)
        }
    }

    func testAmountEditBackupReplaceMergeAndSchemaEightMigration() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyTrack-reimbursement-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try SQLiteDatabase(url: folder.appendingPathComponent("source.sqlite"))
        try source.seedDemoIfNeeded()
        let account = UUID()
        var expense = try source.save(transaction(kind: .expense, cents: 5_000,
            day: "2026-10-01", accountID: account, merchant: "Fictional editable"),
            expectedReimbursementEURMinor: 5_000)
        expense.amountMinor = 4_000
        expense.eurMinor = 4_000
        _ = try source.save(expense, expectedReimbursementEURMinor: 4_000)
        XCTAssertEqual(try source.transactionExportSnapshotForTest(expense.id)?.personalExpenseEURMinor, 0)

        let backup = try source.exportBackup()
        XCTAssertEqual(backup.schemaVersion, 11)
        XCTAssertEqual(backup.databaseSchemaVersion, 10)
        let readOnly = try SQLiteDatabase(readOnlyURL: source.url)
        let export = try readOnly.transactionExportSnapshot().select(filter: .init(), options: {
            var options = TransactionExportOptions()
            options.columns = .detailed
            return options
        }())
        let csv = String(decoding: try TransactionCSVWriter.encode(export, options: {
            var options = TransactionExportOptions()
            options.columns = .detailed
            return options
        }()), as: UTF8.self)
        XCTAssertTrue(csv.contains("Reimbursement status"))
        XCTAssertTrue(csv.contains("Rimborso in attesa"))
        XCTAssertTrue(csv.contains("40.00"))
        let targetURL = folder.appendingPathComponent("target.sqlite")
        let target = try SQLiteDatabase(url: targetURL)
        try target.seedDemoIfNeeded()
        _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .replace)
        XCTAssertEqual(try target.reimbursementStatuses().first { $0.expenseID == expense.id }?.expectedEURMinor, 4_000)
        _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .merge)
        XCTAssertEqual(try target.reimbursementStatuses().filter { $0.expenseID == expense.id }.count, 1)

        let oldTables = Array(backup.tables.prefix(27))
        let old = BackupArchive(schemaVersion: 9, databaseSchemaVersion: 8,
            exportID: UUID(), exportedAt: .now,
            contentSHA256: try SQLiteDatabase.digest(oldTables), tables: oldTables,
            sourceFormatVersion: nil)
        let upgraded = try BackupArchive.decode(JSONEncoder().encode(old))
        XCTAssertEqual(upgraded.schemaVersion, 11)
        XCTAssertEqual(upgraded.sourceFormatVersion, 9)
        XCTAssertEqual(upgraded.tables[29].rows.first?[1], "1")
        XCTAssertTrue(upgraded.tables[30].rows.isEmpty)

        let migrationURL = folder.appendingPathComponent("migration.sqlite")
        let migration = try SQLiteDatabase(url: migrationURL)
        try migration.execute("DROP TABLE expense_reimbursement_links")
        try migration.execute("DROP TABLE expense_reimbursement_plans")
        try migration.execute("PRAGMA user_version=8")
        XCTAssertTrue(try SQLiteDatabase(url: migrationURL).reimbursementStatuses().isEmpty)
    }
}

private extension SQLiteDatabase {
    func transactionExportSnapshotForTest(_ id: UUID) throws -> Transaction? {
        try transactions().first { $0.id == id }
    }
}
