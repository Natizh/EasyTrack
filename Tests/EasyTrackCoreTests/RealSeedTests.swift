import Foundation
import SQLite3
import XCTest
@testable import EasyTrackCore

final class RealSeedTests: XCTestCase {
    func testExternalSeedMappingAndRepeatableImportWhenAvailable() throws {
        guard let path = ProcessInfo.processInfo.environment["EASYTRACK_SEED_PATH"] else {
            throw XCTSkip("Set EASYTRACK_SEED_PATH to run the external seed verification")
        }
        let source = URL(fileURLWithPath: path)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-real-seed-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let staged = folder.appendingPathComponent("staged.sqlite")
        let stagedAgain = folder.appendingPathComponent("staged-again.sqlite")
        try SeedImportCoordinator.snapshotSQLite(from: source, to: staged)
        try SeedImportCoordinator.snapshotSQLite(from: source, to: stagedAgain)
        let mapped = try SeedMapper(url: staged).read(url: staged)
        XCTAssertEqual(mapped.digest, try SeedMapper(url: stagedAgain).read(url: stagedAgain).digest)
        XCTAssertEqual(mapped.schemaVersion, 1)
        XCTAssertEqual(mapped.movements.count, 2_881)
        XCTAssertEqual(mapped.accounts.count, 3)
        XCTAssertEqual(mapped.trips.count, 10)
        XCTAssertEqual(mapped.rules.count, 11)
        XCTAssertEqual(mapped.rates.count, 303)
        XCTAssertEqual(mapped.sourceRows.count, 2_881)
        XCTAssertEqual(mapped.warnings.count, 254)
        XCTAssertEqual(mapped.unmatchedAccountLabels, 2_573)
        XCTAssertEqual(mapped.missingAccountLabels, 51)
        XCTAssertEqual(mapped.movements.filter { $0.transaction.kind == .pacInvestment }.count, 118)
        XCTAssertEqual(mapped.movements.filter { $0.transaction.kind == .advanceForOthers }.count, 8)
        XCTAssertEqual(mapped.movements.filter { $0.transaction.kind == .reimbursement }.count, 2)

        let database = try SQLiteDatabase(url: folder.appendingPathComponent("local.sqlite"))
        try database.seedDemoIfNeeded()
        XCTAssertEqual(try database.transactions().count, 3)
        let first = try database.historicalImportPreview(mapped)
        XCTAssertEqual(first.newMovements, 2_881)
        XCTAssertTrue(first.canImport)
        try database.importHistoricalSeed(mapped)
        let imported = try database.transactions()
        XCTAssertEqual(imported.count, 2_881)
        XCTAssertFalse(imported.contains { $0.isDemo })
        let importedBySource = Dictionary(uniqueKeysWithValues: imported.compactMap { item in
            item.sourceMovementID.map { ($0, item) }
        })
        XCTAssertTrue(mapped.movements.allSatisfy { movement in
            guard let importedItem = importedBySource[movement.transaction.sourceMovementID ?? ""] else { return false }
            return importedItem.kind == movement.transaction.kind &&
                importedItem.amountMinor == movement.transaction.amountMinor &&
                importedItem.currency == movement.transaction.currency &&
                importedItem.eurMinor == movement.transaction.eurMinor &&
                importedItem.personalExpenseEURMinor == movement.transaction.personalExpenseEURMinor &&
                importedItem.recoverableEURMinor == movement.transaction.recoverableEURMinor &&
                importedItem.sourceRow == movement.transaction.sourceRow
        })
        XCTAssertTrue(LedgerTotals(transactions: imported) == LedgerTotals(transactions: mapped.movements.map(\.transaction)))
        XCTAssertEqual(TransactionFilter(kind: .pacInvestment).apply(to: imported).count, 118)
        XCTAssertEqual(TransactionFilter(kind: .reimbursement).apply(to: imported).count, 2)
        XCTAssertEqual(TransactionFilter(currency: "CNY").apply(to: imported).count, 1_425)
        XCTAssertEqual(TransactionFilter(currency: "THB").apply(to: imported).count, 10)
        XCTAssertEqual(mapped.trips.reduce(0) { $0 + TransactionFilter(tripID: $1.id).apply(to: imported).count }, 561)
        XCTAssertEqual(try database.historicalCounts()["historical_imported_movements"], 2_881)
        XCTAssertEqual(try database.historicalCounts()["historical_accounts"], 3)
        XCTAssertEqual(try database.historicalCounts()["historical_trips"], 10)
        XCTAssertEqual(try database.historicalCounts()["historical_recurring_rules"], 11)
        XCTAssertEqual(try database.historicalCounts()["expected_occurrences"], 0)
        XCTAssertEqual(try database.historicalCounts()["historical_exchange_rates"], 303)
        let backup = try XCTUnwrap(database.historicalBackup())
        XCTAssertEqual(backup.provenance.count, 2_881)
        XCTAssertEqual(backup.sourceRows.count, 2_881)
        XCTAssertEqual(backup.importWarnings.count, 254)
        XCTAssertFalse(try JSONEncoder().encode(backup).isEmpty)
        let second = try database.importHistoricalSeed(mapped)
        XCTAssertEqual(second.newMovements, 0)
        XCTAssertEqual(second.alreadyImported, 2_881)
        XCTAssertEqual(try database.transactions().count, 2_881)
        XCTAssertEqual(try database.operations().count, 2_881)

        var edited = imported[0]
        let sourceID = edited.sourceMovementID
        let sourceRow = edited.sourceRow
        let sourceDate = edited.sourceOccurredAt
        let sourceRate = edited.exchangeRateEUR
        edited.merchant = "Local edited test description"
        edited.category = "Local edited test category"
        edited.note = "Local edit in temporary test database"
        edited.occurredAt = edited.occurredAt.addingTimeInterval(60)
        try database.save(edited)
        XCTAssertEqual(try database.importHistoricalSeed(mapped).newMovements, 0)
        let reopened = try database.transactions().first(where: { $0.id == edited.id })
        XCTAssertTrue(reopened?.merchant == edited.merchant)
        XCTAssertTrue(reopened?.category == edited.category)
        XCTAssertTrue(reopened?.note == edited.note)
        XCTAssertTrue(reopened?.occurredAt == edited.occurredAt)
        XCTAssertTrue(reopened?.sourceMovementID == sourceID)
        XCTAssertTrue(reopened?.sourceRow == sourceRow)
        XCTAssertTrue(reopened?.sourceOccurredAt == sourceDate)
        XCTAssertTrue(reopened?.exchangeRateEUR == sourceRate)
        XCTAssertEqual(try database.operations().count, 2_882)

        var mutationHandle: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(stagedAgain.path, &mutationHandle, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(mutationHandle, "UPDATE movements SET kind='Unfamiliar' WHERE source_row=9", nil, nil, nil), SQLITE_OK)
        sqlite3_close(mutationHandle)
        do {
            _ = try SeedMapper(url: stagedAgain).read(url: stagedAgain)
            XCTFail("An unfamiliar movement kind must be rejected")
        } catch SeedImportError.invalidRows(let issues) {
            XCTAssertTrue(issues.contains { $0.table == "movements" && $0.sourceRow == 9 })
        }
        XCTAssertEqual(try database.transactions().count, 2_881)
    }
}
