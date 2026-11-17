import Foundation
import SQLite3
import XCTest
@testable import EasyTrackCore

final class ImportTests: XCTestCase {
    #if os(macOS)
    func testDownloadableExampleConvertsAndImportsWithoutWarnings() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyTrack-example-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let seedURL = folder.appendingPathComponent("example-seed.sqlite")
        let auditURL = folder.appendingPathComponent("example-audit.txt")
        let converter = Process()
        converter.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        converter.arguments = ["python3", "Tools/HistoricalImportConverter/convert_xlsx.py",
            "--input", "docs/examples/EasyTrack-example-import.xlsx",
            "--mapping", "docs/examples/simple-import-mapping.json",
            "--output", seedURL.path, "--audit", auditURL.path]
        converter.currentDirectoryURL = root
        let output = Pipe()
        converter.standardOutput = output
        converter.standardError = output
        try converter.run()
        converter.waitUntilExit()
        let diagnostic = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(converter.terminationStatus, 0, diagnostic)
        let seed = try SeedMapper(url: seedURL).read(url: seedURL)
        XCTAssertEqual(seed.schemaVersion, 3)
        XCTAssertEqual(seed.movements.count, 3)
        XCTAssertTrue(seed.warnings.isEmpty)
        XCTAssertEqual(Set(seed.movements.map { $0.transaction.kind }),
                       Set([.expense, .income, .pacInvestment]))
        let database = try SQLiteDatabase(url: folder.appendingPathComponent("ledger.sqlite"))
        XCTAssertEqual(try database.importHistoricalSeed(seed).newMovements, 3)
        XCTAssertEqual(try database.importHistoricalSeed(seed).alreadyImported, 3)
        let totals = LedgerTotals(transactions: try database.transactions())
        XCTAssertEqual(totals.personalSpendingEURMinor, 2_490)
        XCTAssertEqual(totals.totalExpensesEURMinor, 2_490)
        XCTAssertEqual(totals.incomeEURMinor, 245_000)
        XCTAssertEqual(totals.pacInvestedEURMinor, 15_000)
    }
    #endif

    func testExactKindMappingAndCurrencyMinorUnits() {
        XCTAssertEqual(SeedMapper.kind("Investimento PAC"), .pacInvestment)
        XCTAssertEqual(SeedMapper.kind("Anticipo per altri"), .advanceForOthers)
        XCTAssertEqual(SeedMapper.kind("Rimborso deposito"), .depositRefund)
        XCTAssertNil(SeedMapper.kind("Unfamiliar"))
        XCTAssertEqual(Money.parseMinor("123,45"), 12_345)
        XCTAssertEqual(Money.parseSignedMinor("-12.34"), -1_234)
        XCTAssertEqual(Money.parseMinor("0.001"), nil)
        XCTAssertNotEqual(Money.format(1_234, currency: "CNY"), Money.format(1_234, currency: "EUR"))
        XCTAssertEqual(SeedMapper.stableTransactionID(sourceID: "legacy-row-9"),
                       SeedMapper.stableTransactionID(sourceID: "legacy-row-9"))
        var expense = movement("expense", row: 1).transaction
        expense.kind = .expense
        expense.currency = "EUR"
        expense.amountMinor = 1_000
        expense.eurMinor = 1_000
        expense.personalExpenseEURMinor = 1_000
        var advance = movement("advance", row: 2).transaction
        advance.eurMinor = 2_000
        advance.personalExpenseEURMinor = 0
        var refund = movement("refund", row: 3).transaction
        refund.kind = .reimbursement
        refund.eurMinor = 300
        refund.personalExpenseEURMinor = -300
        var pac = movement("pac", row: 4).transaction
        pac.kind = .pacInvestment
        pac.eurMinor = 3_000
        var income = movement("income", row: 5).transaction
        income.kind = .income
        income.eurMinor = 4_000
        var deposit = movement("deposit", row: 6).transaction
        deposit.kind = .deposit
        deposit.eurMinor = 5_000
        var depositRefund = movement("deposit-refund", row: 7).transaction
        depositRefund.kind = .depositRefund
        depositRefund.eurMinor = 5_000
        let totals = LedgerTotals(transactions: [expense, advance, refund, pac, income, deposit, depositRefund])
        XCTAssertEqual(totals.personalSpendingEURMinor, 700)
        XCTAssertEqual(totals.totalExpensesEURMinor, 1_000)
        XCTAssertEqual(totals.incomeEURMinor, 4_000)
        XCTAssertEqual(totals.pacInvestedEURMinor, 3_000)
    }

    func testIdempotentImportAndRollbackOnDuplicateSourceIdentity() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-import-unit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let invalidDatabase = try SQLiteDatabase(url: folder.appendingPathComponent("invalid.sqlite"))
        try invalidDatabase.seedDemoIfNeeded()
        let invalid = seed([movement("same-source", row: 9), movement("same-source", row: 10)], digest: "invalid")
        XCTAssertThrowsError(try invalidDatabase.importHistoricalSeed(invalid))
        XCTAssertEqual(try invalidDatabase.transactions().count, 3)
        XCTAssertTrue(try invalidDatabase.transactions().allSatisfy { $0.isDemo })
        XCTAssertEqual(try invalidDatabase.historicalCounts()["historical_imported_movements"], 0)
        XCTAssertEqual(try invalidDatabase.operations().count, 3)

        let database = try SQLiteDatabase(url: folder.appendingPathComponent("valid.sqlite"))
        try database.seedDemoIfNeeded()
        let valid = seed([movement("stable-source", row: 9)], digest: "stable")
        XCTAssertEqual(try database.importHistoricalSeed(valid).newMovements, 1)
        XCTAssertEqual(try database.importHistoricalSeed(valid).alreadyImported, 1)
        XCTAssertEqual(try database.transactions().count, 1)
        XCTAssertEqual(try database.transactions()[0].kind, .advanceForOthers)
        XCTAssertEqual(try database.transactions()[0].personalExpenseEURMinor, 0)
        XCTAssertEqual(try database.operations().count, 1)
        let changed = seed([movement("stable-source", row: 10)], digest: "changed")
        XCTAssertThrowsError(try database.importHistoricalSeed(changed))
        XCTAssertEqual(try database.transactions().count, 1)
    }

    func testSchemaTwoAllowsBuildFiveCurrenciesAndMissingEUR() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-seed-v2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("seed.sqlite")
        try makeSchemaTwoSeed(at: url)
        let seed = try SeedMapper(url: url).read(url: url)
        XCTAssertEqual(seed.schemaVersion, 2)
        XCTAssertEqual(seed.movements.count, 2)
        let usd = try XCTUnwrap(seed.movements.first { $0.transaction.currency == "USD" }?.transaction)
        XCTAssertNil(usd.eurMinor)
        XCTAssertNil(usd.eurValueSource)
        XCTAssertEqual(usd.accountAmountMinor, 1_234)
        XCTAssertEqual(usd.accountCurrency, "USD")
        let jpy = try XCTUnwrap(seed.movements.first { $0.transaction.currency == "JPY" }?.transaction)
        XCTAssertEqual(jpy.amountMinor, 1_250)
        XCTAssertEqual(jpy.eurMinor, 750)
        XCTAssertEqual(jpy.eurValueSource, .historical)
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle, "UPDATE migration_meta SET value='1' WHERE key='schema_version'", nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)
        XCTAssertEqual(try SeedMapper(url: url).read(url: url).schemaVersion, 1)
    }

    func testSchemaThreePreservesBuildFiveMetadataFromRawSQLiteIntoLedger() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-seed-v3-currency-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("seed.sqlite")
        try makeSchemaTwoSeed(at: url)
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
            throw NSError(domain: "seed-v3", code: 1)
        }
        let sql = """
        UPDATE migration_meta SET value='3' WHERE key='schema_version';
        CREATE TABLE reimbursement_reconciliations(
            link_id TEXT PRIMARY KEY, expense_source_id TEXT NOT NULL,
            expected_eur_minor INTEGER NOT NULL, receipt_source_id TEXT,
            received_eur_minor INTEGER NOT NULL, status TEXT NOT NULL, note TEXT);
        UPDATE movements SET exchange_rate_date='2026-01-02',
            exchange_rate_provider='Synthetic rates' WHERE id='jpy-historical';
        """
        let rc = sqlite3_exec(handle, sql, nil, nil, nil)
        var rawStatement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(handle, """
            SELECT eur_value_source,exchange_rate_date,exchange_rate_provider,
                   account_amount_minor,account_currency
            FROM movements WHERE id='jpy-historical'
            """, -1, &rawStatement, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_step(rawStatement), SQLITE_ROW)
        let rawSource = String(cString: sqlite3_column_text(rawStatement, 0))
        let rawDate = String(cString: sqlite3_column_text(rawStatement, 1))
        let rawProvider = String(cString: sqlite3_column_text(rawStatement, 2))
        let rawAccountAmount = sqlite3_column_int64(rawStatement, 3)
        let rawAccountCurrency = String(cString: sqlite3_column_text(rawStatement, 4))
        sqlite3_finalize(rawStatement)
        sqlite3_close(handle)
        XCTAssertEqual(rc, SQLITE_OK)

        let seed = try SeedMapper(url: url).read(url: url)
        XCTAssertEqual(seed.schemaVersion, 3)
        let sourceJPY = try XCTUnwrap(seed.movements.first { $0.transaction.sourceMovementID == "jpy-historical" }?.transaction)
        XCTAssertEqual(sourceJPY.eurValueSource?.rawValue, rawSource)
        XCTAssertEqual(sourceJPY.exchangeRateDate, rawDate)
        XCTAssertEqual(sourceJPY.exchangeRateProvider, rawProvider)
        XCTAssertEqual(sourceJPY.accountAmountMinor, rawAccountAmount)
        XCTAssertEqual(sourceJPY.accountCurrency, rawAccountCurrency)

        let db = try SQLiteDatabase(url: folder.appendingPathComponent("ledger.sqlite"))
        _ = try db.importHistoricalSeed(seed)
        let stored = try XCTUnwrap(db.transactions().first { $0.sourceMovementID == "jpy-historical" })
        XCTAssertEqual(stored.eurValueSource?.rawValue, rawSource)
        XCTAssertEqual(stored.exchangeRateDate, rawDate)
        XCTAssertEqual(stored.exchangeRateProvider, rawProvider)
        XCTAssertEqual(stored.accountAmountMinor, rawAccountAmount)
        XCTAssertEqual(stored.accountCurrency, rawAccountCurrency)
    }

    func testIncrementalAddChangeRemovalAndLocalEditProtection() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-incremental-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try SQLiteDatabase(url: folder.appendingPathComponent("ledger.sqlite"))
        try database.seedDemoIfNeeded()
        let first = movement("incremental-a", row: 2)
        XCTAssertEqual(try database.importHistoricalSeed(seed([first], digest: "v1")).newMovements, 1)
        XCTAssertEqual(try database.historicalImportPreview(seed([first], digest: "v1")).alreadyImported, 1)

        let second = movement("incremental-b", row: 3)
        XCTAssertEqual(try database.importHistoricalSeed(seed([first, second], digest: "v2")).newMovements, 1)
        XCTAssertEqual(try database.transactions().count, 2)
        let missing = try database.historicalImportPreview(seed([first], digest: "v3"))
        XCTAssertEqual(missing.missingFromSource, 1)
        _ = try database.importHistoricalSeed(seed([first], digest: "v3"))
        XCTAssertEqual(try database.transactions().count, 2)

        var changed = movement("incremental-a", row: 8)
        changed.transaction.note = "Updated synthetic source"
        let changedSeed = seed([changed], digest: "v4")
        let sourceConflict = try XCTUnwrap(database.historicalImportPreview(changedSeed).rowConflicts.first)
        XCTAssertTrue(sourceConflict.canApplySource)
        _ = try database.importHistoricalSeed(changedSeed, decisions: [sourceConflict.id: .applySource])
        var local = try XCTUnwrap(database.transactions().first { $0.sourceMovementID == "incremental-a" })
        XCTAssertEqual(local.note, "Updated synthetic source")
        local.note = "User correction must win"
        _ = try database.save(local)

        var changedAgain = movement("incremental-a", row: 9)
        changedAgain.transaction.note = "Later source change"
        let protectedSeed = seed([changedAgain], digest: "v5")
        let protected = try XCTUnwrap(database.historicalImportPreview(protectedSeed).rowConflicts.first)
        XCTAssertTrue(protected.localEdited)
        XCTAssertFalse(protected.canApplySource)
        XCTAssertThrowsError(try database.importHistoricalSeed(protectedSeed,
            decisions: [protected.id: .applySource]))
        _ = try database.importHistoricalSeed(protectedSeed, decisions: [protected.id: .keepLocal])
        XCTAssertEqual(try database.transactions().first { $0.sourceMovementID == "incremental-a" }?.note,
                       "User correction must win")
    }

    func testPossibleManualAndNotificationDuplicatesRequireExplicitSkipOrSeparate() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-duplicate-review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try SQLiteDatabase(url: folder.appendingPathComponent("ledger.sqlite"))
        var manual = movement("unused", row: 1).transaction
        manual.id = UUID(); manual.sourceMovementID = nil; manual.sourceSheet = nil; manual.sourceRow = nil
        _ = try database.save(manual)
        var notified = manual
        notified.id = UUID(); notified.sourceEventID = UUID(); notified.merchant = "Synthetic notification duplicate"
        _ = try database.save(notified)

        var incomingManual = movement("incoming-manual", row: 2)
        incomingManual.transaction.merchant = manual.merchant
        var incomingNotification = movement("incoming-notification", row: 3)
        incomingNotification.transaction.merchant = notified.merchant
        let incoming = seed([incomingManual, incomingNotification], digest: "duplicates")
        let preview = try database.historicalImportPreview(incoming)
        XCTAssertEqual(preview.duplicateCandidates.count, 2)
        XCTAssertThrowsError(try database.importHistoricalSeed(incoming))
        let skip = Dictionary(uniqueKeysWithValues: preview.duplicateCandidates.map { ($0.id, HistoricalImportDecision.skipIncoming) })
        _ = try database.importHistoricalSeed(incoming, decisions: skip)
        XCTAssertEqual(try database.transactions().count, 2)
        let again = try database.historicalImportPreview(incoming)
        let separate = Dictionary(uniqueKeysWithValues: again.duplicateCandidates.map { ($0.id, HistoricalImportDecision.importSeparately) })
        _ = try database.importHistoricalSeed(incoming, decisions: separate)
        XCTAssertEqual(try database.transactions().count, 4)
        XCTAssertEqual(try database.historicalCounts()["historical_imported_movements"], 2)
    }

    func testImportedMulticurrencyIdentitySurvivesBackupReplaceMergeAndReopen() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-import-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try SQLiteDatabase(url: folder.appendingPathComponent("source.sqlite"))
        try source.seedDemoIfNeeded()
        var foreign = movement("backup-usd", row: 2)
        foreign.transaction.currency = "USD"
        foreign.transaction.amountMinor = 1_234
        foreign.transaction.eurMinor = nil
        foreign.transaction.eurValueSource = nil
        foreign.transaction.exchangeRateEUR = nil
        foreign.transaction.personalExpenseEURMinor = nil
        foreign.transaction.recoverableEURMinor = nil
        foreign.transaction.accountAmountMinor = 1_234
        foreign.transaction.accountCurrency = "USD"
        let historicalAccount = HistoricalAccount(sourceName: "Synthetic USD account", kind: "bank",
            currency: "USD", openingAt: nil, openingEURMinor: nil, isActive: true, note: nil,
            sourceSheet: "Accounts", sourceRow: 2, cellValuesJSON: "{}")
        foreign.transaction.account = historicalAccount.sourceName
        _ = try source.importHistoricalSeed(seed([foreign], digest: "backup", accounts: [historicalAccount]))
        XCTAssertEqual(try source.localAccounts().first { $0.name == historicalAccount.sourceName }?.nativeCurrency,
                       "USD")
        let backup = try source.exportBackup()
        let targetURL = folder.appendingPathComponent("target.sqlite")
        let target = try SQLiteDatabase(url: targetURL)
        try target.seedDemoIfNeeded()
        _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .replace)
        let restored = try XCTUnwrap(SQLiteDatabase(url: targetURL).transactions().first)
        XCTAssertEqual(restored.sourceMovementID, "backup-usd")
        XCTAssertEqual(restored.currency, "USD")
        XCTAssertNil(restored.eurMinor)
        _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .merge)
        XCTAssertEqual(try target.transactions().count, 1)
        try target.checkDatabase()
    }

    func testSeedThreeImportsCrossAccountAdvanceReimbursementIdempotently() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-seed-reimbursement-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try SQLiteDatabase(url: folder.appendingPathComponent("ledger.sqlite"))
        var advance = movement("advance-source", row: 10)
        advance.transaction.kind = .advanceForOthers
        advance.transaction.account = "Synthetic source account"
        advance.transaction.currency = "EUR"
        advance.transaction.amountMinor = 1_500
        advance.transaction.eurMinor = 1_500
        advance.transaction.personalExpenseEURMinor = 0
        advance.transaction.recoverableEURMinor = 1_500
        var receipt = movement("receipt-source", row: 11)
        receipt.transaction.kind = .reimbursement
        receipt.transaction.account = "Synthetic destination account"
        receipt.transaction.currency = "EUR"
        receipt.transaction.amountMinor = 1_500
        receipt.transaction.eurMinor = 1_500
        receipt.transaction.personalExpenseEURMinor = -1_500
        receipt.transaction.recoverableEURMinor = 0
        let reconciliation = HistoricalReimbursementReconciliation(linkID: "synthetic-link",
            expenseSourceID: "advance-source", expectedEURMinor: 1_500,
            receiptSourceID: "receipt-source", receivedEURMinor: 1_500,
            status: "received", note: nil)
        let historical = seed([advance, receipt], digest: "reimbursement-v3",
                              reimbursements: [reconciliation])
        _ = try database.importHistoricalSeed(historical)
        XCTAssertEqual(try database.reimbursementStatuses().first?.outstandingEURMinor, 0)
        XCTAssertEqual(try database.reimbursementLinks().count, 1)
        XCTAssertEqual(LedgerTotals(transactions: try database.transactions()).personalSpendingEURMinor, 0)
        let repeated = try database.importHistoricalSeed(historical)
        XCTAssertEqual(repeated.newMovements, 0)
        XCTAssertEqual(try database.transactions().count, 2)
        XCTAssertEqual(try database.reimbursementLinks().count, 1)
    }

    private func movement(_ sourceID: String, row: Int) -> ImportedMovement {
        var item = Transaction(id: UUID(), kind: .advanceForOthers, amountMinor: 1_500,
                               currency: "CNY", merchant: "Synthetic advance", account: "Synthetic account",
                               category: "Synthetic", note: "", occurredAt: Date(timeIntervalSince1970: 0),
                               updatedAt: .now, deletedAt: nil, isDemo: false, revision: 1, sourceEventID: nil)
        item.sourceMovementID = sourceID
        item.sourceSheet = "SYNTHETIC"
        item.sourceRow = row
        item.eurMinor = 190
        item.personalExpenseEURMinor = 0
        item.recoverableEURMinor = 190
        return ImportedMovement(transaction: item, sourceFingerprint: "fingerprint-\(row)", sourcePayloadJSON: "{}")
    }

    private func seed(_ movements: [ImportedMovement], digest: String,
                      accounts: [HistoricalAccount] = [],
                      reimbursements: [HistoricalReimbursementReconciliation] = []) -> ValidatedSeed {
        ValidatedSeed(schemaVersion: reimbursements.isEmpty ? 2 : 3, digest: digest,
                      movements: movements, accounts: accounts, trips: [], rules: [],
                      rates: [], sourceRows: [], warnings: [], reimbursements: reimbursements,
                      unmatchedAccountLabels: 0, missingAccountLabels: 0)
    }

    private func makeSchemaTwoSeed(at url: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else { throw NSError(domain: "seed", code: 1) }
        defer { sqlite3_close(handle) }
        let sql = """
        CREATE TABLE migration_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);
        INSERT INTO migration_meta VALUES('schema_version','2');
        CREATE TABLE movements(id TEXT PRIMARY KEY,occurred_at TEXT,amount_minor INTEGER,currency TEXT,eur_minor INTEGER,exchange_rate_eur TEXT,description TEXT,kind TEXT,category TEXT,subcategory TEXT,account TEXT,trip_id TEXT,paid_by TEXT,affects_my_accounts INTEGER,personal_expense_eur_minor INTEGER,recoverable_eur_minor INTEGER,needs_review INTEGER,review_reason TEXT,origin TEXT,entered_at TEXT,note TEXT,home_type TEXT,source_sheet TEXT,source_row INTEGER,source_technical_id TEXT,cached_personal_value TEXT,import_fingerprint TEXT,eur_value_source TEXT,exchange_rate_date TEXT,exchange_rate_provider TEXT,account_amount_minor INTEGER,account_currency TEXT);
        CREATE TABLE accounts(name TEXT PRIMARY KEY,kind TEXT,currency TEXT,opening_at TEXT,opening_eur_minor INTEGER,is_active INTEGER,note TEXT,source_sheet TEXT,source_row INTEGER,cell_values_json TEXT);
        CREATE TABLE trips(id TEXT PRIMARY KEY,name TEXT,destination TEXT,starts_at TEXT,ends_at TEXT,currency TEXT,note TEXT,source_sheet TEXT,source_row INTEGER,cell_values_json TEXT);
        CREATE TABLE recurring_rules(id TEXT PRIMARY KEY,rule_kind TEXT,name TEXT,amount_minor INTEGER,currency TEXT,frequency TEXT,nominal_day INTEGER,starts_at TEXT,ends_at TEXT,account TEXT,is_active INTEGER,investment_kind TEXT,date_rule TEXT,initial_contribution_minor INTEGER,initial_contribution_at TEXT,note TEXT,source_sheet TEXT,source_row INTEGER,cell_values_json TEXT);
        CREATE TABLE exchange_rates(source_row INTEGER PRIMARY KEY,date TEXT,currency TEXT,eur_rate TEXT,status TEXT,origin TEXT,source_key TEXT,cell_values_json TEXT);
        CREATE TABLE source_rows(source_sheet TEXT,source_row INTEGER,cell_values_json TEXT,PRIMARY KEY(source_sheet,source_row));
        CREATE TABLE migration_warnings(source_sheet TEXT,source_row INTEGER,code TEXT,detail TEXT,PRIMARY KEY(source_sheet,source_row,code));
        INSERT INTO source_rows VALUES('Synthetic',2,'{}'),('Synthetic',3,'{}');
        INSERT INTO movements(id,occurred_at,amount_minor,currency,description,kind,account,source_sheet,source_row,import_fingerprint,account_amount_minor,account_currency)
        VALUES('usd-no-eur','2026-01-01T12:00:00',1234,'USD','Synthetic USD','Spesa','USD account','Synthetic',2,'usd-fingerprint',1234,'USD');
        INSERT INTO movements(id,occurred_at,amount_minor,currency,eur_minor,exchange_rate_eur,description,kind,account,source_sheet,source_row,import_fingerprint,eur_value_source,account_amount_minor,account_currency)
        VALUES('jpy-historical','2026-01-02T12:00:00',1250,'JPY',750,'0.006','Synthetic JPY','Entrata','JPY account','Synthetic',3,'jpy-fingerprint','historical',1250,'JPY');
        """
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "seed", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(handle))])
        }
    }
}
