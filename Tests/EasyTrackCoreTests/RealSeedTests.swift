import Foundation
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
        XCTAssertEqual(try database.historicalCounts()["historical_imported_movements"], mapped.movements.count)
        XCTAssertEqual(try database.historicalCounts()["historical_accounts"], mapped.accounts.count)
        XCTAssertEqual(try database.historicalCounts()["historical_trips"], mapped.trips.count)
        XCTAssertEqual(try database.historicalCounts()["historical_recurring_rules"], mapped.rules.count)

        let backup = try XCTUnwrap(database.historicalBackup())
        XCTAssertEqual(backup.provenance.count, mapped.movements.count)
        XCTAssertEqual(backup.sourceRows.count, mapped.sourceRows.count)

        let repeatImport = try database.importHistoricalSeed(mapped)
        XCTAssertEqual(repeatImport.newMovements, 0)
        XCTAssertEqual(repeatImport.alreadyImported, mapped.movements.count)
    }
}
