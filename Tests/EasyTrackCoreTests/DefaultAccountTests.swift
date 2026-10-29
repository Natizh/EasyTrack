import Foundation
import XCTest
@testable import EasyTrackCore

final class DefaultAccountTests: XCTestCase {
    func testChooseRenameArchiveNoneAndReopen() throws {
        try withDatabase { database, url in
            let first = try database.saveLocalAccount(account("Primary", currency: "USD"))
            let second = try database.saveLocalAccount(account("Secondary", currency: "EUR"))
            try database.setDefaultExpenseAccountID(first.id)
            XCTAssertEqual(try SQLiteDatabase(url: url).defaultExpenseAccountID(), first.id)
            var renamed = first; renamed.name = "Primary renamed"
            _ = try database.saveLocalAccount(renamed)
            XCTAssertEqual(try database.defaultExpenseAccountID(), first.id)
            try database.setDefaultExpenseAccountID(second.id)
            XCTAssertEqual(try database.defaultExpenseAccountID(), second.id)
            try database.setDefaultExpenseAccountID(nil)
            XCTAssertNil(try database.defaultExpenseAccountID())
            try database.setDefaultExpenseAccountID(first.id)
            renamed = try XCTUnwrap(database.localAccounts().first { $0.id == first.id })
            renamed.archivedAt = .now
            _ = try database.saveLocalAccount(renamed)
            XCTAssertNil(try database.defaultExpenseAccountID())
        }
    }

    func testPrefillPrecedenceNativeCurrencyAndMissingDefault() throws {
        let active = account("Active", currency: "USD")
        var archived = account("Archived", currency: "GBP"); archived.archivedAt = .now
        let original = Transaction(id: UUID(), kind: .expense, amountMinor: 123, currency: "EUR",
            merchant: "Synthetic", account: active.name, category: "", note: "", occurredAt: .now,
            updatedAt: .now, deletedAt: nil, isDemo: false, revision: 1, sourceEventID: nil,
            accountID: active.id)
        XCTAssertEqual(TransactionAccountPrefill.resolve(original: original, explicitAccountID: archived.id,
            defaultAccountID: archived.id, accounts: [active, archived])?.id, active.id)
        XCTAssertEqual(TransactionAccountPrefill.resolve(original: nil, explicitAccountID: active.id,
            defaultAccountID: archived.id, accounts: [active, archived])?.nativeCurrency, "USD")
        XCTAssertNil(TransactionAccountPrefill.resolve(original: nil, explicitAccountID: nil,
            defaultAccountID: archived.id, accounts: [active, archived]))
        XCTAssertNil(TransactionAccountPrefill.resolve(original: nil, explicitAccountID: nil,
            defaultAccountID: UUID(), accounts: [active]))
    }

    func testBackupReplaceAndMergeKeepExpectedDefaultPolicy() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-default-account-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try SQLiteDatabase(url: folder.appendingPathComponent("source.sqlite"))
        try source.seedDemoIfNeeded()
        let first = try source.saveLocalAccount(account("First", currency: "USD"))
        let second = try source.saveLocalAccount(account("Second", currency: "EUR"))
        try source.setDefaultExpenseAccountID(first.id)
        let backup = try source.exportBackup()

        let targetURL = folder.appendingPathComponent("target.sqlite")
        let target = try SQLiteDatabase(url: targetURL)
        try target.seedDemoIfNeeded()
        _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .replace)
        XCTAssertEqual(try target.defaultExpenseAccountID(), first.id)
        try target.setDefaultExpenseAccountID(second.id)
        _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .merge)
        XCTAssertEqual(try SQLiteDatabase(url: targetURL).defaultExpenseAccountID(), second.id)

        try target.execute("DELETE FROM metadata WHERE key='preference.defaultExpenseAccountID'")
        _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .merge)
        XCTAssertEqual(try SQLiteDatabase(url: targetURL).defaultExpenseAccountID(), first.id)
    }

    private func account(_ name: String, currency: String) -> LocalAccount {
        LocalAccount(id: UUID(), name: name, createdAt: .now, nativeCurrency: currency)
    }

    private func withDatabase(_ body: (SQLiteDatabase, URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-default-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("ledger.sqlite")
        try body(SQLiteDatabase(url: url), url)
    }
}
