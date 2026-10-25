import Foundation
import SQLite3
import XCTest
@testable import EasyTrackCore

final class MerchantAnalyticsTests: XCTestCase {
    private func merchant(_ key: String, _ name: String, _ amount: Int64, _ count: Int,
                          _ ids: [UUID]) -> FinancialMerchantAggregate {
        FinancialMerchantAggregate(key: key, name: name, transactionCount: count,
            personalNetExpensesEURMinor: amount, transactionIDs: ids)
    }

    func testDeterministicSuggestionsRequireExactBaseAndApprovedGroupingPreservesProvenance() throws {
        let firstID = UUID(), secondID = UUID(), unrelatedID = UUID()
        let raw = [
            merchant("fictional cafe 1234", "Fictional Cafe 1234", 500, 1, [firstID]),
            merchant("fictional cafe 9876", "Fictional Cafe 9876", -100, 1, [secondID]),
            merchant("fictional market", "Fictional Market", 900, 2, [unrelatedID])
        ]
        let suggestions = MerchantAnalytics.suggestions(from: raw, aliases: [])
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions[0].canonicalName, "Fictional Cafe")
        XCTAssertEqual(Set(suggestions[0].memberKeys), ["fictional cafe 1234", "fictional cafe 9876"])

        let group = MerchantAliasGroup(id: UUID(), canonicalName: "Fictional Cafe",
            memberKeys: suggestions[0].memberKeys, createdAt: .now, updatedAt: .now)
        let grouped = try MerchantAnalytics.grouped(raw, aliases: [group])
        let approved = try XCTUnwrap(grouped.first { $0.name == "Fictional Cafe" })
        XCTAssertEqual(approved.personalNetExpensesEURMinor, 400)
        XCTAssertEqual(approved.transactionCount, 2)
        XCTAssertEqual(Set(approved.transactionIDs), [firstID, secondID])
        XCTAssertEqual(raw[0].name, "Fictional Cafe 1234")
        XCTAssertEqual(grouped.first { $0.name == "Fictional Market" }?.transactionIDs, [unrelatedID])
    }

    func testPersistenceUndoMigrationBackupReplaceMergeAndVersionEightCompatibility() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyTrack-merchant-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sourceURL = folder.appendingPathComponent("source.sqlite")
        let source = try SQLiteDatabase(url: sourceURL)
        try source.seedDemoIfNeeded()
        let now = Date(timeIntervalSince1970: 100)
        let sourceGroup = MerchantAliasGroup(id: UUID(), canonicalName: "Fictional Cafe",
            memberKeys: ["fictional cafe 1", "fictional cafe 2"], createdAt: now, updatedAt: now)
        try source.saveMerchantAliasGroup(sourceGroup)
        XCTAssertEqual(try SQLiteDatabase(url: sourceURL).merchantAliasGroups(), [sourceGroup])

        let backup = try source.exportBackup()
        XCTAssertEqual(backup.schemaVersion, 9)
        XCTAssertEqual(backup.databaseSchemaVersion, 8)
        let targetURL = folder.appendingPathComponent("target.sqlite")
        let target = try SQLiteDatabase(url: targetURL)
        try target.seedDemoIfNeeded()
        _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .replace)
        XCTAssertEqual(try target.merchantAliasGroups(), [sourceGroup])

        let localGroup = MerchantAliasGroup(id: UUID(), canonicalName: "Local Market",
            memberKeys: ["local market 1", "local market 2"], createdAt: now, updatedAt: now)
        try target.deleteMerchantAliasGroup(sourceGroup.id)
        try target.saveMerchantAliasGroup(localGroup)
        _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .merge)
        XCTAssertEqual(try target.merchantAliasGroups(), [localGroup])
        try target.deleteMerchantAliasGroup(localGroup.id)
        XCTAssertTrue(try target.merchantAliasGroups().isEmpty)

        let oldTables = Array(backup.tables.dropLast())
        let old = BackupArchive(schemaVersion: 8, databaseSchemaVersion: 7,
            exportID: UUID(), exportedAt: .now,
            contentSHA256: try SQLiteDatabase.digest(oldTables), tables: oldTables,
            sourceFormatVersion: nil)
        let upgraded = try BackupArchive.decode(JSONEncoder().encode(old))
        XCTAssertEqual(upgraded.schemaVersion, 9)
        XCTAssertEqual(upgraded.sourceFormatVersion, 8)
        XCTAssertTrue(upgraded.tables.last?.rows.isEmpty == true)

        let migrationURL = folder.appendingPathComponent("migration.sqlite")
        let migration = try SQLiteDatabase(url: migrationURL)
        try migration.execute("DROP TABLE merchant_alias_groups")
        try migration.execute("PRAGMA user_version=7")
        XCTAssertTrue(try SQLiteDatabase(url: migrationURL).merchantAliasGroups().isEmpty)
    }
}
