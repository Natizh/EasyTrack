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
            XCTAssertEqual(totals.personalSpendingEURMinor, 10_000)
            XCTAssertEqual(totals.incomeEURMinor, 0)
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
            XCTAssertEqual(LedgerTotals(transactions: try database.transactions()).personalSpendingEURMinor, 0)
            try database.linkReimbursement(expenseID: expense.id, reimbursementID: refund.id)

            let active = try database.transactions()
            let totals = LedgerTotals(transactions: active)
            XCTAssertEqual(active.count, 2)
            XCTAssertEqual(totals.totalExpensesEURMinor, 5_000)
            XCTAssertEqual(totals.personalSpendingEURMinor, 0)
            XCTAssertEqual(totals.incomeEURMinor, 5_000)
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
            XCTAssertEqual(LedgerTotals(transactions: try database.transactions()).personalSpendingEURMinor, 5_000)

            let tooLarge = try database.save(transaction(kind: .reimbursement, cents: 3_001,
                day: "2026-11-02", accountID: account, merchant: "Fictional too large"))
            XCTAssertThrowsError(try database.linkReimbursement(expenseID: expense.id,
                                                                 reimbursementID: tooLarge.id)) {
                XCTAssertEqual($0 as? ReimbursementError, .overpayment)
            }
            let wrongAccount = try database.save(transaction(kind: .reimbursement, cents: 1_000,
                day: "2026-11-03", accountID: UUID(), merchant: "Fictional wrong account"))
            try database.linkReimbursement(expenseID: expense.id, reimbursementID: wrongAccount.id)
            XCTAssertEqual(try database.reimbursementStatuses().first?.outstandingEURMinor, 2_000)
        }
    }

    func testAdvancePlanAllowsCrossAccountReceiptBeforeExpenseWithoutDoubleCounting() throws {
        try withDatabase { database, _ in
            let receipt = try database.save(transaction(kind: .reimbursement, cents: 3_339,
                day: "2026-10-12", accountID: UUID(), merchant: "Fictional early receipt"))
            var advance = transaction(kind: .advanceForOthers, cents: 3_339,
                day: "2026-10-14", accountID: UUID(), merchant: "Fictional later advance")
            advance.personalExpenseEURMinor = 0
            advance.recoverableEURMinor = 3_339
            advance = try database.save(advance)
            try database.configureExpectedReimbursement(expenseID: advance.id, expectedEURMinor: 3_339)
            try database.linkReimbursement(expenseID: advance.id, reimbursementID: receipt.id)
            let status = try XCTUnwrap(database.reimbursementStatuses().first)
            XCTAssertEqual(status.receivedEURMinor, 3_339)
            XCTAssertEqual(status.outstandingEURMinor, 0)
            let active = try database.transactions()
            XCTAssertEqual(active.first { $0.id == advance.id }?.personalExpenseEURMinor, 0)
            XCTAssertEqual(active.first { $0.id == receipt.id }?.personalExpenseEURMinor, 0)
            XCTAssertEqual(LedgerTotals(transactions: active).personalSpendingEURMinor, 0)
            try database.checkDatabase()
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
            XCTAssertEqual(LedgerTotals(transactions: try database.transactions()).personalSpendingEURMinor, 5_000)
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
            XCTAssertEqual(october.totals.incomeEURMinor, 5_000)
            XCTAssertEqual(october.totals.cashNetEURMinor, 5_000)

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
        XCTAssertEqual(try source.transactionExportSnapshotForTest(expense.id)?.personalExpenseEURMinor, 4_000)

        let backup = try source.exportBackup()
        XCTAssertEqual(backup.schemaVersion, 15)
        XCTAssertEqual(backup.databaseSchemaVersion, 13)
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

        let oldTables = Array(BackupArchive.schemaElevenShape(backup.tables).prefix(27))
        let old = BackupArchive(schemaVersion: 9, databaseSchemaVersion: 8,
            exportID: UUID(), exportedAt: .now,
            contentSHA256: try SQLiteDatabase.digest(oldTables), tables: oldTables,
            sourceFormatVersion: nil)
        let upgraded = try BackupArchive.decode(JSONEncoder().encode(old))
        XCTAssertEqual(upgraded.schemaVersion, 15)
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

    func testCrossAccountReimbursementLinksAndSurvivesRelaunch() throws {
        try withDatabase { database, url in
            let paying = try database.saveLocalAccount(LocalAccount(id: UUID(), name: "Fictional paying card",
                                                                    createdAt: date("2026-10-01")))
            let receiving = try database.saveLocalAccount(LocalAccount(id: UUID(), name: "Fictional receiving bank",
                                                                      createdAt: date("2026-10-01")))
            var expense = transaction(kind: .expense, cents: 10_000, day: "2026-10-01",
                                      accountID: paying.id, merchant: "Fictional conference")
            expense.account = paying.name
            expense.accountID = paying.id
            let savedExpense = try database.save(expense, expectedReimbursementEURMinor: 10_000)

            var receipt = transaction(kind: .reimbursement, cents: 4_000, day: "2026-10-20",
                                      accountID: receiving.id, merchant: "Fictional employer refund")
            receipt.account = receiving.name
            receipt.accountID = receiving.id
            receipt.accountCurrency = receiving.nativeCurrency
            receipt.accountAmountMinor = 4_000
            _ = try database.createAndLinkReimbursement(expenseID: savedExpense.id, reimbursement: receipt)

            var status = try XCTUnwrap(database.reimbursementStatuses().first)
            XCTAssertEqual(status.receivedEURMinor, 4_000)
            XCTAssertEqual(status.outstandingEURMinor, 6_000)
            let linked = try XCTUnwrap(database.transactions().first { $0.kind == .reimbursement })
            XCTAssertEqual(linked.accountID, receiving.id)
            XCTAssertEqual(linked.account, receiving.name)
            XCTAssertEqual(linked.accountCurrency, "EUR")
            XCTAssertEqual(linked.accountAmountMinor, 4_000)
            XCTAssertEqual(LedgerTotals(transactions: try database.transactions()).personalSpendingEURMinor, 0)

            let reopened = try SQLiteDatabase(url: url)
            status = try XCTUnwrap(reopened.reimbursementStatuses().first)
            XCTAssertEqual(status.outstandingEURMinor, 6_000)
            XCTAssertEqual(try reopened.reimbursementLinks().first?.reimbursementID, linked.id)
            XCTAssertEqual(try reopened.transactions().first { $0.id == linked.id }?.accountID, receiving.id)
            try reopened.checkDatabase()
        }
    }

    func testCrossAccountReimbursementAcceptsArchivedReceivingAccount() throws {
        try withDatabase { database, _ in
            let paying = try database.saveLocalAccount(LocalAccount(id: UUID(), name: "Fictional paying card",
                                                                    createdAt: date("2026-10-01")))
            let closed = try database.saveLocalAccount(LocalAccount(id: UUID(), name: "Fictional closed bank",
                                                                    createdAt: date("2026-10-01"),
                                                                    archivedAt: date("2026-10-05")))
            var expense = transaction(kind: .expense, cents: 5_000, day: "2026-10-01",
                                      accountID: paying.id, merchant: "Fictional taxi")
            expense.account = paying.name
            expense.accountID = paying.id
            let savedExpense = try database.save(expense, expectedReimbursementEURMinor: 5_000)

            var receipt = transaction(kind: .reimbursement, cents: 5_000, day: "2026-10-06",
                                      accountID: closed.id, merchant: "Fictional late refund")
            receipt.account = closed.name
            receipt.accountID = closed.id
            _ = try database.createAndLinkReimbursement(expenseID: savedExpense.id, reimbursement: receipt)

            let status = try XCTUnwrap(database.reimbursementStatuses().first)
            XCTAssertEqual(status.outstandingEURMinor, 0)
            XCTAssertEqual(try database.transactions().first { $0.kind == .reimbursement }?.accountID, closed.id)
            XCTAssertEqual(LedgerTotals(transactions: try database.transactions()).personalSpendingEURMinor, 0)
        }
    }

    func testCrossAccountReimbursementStillRejectsOverpaymentAndRelinking() throws {
        try withDatabase { database, _ in
            let paying = try database.saveLocalAccount(LocalAccount(id: UUID(), name: "Fictional paying card",
                                                                    createdAt: date("2026-10-01")))
            let receiving = try database.saveLocalAccount(LocalAccount(id: UUID(), name: "Fictional receiving bank",
                                                                      createdAt: date("2026-10-01")))
            var expense = transaction(kind: .expense, cents: 5_000, day: "2026-10-01",
                                      accountID: paying.id, merchant: "Fictional train")
            expense.account = paying.name
            expense.accountID = paying.id
            let savedExpense = try database.save(expense, expectedReimbursementEURMinor: 5_000)

            var receipt = transaction(kind: .reimbursement, cents: 5_000, day: "2026-10-02",
                                      accountID: receiving.id, merchant: "Fictional refund")
            receipt.account = receiving.name
            receipt.accountID = receiving.id
            _ = try database.createAndLinkReimbursement(expenseID: savedExpense.id, reimbursement: receipt)

            var extra = transaction(kind: .reimbursement, cents: 100, day: "2026-10-03",
                                    accountID: receiving.id, merchant: "Fictional extra")
            extra.account = receiving.name
            extra.accountID = receiving.id
            let savedExtra = try database.save(extra)
            XCTAssertThrowsError(try database.linkReimbursement(expenseID: savedExpense.id,
                                                                 reimbursementID: savedExtra.id)) {
                XCTAssertEqual($0 as? ReimbursementError, .overpayment)
            }
            XCTAssertThrowsError(try database.linkReimbursement(expenseID: savedExpense.id,
                                                                 reimbursementID: receipt.id))
        }
    }

    func testCrossAccountReceiptCannotMoveAccountWhileLinked() throws {
        try withDatabase { database, _ in
            let paying = try database.saveLocalAccount(LocalAccount(id: UUID(), name: "Fictional paying card",
                                                                    createdAt: date("2026-10-01")))
            let receiving = try database.saveLocalAccount(LocalAccount(id: UUID(), name: "Fictional receiving bank",
                                                                      createdAt: date("2026-10-01")))
            let other = try database.saveLocalAccount(LocalAccount(id: UUID(), name: "Fictional other bank",
                                                                   createdAt: date("2026-10-01")))
            var expense = transaction(kind: .expense, cents: 5_000, day: "2026-10-01",
                                      accountID: paying.id, merchant: "Fictional museum")
            expense.account = paying.name
            expense.accountID = paying.id
            let savedExpense = try database.save(expense, expectedReimbursementEURMinor: 5_000)
            var receipt = transaction(kind: .reimbursement, cents: 5_000, day: "2026-10-02",
                                      accountID: receiving.id, merchant: "Fictional refund")
            receipt.account = receiving.name
            receipt.accountID = receiving.id
            let linked = try database.createAndLinkReimbursement(expenseID: savedExpense.id,
                                                                 reimbursement: receipt)

            var moved = try XCTUnwrap(database.transactions().first { $0.id == linked.id })
            moved.accountID = other.id
            moved.account = other.name
            XCTAssertThrowsError(try database.save(moved)) {
                XCTAssertEqual($0 as? ReimbursementError, .linkedReceiptRequiresUnlink)
            }
            try database.unlinkReimbursement(linked.id)
            _ = try database.save(moved)
            XCTAssertEqual(try database.transactions().first { $0.id == linked.id }?.accountID, other.id)
        }
    }

    func testNewReceiptAccountSelectionNeverGuessesAnArchivedOrForeignAccount() {
        let activeEUR = LocalAccount(id: UUID(), name: "Fictional EUR account", createdAt: .now)
        var archived = LocalAccount(id: UUID(), name: "Fictional archived account", createdAt: .now)
        archived.archivedAt = .now
        let activeUSD = LocalAccount(id: UUID(), name: "Fictional USD account", createdAt: .now,
                                     nativeCurrency: "USD")
        let accounts = [archived, activeUSD, activeEUR]
        XCTAssertEqual(NewReimbursementAccountPolicy.proposed(
            expenseAccountID: activeEUR.id, accounts: accounts)?.id, activeEUR.id)
        XCTAssertNil(NewReimbursementAccountPolicy.proposed(expenseAccountID: archived.id,
            accounts: accounts))
        XCTAssertNil(NewReimbursementAccountPolicy.proposed(expenseAccountID: activeUSD.id,
            accounts: accounts))
        XCTAssertNil(NewReimbursementAccountPolicy.proposed(expenseAccountID: nil,
            accounts: accounts))
        XCTAssertFalse(NewReimbursementAccountPolicy.isEligible(archived))
        XCTAssertFalse(NewReimbursementAccountPolicy.isEligible(activeUSD))
    }

    func testTwoPartialReceiptsOnDifferentAccountsSurviveBackupReplace() throws {
        try withDatabase { source, url in
            try source.prepareProductionLedger()
            let paying = try source.saveLocalAccount(LocalAccount(id: UUID(), name: "Fictional payer",
                                                               createdAt: date("2026-10-01")))
            let bankB = try source.saveLocalAccount(LocalAccount(id: UUID(), name: "Fictional bank B",
                                                              createdAt: date("2026-10-01")))
            let bankC = try source.saveLocalAccount(LocalAccount(id: UUID(), name: "Fictional bank C",
                                                              createdAt: date("2026-10-01")))
            var expense = transaction(kind: .expense, cents: 10_000, day: "2026-10-01",
                                      accountID: paying.id, merchant: "Fictional group booking")
            expense.accountID = paying.id
            expense.account = paying.name
            let saved = try source.save(expense, expectedReimbursementEURMinor: 10_000)
            for (account, cents) in [(bankB, Int64(4_000)), (bankC, 6_000)] {
                var receipt = transaction(kind: .reimbursement, cents: cents, day: "2026-10-10",
                                          accountID: account.id, merchant: "Fictional partial refund")
                receipt.accountID = account.id
                receipt.account = account.name
                receipt.accountCurrency = "EUR"
                receipt.accountAmountMinor = cents
                _ = try source.createAndLinkReimbursement(expenseID: saved.id, reimbursement: receipt)
            }
            let status = try XCTUnwrap(source.reimbursementStatuses().first)
            XCTAssertEqual(status.receivedEURMinor, 10_000)
            XCTAssertEqual(status.outstandingEURMinor, 0)
            XCTAssertEqual(status.linkedTransactionIDs.count, 2)
            let totals = LedgerTotals(transactions: try source.transactions())
            XCTAssertEqual(totals.totalExpensesEURMinor, 10_000)
            XCTAssertEqual(totals.personalSpendingEURMinor, 0)
            XCTAssertEqual(totals.incomeEURMinor, 0)
            XCTAssertEqual(Set(try source.transactions().filter { $0.kind == .reimbursement }
                .compactMap(\.accountID)), Set([bankB.id, bankC.id]))

            let backup = try source.exportBackup()
            let target = try SQLiteDatabase(url: url.deletingLastPathComponent()
                .appendingPathComponent("restore.sqlite"))
            _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .replace)
            XCTAssertEqual(try target.reimbursementStatuses().first?.outstandingEURMinor, 0)
            XCTAssertEqual(try target.reimbursementLinks().count, 2)
            XCTAssertEqual(LedgerTotals(transactions: try target.transactions()), totals)
            try target.checkDatabase()
        }
    }

    func testExistingForeignReceiptOnArchivedAccountCanBeLinkedWithVerifiedEUR() throws {
        try withDatabase { database, _ in
            let paying = try database.saveLocalAccount(LocalAccount(id: UUID(), name: "Fictional EUR payer",
                                                                  createdAt: date("2026-10-01")))
            let archivedUSD = try database.saveLocalAccount(LocalAccount(id: UUID(),
                name: "Fictional archived USD", createdAt: date("2026-10-01"),
                archivedAt: date("2026-10-05"), nativeCurrency: "USD"))
            var expense = transaction(kind: .expense, cents: 5_000, day: "2026-10-01",
                                      accountID: paying.id, merchant: "Fictional expense")
            expense.accountID = paying.id
            expense.account = paying.name
            let savedExpense = try database.save(expense, expectedReimbursementEURMinor: 5_000)
            var receipt = transaction(kind: .reimbursement, cents: 6_000, day: "2026-10-06",
                                      accountID: archivedUSD.id, merchant: "Fictional USD refund")
            receipt.currency = "USD"
            receipt.accountID = archivedUSD.id
            receipt.account = archivedUSD.name
            receipt.accountCurrency = "USD"
            receipt.accountAmountMinor = 6_000
            receipt.eurMinor = 4_600
            receipt.exchangeRateEUR = "0.7666667"
            receipt.eurValueSource = .confirmed
            let existing = try database.save(receipt)
            try database.linkReimbursement(expenseID: savedExpense.id,
                                           reimbursementID: existing.id)
            XCTAssertEqual(try database.reimbursementStatuses().first?.outstandingEURMinor, 400)
            XCTAssertEqual(try database.transactions().first { $0.id == existing.id }?.accountID,
                           archivedUSD.id)
            let totals = LedgerTotals(transactions: try database.transactions())
            XCTAssertEqual(totals.totalExpensesEURMinor, 5_000)
            XCTAssertEqual(totals.personalSpendingEURMinor, 0)
            XCTAssertEqual(totals.incomeEURMinor, 0)
            try database.checkDatabase()
        }
    }
}

private extension SQLiteDatabase {
    func transactionExportSnapshotForTest(_ id: UUID) throws -> Transaction? {
        try transactions().first { $0.id == id }
    }
}
