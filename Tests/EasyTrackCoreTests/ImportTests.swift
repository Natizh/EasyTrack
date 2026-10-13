import Foundation
import XCTest
@testable import EasyTrackCore

final class ImportTests: XCTestCase {
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

    private func seed(_ movements: [ImportedMovement], digest: String) -> ValidatedSeed {
        ValidatedSeed(schemaVersion: 1, digest: digest, movements: movements, accounts: [], trips: [], rules: [],
                      rates: [], sourceRows: [], warnings: [], unmatchedAccountLabels: 0, missingAccountLabels: 0)
    }
}
