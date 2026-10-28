import SQLite3
import XCTest
@testable import EasyTrackCore

final class CurrencyTests: XCTestCase {
    private func temporaryDatabase(_ body: (URL, SQLiteDatabase) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-currency-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("ledger.sqlite")
        try body(url, SQLiteDatabase(url: url))
    }

    func testCurrencyExponentsAndDecimalConversion() throws {
        XCTAssertEqual(Money.parseMinor("123", currency: "JPY"), 123)
        XCTAssertNil(Money.parseMinor("123.00", currency: "JPY"))
        XCTAssertEqual(Money.parseMinor("12.345", currency: "KWD"), 12_345)
        XCTAssertEqual(Money.parseMinor("12,50", currency: "EUR"), 1_250)
        XCTAssertEqual(try CurrencyMath.eurMinor(originalMinor: 12_000, currency: "CNY",
                                                 eurPerUnit: Decimal(string: "0.12")!), 1_440)
    }

    func testForeignTransactionAccountChargePersistenceBackupAndConfirmedEURAuthority() throws {
        try temporaryDatabase { _, database in
            try database.seedDemoIfNeeded()
            var account = LocalAccount(id: UUID(), name: "Synthetic USD account", createdAt: .now)
            account.nativeCurrency = "USD"
            account = try database.saveLocalAccount(account)
            var item = Transaction(id: UUID(), kind: .expense, amountMinor: 12_000, currency: "CNY",
                merchant: "Synthetic merchant", account: account.name, category: "", note: "keep",
                occurredAt: .now, updatedAt: .now, deletedAt: nil, isDemo: false, revision: 0,
                sourceEventID: nil)
            item.accountID = account.id
            item.eurMinor = 1_580
            item.eurValueSource = .confirmed
            item.exchangeRateEUR = "0.12"
            item.exchangeRateDate = "2026-10-28"
            item.exchangeRateProvider = "Synthetic provider"
            item.accountAmountMinor = 1_400
            item.accountCurrency = "USD"
            item.personalExpenseEURMinor = 1_580
            item = try database.save(item)

            item.merchant = "Unrelated edit"
            item = try database.save(item)
            XCTAssertEqual(item.eurMinor, 1_580)
            XCTAssertEqual(item.eurValueSource, .confirmed)
            XCTAssertEqual(item.accountAmountMinor, 1_400)
            XCTAssertThrowsError(try {
                var changed = account; changed.nativeCurrency = "GBP"
                _ = try database.saveLocalAccount(changed)
            }())

            let backup = try database.exportBackup()
            XCTAssertEqual(backup.schemaVersion, 14)
            XCTAssertEqual(backup.databaseSchemaVersion, 13)
            let target = try SQLiteDatabase(url: database.url.deletingLastPathComponent()
                .appendingPathComponent("restored.sqlite"))
            _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .replace)
            let restored = try XCTUnwrap(target.transactions().first { $0.id == item.id })
            XCTAssertEqual(restored.currency, "CNY")
            XCTAssertEqual(restored.accountCurrency, "USD")
            XCTAssertEqual(restored.eurValueSource, .confirmed)
            XCTAssertEqual(try target.localAccounts().first { $0.id == account.id }?.nativeCurrency, "USD")
        }
    }
}
