import Foundation
import XCTest
@testable import EasyTrackCore

final class CashFlowAccountingTests: XCTestCase {
    private let zone = TimeZone(identifier: "Europe/Rome")!

    private func date(_ value: String) -> Date {
        LocalDay(isoString: value)!.noon(in: zone)!
    }

    private func withDatabase(_ body: (SQLiteDatabase) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyTrack-cash-flow-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(SQLiteDatabase(url: directory.appendingPathComponent("ledger.sqlite")))
    }

    private func movement(_ kind: TransactionKind, _ cents: Int64, _ day: String,
                          accountID: UUID? = nil, categoryID: UUID? = nil) -> Transaction {
        var item = Transaction(id: UUID(), kind: kind, amountMinor: cents, currency: "EUR",
            merchant: "Fictional \(kind.title)", account: "Fictional account", category: "Travel",
            note: "", occurredAt: date(day), updatedAt: date(day), deletedAt: nil,
            isDemo: false, revision: 0, sourceEventID: nil)
        item.accountID = accountID
        item.categoryID = categoryID
        item.eurMinor = cents
        item.personalExpenseEURMinor = kind == .expense ? cents : (kind == .reimbursement ? -cents : 0)
        item.recoverableEURMinor = kind == .advanceForOthers ? cents : 0
        return item
    }

    private func month(_ database: SQLiteDatabase, _ year: Int = 2026, _ number: Int = 10)
        throws -> FinancialAnalyticsSnapshot {
        try FinancialAnalytics.snapshot(transactions: database.transactions().filter { !$0.isDemo },
            period: .month(year: year, month: number),
            reimbursementStatuses: database.reimbursementStatuses(),
            timeZone: zone, now: date("2027-02-01"))
    }

    private func expect(_ totals: FinancialTotals, income: Int64, expenses: Int64,
                        netExpenses: Int64, net: Int64, pending: Int64) {
        XCTAssertEqual(totals.incomeEURMinor, income)
        XCTAssertEqual(totals.grossIncomeEURMinor, income)
        XCTAssertEqual(totals.grossExpensesEURMinor, expenses)
        XCTAssertEqual(totals.personalNetExpensesEURMinor, netExpenses)
        XCTAssertEqual(totals.netExpensesEURMinor, netExpenses)
        XCTAssertEqual(totals.cashNetEURMinor, net)
        XCTAssertEqual(totals.netEURMinor, net)
        XCTAssertEqual(totals.pendingReimbursementsEURMinor, pending)
    }

    func testMandatoryNumericalExamplesAThroughE() throws {
        try withDatabase { db in
            _ = try db.save(movement(.income, 100_000, "2026-10-01"))
            _ = try db.save(movement(.expense, 60_000, "2026-10-02"))
            expect(try month(db).totals, income: 100_000, expenses: 60_000,
                   netExpenses: 60_000, net: 40_000, pending: 0) // A
        }
        try withDatabase { db in
            let expense = try db.save(movement(.expense, 10_000, "2026-10-02"),
                                      expectedReimbursementEURMinor: 10_000)
            expect(try month(db).totals, income: 0, expenses: 10_000,
                   netExpenses: 10_000, net: -10_000, pending: 10_000) // B
            _ = try db.createAndLinkReimbursement(expenseID: expense.id,
                reimbursement: movement(.reimbursement, 4_000, "2026-10-05"))
            expect(try month(db).totals, income: 4_000, expenses: 10_000,
                   netExpenses: 6_000, net: -6_000, pending: 6_000) // C
            _ = try db.createAndLinkReimbursement(expenseID: expense.id,
                reimbursement: movement(.reimbursement, 6_000, "2026-10-06"))
            expect(try month(db).totals, income: 10_000, expenses: 10_000,
                   netExpenses: 0, net: 0, pending: 0) // E
        }
        try withDatabase { db in
            _ = try db.save(movement(.income, 100_000, "2026-10-01"))
            let expense = try db.save(movement(.expense, 10_000, "2026-10-02"),
                                      expectedReimbursementEURMinor: 10_000)
            _ = try db.save(movement(.expense, 20_000, "2026-10-03"))
            _ = try db.createAndLinkReimbursement(expenseID: expense.id,
                reimbursement: movement(.reimbursement, 10_000, "2026-10-05"))
            expect(try month(db).totals, income: 110_000, expenses: 30_000,
                   netExpenses: 20_000, net: 80_000, pending: 0) // D
        }
    }

    func testExistingReceiptOtherAccountPartialsWriteOffAndUnlink() throws {
        try withDatabase { db in
            let expenseAccount = UUID()
            let receiptAccount = UUID()
            let categoryID = UUID()
            _ = try db.saveLocalAccount(LocalAccount(id: expenseAccount,
                name: "Fictional checking", createdAt: .now,
                symbolName: "creditcard.fill", colorName: "teal"))
            _ = try db.saveLocalAccount(LocalAccount(id: receiptAccount,
                name: "Fictional savings", createdAt: .now,
                symbolName: "building.columns.fill", colorName: "blue"))
            _ = try db.saveLedgerCategory(LedgerCategory(id: categoryID,
                name: "Fictional Travel Audit", symbolName: "airplane", colorName: "teal",
                sortIndex: 0, createdAt: .now, updatedAt: .now,
                archivedAt: nil, revision: 0))
            let expense = try db.save(movement(.expense, 10_001, "2026-10-02",
                accountID: expenseAccount, categoryID: categoryID), expectedReimbursementEURMinor: 10_001)
            let receipt = try db.save(movement(.reimbursement, 4_001, "2026-10-05",
                accountID: receiptAccount))
            let countBefore = try db.transactions().count
            try db.linkReimbursement(expenseID: expense.id, reimbursementID: receipt.id)
            XCTAssertEqual(try db.transactions().count, countBefore)
            XCTAssertEqual(try db.transactions().first { $0.id == receipt.id }?.accountID, receiptAccount)
            XCTAssertEqual(try db.transactions().first { $0.id == expense.id }?.accountID, expenseAccount)
            expect(try month(db).totals, income: 4_001, expenses: 10_001,
                   netExpenses: 6_000, net: -6_000, pending: 6_000)
            let budget = MonthlyBudget(id: UUID(), scope: .overall, categoryID: nil,
                limitEURMinor: 10_001, createdAt: .now, updatedAt: .now,
                archivedAt: nil, revision: 0)
            let progress = try BudgetAnalytics.snapshot(financial: month(db),
                budgets: [budget], categories: [])
            XCTAssertEqual(progress.overall?.spentEURMinor, 6_000)
            XCTAssertEqual(try month(db).categories.first { $0.categoryID == categoryID }?.personalNetExpensesEURMinor,
                           6_000)

            try db.configureExpectedReimbursement(expenseID: expense.id, expectedEURMinor: 8_001)
            XCTAssertEqual(try db.reimbursementStatuses().first?.outstandingEURMinor, 4_000)
            XCTAssertEqual(try month(db).totals.personalNetExpensesEURMinor, 6_000)
            try db.writeOffOutstandingReimbursement(expense.id)
            XCTAssertEqual(try month(db).totals.pendingReimbursementsEURMinor, 0)
            XCTAssertEqual(try month(db).totals.personalNetExpensesEURMinor, 6_000)
            try db.undoReimbursementWriteOff(expense.id)
            XCTAssertEqual(try month(db).totals.pendingReimbursementsEURMinor, 4_000)
            try db.unlinkReimbursement(receipt.id)
            XCTAssertEqual(try month(db).totals.personalNetExpensesEURMinor, 6_000)
            XCTAssertEqual(try db.reimbursementStatuses().first?.outstandingEURMinor, 8_001)
            var deleted = try XCTUnwrap(db.transactions().first { $0.id == receipt.id })
            deleted.deletedAt = .now
            _ = try db.save(deleted)
            expect(try month(db).totals, income: 0, expenses: 10_001,
                   netExpenses: 10_001, net: -10_001, pending: 8_001)
        }
    }

    func testReceiptDateControlsIncomeWhileLinkedCostReturnsToExpenseYear() throws {
        try withDatabase { db in
            let expense = try db.save(movement(.expense, 10_000, "2025-12-30"),
                                      expectedReimbursementEURMinor: 10_000)
            let decemberBefore = try month(db, 2025, 12)
            expect(decemberBefore.totals, income: 0, expenses: 10_000,
                   netExpenses: 10_000, net: -10_000, pending: 10_000)
            let receipt = try db.save(movement(.reimbursement, 4_000, "2026-01-03"))
            try db.linkReimbursement(expenseID: expense.id, reimbursementID: receipt.id)
            let december = try month(db, 2025, 12)
            let january = try month(db, 2026, 1)
            expect(december.totals, income: 0, expenses: 10_000,
                   netExpenses: 6_000, net: -10_000, pending: 6_000)
            expect(january.totals, income: 4_000, expenses: 0,
                   netExpenses: 0, net: 4_000, pending: 0)
            let year2025 = try FinancialAnalytics.snapshot(transactions: db.transactions(),
                period: .year(2025), timeZone: zone, now: date("2027-02-01"))
            let year2026 = try FinancialAnalytics.snapshot(transactions: db.transactions(),
                period: .year(2026), timeZone: zone, now: date("2027-02-01"))
            XCTAssertEqual(year2025.totals.personalNetExpensesEURMinor, 6_000)
            XCTAssertEqual(year2026.totals.incomeEURMinor, 4_000)
            let incomeFilter = try XCTUnwrap(HomeMetricDrilldown.filter(for: .income, snapshot: january))
            let expensesFilter = try XCTUnwrap(HomeMetricDrilldown.filter(for: .expenses, snapshot: december))
            XCTAssertEqual(incomeFilter.apply(to: try db.transactions(), timeZone: zone).map(\.id), [receipt.id])
            XCTAssertEqual(expensesFilter.apply(to: try db.transactions(), timeZone: zone).map(\.id), [expense.id])
            XCTAssertNil(HomeMetricDrilldown.filter(for: .net, snapshot: january))
        }
    }

    func testOldDatabaseAndVersionFourteenBackupRecalculateWithoutChangingMovements() throws {
        try withDatabase { db in
            try db.seedDemoIfNeeded()
            let expense = try db.save(movement(.expense, 10_000, "2026-10-02"),
                                      expectedReimbursementEURMinor: 10_000)
            let receipt = try db.save(movement(.reimbursement, 4_000, "2026-10-05"))
            try db.linkReimbursement(expenseID: expense.id, reimbursementID: receipt.id)
            let revision = try XCTUnwrap(db.transactions().first { $0.id == expense.id }?.revision)
            let current = try db.exportBackup()
            let index = try XCTUnwrap(current.tables.firstIndex { $0.name == "transactions" })
            var tables = current.tables
            let idColumn = try XCTUnwrap(tables[index].columns.firstIndex(of: "id"))
            let personalColumn = try XCTUnwrap(tables[index].columns.firstIndex(of: "personal_expense_eur_minor"))
            var rows = tables[index].rows
            let rowIndex = try XCTUnwrap(rows.firstIndex { $0[idColumn] == expense.id.uuidString })
            rows[rowIndex][personalColumn] = "0" // Version 14 excluded the expected amount.
            tables[index] = BackupTable(name: "transactions", columns: tables[index].columns, rows: rows)
            let old = BackupArchive(schemaVersion: 14, databaseSchemaVersion: 13,
                exportID: UUID(), exportedAt: .now,
                contentSHA256: try SQLiteDatabase.digest(tables), tables: tables,
                sourceFormatVersion: nil)
            let upgraded = try BackupArchive.decode(JSONEncoder().encode(old))
            XCTAssertEqual(upgraded.schemaVersion, 15)
            XCTAssertEqual(upgraded.sourceFormatVersion, 14)
            XCTAssertEqual(upgraded.tables[index].rows[rowIndex][personalColumn], "6000")
            try db.execute("UPDATE transactions SET personal_expense_eur_minor=0 WHERE id='\(expense.id.uuidString)'")
            let reopened = try SQLiteDatabase(url: db.url)
            XCTAssertEqual(try reopened.transactions().first { $0.id == expense.id }?.personalExpenseEURMinor, 6_000)
            XCTAssertEqual(try reopened.transactions().first { $0.id == expense.id }?.revision, revision)
            let target = try SQLiteDatabase(url: db.url.deletingLastPathComponent()
                .appendingPathComponent("restored.sqlite"))
            try target.seedDemoIfNeeded()
            _ = try target.restoreBackup(upgraded, preview: target.previewBackup(upgraded), mode: .replace)
            XCTAssertEqual(try target.transactions().first { $0.id == expense.id }?.personalExpenseEURMinor, 6_000)
            XCTAssertEqual(try target.transactions().first { $0.id == receipt.id }?.occurredAt, date("2026-10-05"))
            XCTAssertEqual(try target.reimbursementLinks().count, 1)
            try target.checkDatabase()
        }
    }

    func testDrilldownsExcludePACAndDepositsAndHandleEmptyAndLargePeriods() throws {
        let rows = [movement(.income, 2_000, "2026-10-01"),
                    movement(.reimbursement, 500, "2026-10-02"),
                    movement(.expense, 4_000, "2026-10-03"),
                    movement(.pacInvestment, 1_000, "2026-10-04"),
                    movement(.advanceForOthers, 700, "2026-10-05"),
                    movement(.deposit, 300, "2026-10-06"),
                    movement(.depositRefund, 300, "2026-10-07")]
        let october = try FinancialAnalytics.snapshot(transactions: rows,
            period: .month(year: 2026, month: 10), timeZone: zone, now: date("2027-02-01"))
        expect(october.totals, income: 2_500, expenses: 4_000,
               netExpenses: 3_500, net: -1_500, pending: 0)
        XCTAssertEqual(try XCTUnwrap(HomeMetricDrilldown.filter(for: .income, snapshot: october))
            .apply(to: rows, timeZone: zone).count, 2)
        XCTAssertEqual(try XCTUnwrap(HomeMetricDrilldown.filter(for: .expenses, snapshot: october))
            .apply(to: rows, timeZone: zone).count, 1)
        let empty = try FinancialAnalytics.snapshot(transactions: rows,
            period: .month(year: 2026, month: 11), timeZone: zone, now: date("2027-02-01"))
        expect(empty.totals, income: 0, expenses: 0, netExpenses: 0, net: 0, pending: 0)

        let many = (0..<10_000).map { offset in
            movement(offset.isMultiple(of: 2) ? .income : .expense, 1,
                     "2026-10-03")
        }
        let large = try FinancialAnalytics.snapshot(transactions: many,
            period: .month(year: 2026, month: 10), timeZone: zone, now: date("2027-02-01"))
        expect(large.totals, income: 5_000, expenses: 5_000,
               netExpenses: 5_000, net: 0, pending: 0)
        let overflowing = [movement(.income, Int64.max, "2026-10-01"),
                           movement(.reimbursement, 1, "2026-10-02")]
        XCTAssertThrowsError(try FinancialAnalytics.snapshot(transactions: overflowing,
            period: .month(year: 2026, month: 10), timeZone: zone,
            now: date("2027-02-01"))) {
            XCTAssertEqual($0 as? FinancialAnalyticsError, .amountOverflow)
        }
        func outstanding(_ amount: Int64) -> ExpenseReimbursementStatus {
            ExpenseReimbursementStatus(expenseID: UUID(), expectedEURMinor: amount,
                receivedEURMinor: 0, writtenOffEURMinor: 0,
                outstandingEURMinor: amount, linkedTransactionIDs: [], updatedAt: .now)
        }
        XCTAssertEqual(try ReimbursementTotals.pending([outstanding(1), outstanding(2)]), 3)
        XCTAssertThrowsError(try ReimbursementTotals.pending([outstanding(Int64.max), outstanding(1)])) {
            XCTAssertEqual($0 as? FinancialAnalyticsError, .amountOverflow)
        }
    }
}
