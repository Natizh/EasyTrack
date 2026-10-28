import Foundation
import SQLite3
import XCTest
@testable import EasyTrackCore

final class RealSeedTests: XCTestCase {
    func testExternalSeedImportAndReimportWhenAvailable() throws {
        guard let path = ProcessInfo.processInfo.environment["EASYTRACK_SEED_PATH"] else {
            throw XCTSkip("External import fixture not configured")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let snapshot = folder.appendingPathComponent("source.sqlite")
        try SeedImportCoordinator.snapshotSQLite(from: URL(fileURLWithPath: path), to: snapshot)
        let mapped = try SeedMapper(url: snapshot).read(url: snapshot)
        XCTAssertGreaterThan(mapped.movements.count, 0)

        let database = try SQLiteDatabase(url: folder.appendingPathComponent("ledger.sqlite"))
        try database.seedDemoIfNeeded()
        let preview = try database.historicalImportPreview(mapped)
        XCTAssertEqual(preview.newMovements, mapped.movements.count)
        XCTAssertTrue(preview.canImport)
        try database.importHistoricalSeed(mapped)

        let imported = try database.transactions()
        XCTAssertEqual(imported.count, mapped.movements.count)
        XCTAssertFalse(imported.contains { $0.isDemo })
        let importedBySource = Dictionary(uniqueKeysWithValues: imported.compactMap { item in
            item.sourceMovementID.map { ($0, item) }
        })
        XCTAssertTrue(mapped.movements.allSatisfy { movement in
            guard let sourceID = movement.transaction.sourceMovementID,
                  let importedItem = importedBySource[sourceID] else { return false }
            return importedItem.id == movement.transaction.id &&
                importedItem.kind == movement.transaction.kind &&
                importedItem.amountMinor == movement.transaction.amountMinor &&
                importedItem.currency == movement.transaction.currency &&
                importedItem.eurMinor == movement.transaction.eurMinor &&
                importedItem.personalExpenseEURMinor == movement.transaction.personalExpenseEURMinor &&
                importedItem.recoverableEURMinor == movement.transaction.recoverableEURMinor &&
                importedItem.sourceRow == movement.transaction.sourceRow
        })
        XCTAssertEqual(LedgerTotals(transactions: imported),
                       LedgerTotals(transactions: mapped.movements.map(\.transaction)))
        XCTAssertEqual(try database.historicalCounts()["historical_imported_movements"], mapped.movements.count)
        XCTAssertEqual(try database.historicalCounts()["historical_accounts"], mapped.accounts.count)
        XCTAssertEqual(try database.historicalCounts()["historical_trips"], mapped.trips.count)
        XCTAssertEqual(try database.historicalCounts()["historical_recurring_rules"], mapped.rules.count)

        let backup = try XCTUnwrap(database.historicalBackup())
        XCTAssertEqual(backup.provenance.count, mapped.movements.count)
        XCTAssertEqual(backup.sourceRows.count, mapped.sourceRows.count)
        XCTAssertFalse(try JSONEncoder().encode(backup).isEmpty)

        let repeatImport = try database.importHistoricalSeed(mapped)
        XCTAssertEqual(repeatImport.newMovements, 0)
        XCTAssertEqual(repeatImport.alreadyImported, mapped.movements.count)

        var edited = try XCTUnwrap(imported.first)
        let identity = (edited.sourceMovementID, edited.sourceRow, edited.sourceOccurredAt)
        edited.merchant = "Synthetic local edit"
        edited.note = "Synthetic verification"
        edited = try database.save(edited)
        XCTAssertEqual(try database.importHistoricalSeed(mapped).newMovements, 0)
        let reopened = try XCTUnwrap(database.transactions().first { $0.id == edited.id })
        XCTAssertEqual(reopened.merchant, edited.merchant)
        XCTAssertEqual(reopened.note, edited.note)
        XCTAssertEqual((reopened.sourceMovementID, reopened.sourceRow, reopened.sourceOccurredAt).0,
                       identity.0)
        XCTAssertEqual(reopened.sourceRow, identity.1)
        XCTAssertEqual(reopened.sourceOccurredAt, identity.2)

        let invalidSnapshot = folder.appendingPathComponent("invalid-kind.sqlite")
        try SeedImportCoordinator.snapshotSQLite(from: snapshot, to: invalidSnapshot)
        let sourceRow = try XCTUnwrap(mapped.movements.first?.transaction.sourceRow)
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(invalidSnapshot.path, &handle, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle,
            "UPDATE movements SET kind='SyntheticUnknownKind' WHERE source_row=\(sourceRow)",
            nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)
        XCTAssertThrowsError(try SeedMapper(url: invalidSnapshot).read(url: invalidSnapshot))
    }
}
