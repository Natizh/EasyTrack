import Foundation
import SQLite3
import XCTest
@testable import EasyTrackCore

final class DashboardPreferencesTests: XCTestCase {
    private func withDatabase(_ body: (SQLiteDatabase, URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyTrack-dashboard-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("ledger.sqlite")
        try body(SQLiteDatabase(url: url), url)
    }

    private func preference(_ id: String, _ position: Int, _ visible: Bool) -> DashboardWidgetPreference {
        DashboardWidgetPreference(widgetID: id, position: position,
                                  isVisible: visible, updatedAt: Date(timeIntervalSince1970: 100))
    }

    func testDefaultOrderHiddenReorderedUnknownAndNewWidgetsResolveSafely() {
        let defaults = ["monthly", "categories", "recurring", "daily"]
        XCTAssertEqual(DashboardWidgetPreferenceResolver.resolve(
            availableIDs: defaults, defaultOrder: defaults, preferences: []),
            defaults.map { ResolvedDashboardWidget(widgetID: $0, isVisible: true) })

        let configured = [preference("daily", 0, true), preference("unknown.future", 1, true),
                          preference("monthly", 2, false), preference("categories", 3, true)]
        XCTAssertEqual(DashboardWidgetPreferenceResolver.resolve(
            availableIDs: defaults, defaultOrder: defaults, preferences: configured), [
                ResolvedDashboardWidget(widgetID: "daily", isVisible: true),
                ResolvedDashboardWidget(widgetID: "monthly", isVisible: false),
                ResolvedDashboardWidget(widgetID: "categories", isVisible: true),
                ResolvedDashboardWidget(widgetID: "recurring", isVisible: true)
            ])
    }

    func testPersistenceReopenResetAndFinancialRowsRemainUnchanged() throws {
        try withDatabase { database, url in
            try database.seedDemoIfNeeded()
            let transactions = try database.transactions()
            let totals = LedgerTotals(transactions: transactions)
            let preferences = [preference("dailySpending", 0, false),
                               preference("monthlyTrend", 1, true)]
            try database.saveDashboardWidgetPreferences(preferences)
            XCTAssertEqual(try database.dashboardWidgetPreferences(), preferences)

            let reopened = try SQLiteDatabase(url: url)
            XCTAssertEqual(try reopened.dashboardWidgetPreferences(), preferences)
            XCTAssertEqual(try reopened.transactions(), transactions)
            XCTAssertEqual(LedgerTotals(transactions: try reopened.transactions()), totals)
            try reopened.resetDashboardWidgetPreferences()
            XCTAssertTrue(try reopened.dashboardWidgetPreferences().isEmpty)
        }
    }

    func testSchemaSixMigratesAtomicallyToCurrent() throws {
        try withDatabase { database, url in
            try database.execute("DROP TABLE dashboard_widget_preferences")
            try database.execute("PRAGMA user_version=6")
            let reopened = try SQLiteDatabase(url: url)
            XCTAssertTrue(try reopened.dashboardWidgetPreferences().isEmpty)
            let version = try reopened.statement("PRAGMA user_version")
            defer { sqlite3_finalize(version) }
            XCTAssertEqual(sqlite3_step(version), SQLITE_ROW)
            XCTAssertEqual(sqlite3_column_int(version, 0), 10)
        }
    }

    func testBackupReplaceMergeAndVersionSevenCompatibility() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyTrack-dashboard-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try SQLiteDatabase(url: folder.appendingPathComponent("source.sqlite"))
        let targetURL = folder.appendingPathComponent("target.sqlite")
        let target = try SQLiteDatabase(url: targetURL)
        try source.seedDemoIfNeeded()
        try target.seedDemoIfNeeded()
        let sourcePreferences = [preference("monthlyTrend", 0, false), preference("recurring", 1, true)]
        try source.saveDashboardWidgetPreferences(sourcePreferences)
        let backup = try source.exportBackup()
        XCTAssertEqual(backup.schemaVersion, 11)
        XCTAssertEqual(backup.databaseSchemaVersion, 10)

        _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .replace)
        XCTAssertEqual(try target.dashboardWidgetPreferences(), sourcePreferences)

        let localPreferences = [preference("dailySpending", 0, true),
                                preference("unknown.future", 1, false)]
        try target.saveDashboardWidgetPreferences(localPreferences)
        _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .merge)
        XCTAssertEqual(try target.dashboardWidgetPreferences(), localPreferences)

        let oldTables = Array(backup.tables.prefix(25))
        let old = BackupArchive(schemaVersion: 7, databaseSchemaVersion: 6,
            exportID: UUID(), exportedAt: .now,
            contentSHA256: try SQLiteDatabase.digest(oldTables), tables: oldTables,
            sourceFormatVersion: nil)
        let upgraded = try BackupArchive.decode(JSONEncoder().encode(old))
        XCTAssertEqual(upgraded.schemaVersion, 11)
        XCTAssertEqual(upgraded.sourceFormatVersion, 7)
        let legacyTargetURL = folder.appendingPathComponent("legacy-target.sqlite")
        let legacyTarget = try SQLiteDatabase(url: legacyTargetURL)
        _ = try legacyTarget.seedDemoIfNeeded()
        try legacyTarget.saveDashboardWidgetPreferences(localPreferences)
        _ = try legacyTarget.restoreBackup(upgraded, preview: legacyTarget.previewBackup(upgraded), mode: .replace)
        XCTAssertTrue(try SQLiteDatabase(url: legacyTargetURL).dashboardWidgetPreferences().isEmpty)
    }
}
