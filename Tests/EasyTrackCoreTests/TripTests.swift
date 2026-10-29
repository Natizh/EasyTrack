import Foundation
import XCTest
@testable import EasyTrackCore

final class TripTests: XCTestCase {
    func testLocalAndImportedTripRenameKeepStableIdentityAndBackup() throws {
        try withDatabases { source, target, targetURL in
            try source.seedDemoIfNeeded()
            let local = try source.saveTrip(name: "Synthetic Local Trip")
            XCTAssertTrue(local.id.hasPrefix("local:"))
            let renamed = try source.saveTrip(id: local.id, name: "Synthetic Renamed Trip")
            XCTAssertEqual(renamed.id, local.id)
            XCTAssertEqual(try source.historicalTrips().first { $0.id == local.id }?.name,
                           "Synthetic Renamed Trip")

            try source.execute("""
                INSERT INTO historical_trips
                (id,name,destination,starts_at,ends_at,currency,note,source_sheet,source_row,cell_values_json)
                VALUES('imported-trip','Imported Name',NULL,NULL,NULL,NULL,NULL,'Trips',2,'{}')
                """)
            _ = try source.saveTrip(id: "imported-trip", name: "User Trip Name")
            try source.execute("UPDATE historical_trips SET name='Later Import Name' WHERE id='imported-trip'")
            XCTAssertEqual(try source.historicalTrips().first { $0.id == "imported-trip" }?.name,
                           "User Trip Name")

            let backup = try source.exportBackup()
            try target.seedDemoIfNeeded()
            _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .replace)
            let reopened = try SQLiteDatabase(url: targetURL)
            XCTAssertEqual(try reopened.historicalTrips().first { $0.id == local.id }?.name,
                           "Synthetic Renamed Trip")
            XCTAssertEqual(try reopened.historicalTrips().first { $0.id == "imported-trip" }?.name,
                           "User Trip Name")
            try reopened.checkDatabase()
        }
    }

    func testWholeTripAnalyticsUseExplicitIdentitySignedPersonalValuesAndFXCoverage() throws {
        let tripID = "local:trip-a"
        let otherTrip = "local:trip-b"
        let food = UUID(), travel = UUID()
        var first = transaction("Booking", .expense, 10_000, tripID, "2025-12-20")
        first.categoryID = travel; first.category = "Travel"; first.personalExpenseEURMinor = 7_500
        var second = transaction("Meal", .expense, 2_000, tripID, "2026-02-03")
        second.categoryID = food; second.category = "Food"; second.personalExpenseEURMinor = 2_000
        var refund = transaction("Meal refund", .reimbursement, 500, tripID, "2026-03-01")
        refund.categoryID = food; refund.category = "Food"; refund.personalExpenseEURMinor = -500
        var uncategorized = transaction("Taxi", .expense, 800, tripID, "2026-01-15")
        uncategorized.personalExpenseEURMinor = 800
        var missingFX = transaction("Foreign", .expense, 900, tripID, "2026-01-16")
        missingFX.currency = "USD"; missingFX.eurMinor = nil; missingFX.personalExpenseEURMinor = nil
        let income = transaction("Income", .income, 50_000, tripID, "2026-01-17")
        let pac = transaction("PAC", .pacInvestment, 20_000, tripID, "2026-01-18")
        let other = transaction("Other trip", .expense, 99_000, otherTrip, "2026-01-19")
        var deleted = transaction("Deleted", .expense, 1_000, tripID, "2026-01-20")
        deleted.deletedAt = .now

        let snapshot = try FinancialAnalytics.tripSnapshot(
            transactions: [first, second, refund, uncategorized, missingFX, income, pac, other, deleted],
            tripID: tripID, categoryNames: [food: "Food", travel: "Travel"])
        XCTAssertEqual(snapshot.personalNetEURMinor, 9_800)
        XCTAssertEqual(snapshot.categories.first { $0.categoryID == food }?.personalNetEURMinor, 1_500)
        XCTAssertEqual(snapshot.categories.first { $0.key == "uncategorized" }?.personalNetEURMinor, 800)
        XCTAssertEqual(snapshot.missingEURTransactionCount, 1)
        XCTAssertEqual(Set(snapshot.transactionIDs), Set([first.id, second.id, refund.id, uncategorized.id, missingFX.id]))
        XCTAssertFalse(snapshot.transactionIDs.contains(income.id))
        XCTAssertFalse(snapshot.transactionIDs.contains(pac.id))
    }

    private func transaction(_ merchant: String, _ kind: TransactionKind, _ amount: Int64,
                             _ tripID: String, _ day: String) -> Transaction {
        var item = Transaction(id: UUID(), kind: kind, amountMinor: amount, currency: "EUR",
            merchant: merchant, account: "Synthetic", category: "", note: "",
            occurredAt: ISO8601DateFormatter().date(from: "\(day)T12:00:00Z")!, updatedAt: .now,
            deletedAt: nil, isDemo: false, revision: 1, sourceEventID: nil)
        item.eurMinor = amount; item.tripID = tripID
        return item
    }

    private func withDatabases(_ body: (SQLiteDatabase, SQLiteDatabase, URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-trip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let targetURL = folder.appendingPathComponent("target.sqlite")
        try body(SQLiteDatabase(url: folder.appendingPathComponent("source.sqlite")),
                 SQLiteDatabase(url: targetURL), targetURL)
    }
}
