import Foundation
import XCTest
@testable import EasyTrackCore

final class BackupRestoreTests: XCTestCase {
    private func withDatabases(_ body: (SQLiteDatabase, SQLiteDatabase, URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-backup-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try SQLiteDatabase(url: folder.appendingPathComponent("source.sqlite"))
        let targetURL = folder.appendingPathComponent("target.sqlite")
        let second = try SQLiteDatabase(url: targetURL)
        try body(first, second, targetURL)
    }

    private func populate(_ database: SQLiteDatabase) throws -> (NotificationEvent, UUID) {
        try database.execute("INSERT INTO metadata VALUES ('demo_seeded','1')")
        let account = try database.saveLocalAccount(LocalAccount(id: UUID(), name: "Fictional checking", createdAt: .now))
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let event = try XCTUnwrap(NotificationEvent.make(sourceApp: "Northstar Pay (fictional)",
            title: "Card purchase", subtitle: "", message: "Paid €12,34 at Fictional Cafe",
            receivedAt: date, capturedAt: date))
        let attempt = try database.captureNotification(event)
        let sourceID = try XCTUnwrap(database.parserSources().first?.id)
        let source = try database.mapParserSource(sourceID, to: account.name)
        let rule = try database.saveParserRule(ParserRule(id: UUID(), sourceID: source.id, name: "Fictional format",
            enabled: true, priority: 1, version: 0, config: NotificationParser.suggest(for: event),
            createdAt: date, updatedAt: date, deletedAt: nil))
        let created = try database.processNotificationAttempt(attempt.id, preferredRuleID: rule.id)
        let parsedID = try XCTUnwrap(created.transactionID)

        var historical = Transaction(id: UUID(), kind: .expense, amountMinor: 875,
            currency: "EUR", merchant: "Fictional history", account: account.name, category: "",
            note: "", occurredAt: date, updatedAt: date, deletedAt: nil, isDemo: false,
            revision: 0, sourceEventID: nil)
        historical.accountID = account.id
        historical.sourceMovementID = "fictional-source-1"
        historical.sourceSheet = "Fictional movements"
        historical.sourceRow = 2
        _ = try database.save(historical)
        try database.execute("INSERT INTO historical_imported_movements VALUES ('fictional-source-1','\(historical.id.uuidString)','fictional-fingerprint','Fictional movements',2,'{}')")
        try database.execute("INSERT INTO historical_source_rows VALUES ('Fictional movements',2,'{}')")
        try database.execute("INSERT INTO historical_accounts(source_name,source_sheet,source_row,cell_values_json) VALUES ('Fictional checking','Fictional accounts',2,'{}')")
        try database.execute("INSERT INTO historical_trips(id,name,source_sheet,source_row,cell_values_json) VALUES ('fictional-trip','Fictional trip','Fictional trips',2,'{}')")
        try database.execute("INSERT INTO historical_recurring_rules(id,rule_kind,name,amount_minor,currency,source_sheet,source_row,cell_values_json) VALUES ('fictional-historical-rule','subscription','Fictional plan',875,'EUR','Fictional rules',2,'{}')")
        try database.execute("INSERT INTO expected_occurrences(id,rule_source_id,scheduled_at,matched_transaction_id,status) VALUES ('fictional-expected','fictional-historical-rule','2026-10-01','\(historical.id.uuidString)','matched')")
        try database.execute("INSERT INTO historical_exchange_rates(source_row,date,currency,eur_rate,cell_values_json) VALUES (2,'2026-10-01','EUR','1','{}')")
        try database.execute("INSERT INTO historical_import_warnings VALUES ('Fictional movements',2,'fictional-warning',NULL)")
        try database.execute("INSERT INTO metadata VALUES ('historical_import_digest','fictional-digest')")

        let recurring = RecurringRule(id: UUID(), name: "Fictional subscription", type: .subscription,
            amountMinor: 500, accountID: account.id, categoryID: nil,
            startDay: LocalDay(isoString: "2026-10-15")!, frequency: .monthly, nextIndex: 0,
            endDay: nil, timeZoneIdentifier: "Europe/Rome", isActive: true, note: "",
            createdAt: date, updatedAt: date, archivedAt: nil, revision: 0)
        _ = try database.saveRecurringRule(recurring)
        _ = try database.materializeDueRecurring(now: LocalDay(isoString: "2026-10-15")!.noon(in: TimeZone(identifier: "Europe/Rome")!)!)
        let occurrence = try XCTUnwrap(database.recurringOccurrences().first)
        _ = try database.recordExpectedRecurringNow(occurrence.id, now: date)
        try database.checkDatabase()
        return (event, parsedID)
    }

    private func legacyExport(_ database: SQLiteDatabase) throws -> Data {
        let rules = try database.parserRules(includeDeleted: true)
        let envelope = BackupEnvelope(schemaVersion: 5, exportID: UUID(), exportedAt: .now,
            transactions: try database.transactions(includeDeleted: true),
            notificationEvents: try database.notificationEvents(),
            operations: try database.operations(), historical: try database.historicalBackup(),
            parserSources: try database.parserSources(), parserRules: rules,
            localAccounts: try database.localAccounts(), ledgerCategories: try database.ledgerCategories(),
            recurringRules: try database.recurringRules(includeArchived: true),
            recurringOccurrences: try database.recurringOccurrences().map { current in
                RecurringOccurrence(id: current.id, ruleID: current.ruleID,
                                    scheduledDay: current.scheduledDay,
                                    status: current.transactionID == nil ? .skipped : .materialized,
                                    transactionID: current.transactionID, createdAt: current.createdAt)
            },
            parserRuleVersions: try rules.flatMap { try database.parserRuleHistory($0.id) },
            parserAttempts: try database.parserAttempts())
        return try JSONEncoder().encode(envelope)
    }

    func testVersionFiveExportConvertsAndRestoresWithRebuiltDeduplication() throws {
        try withDatabases { source, target, targetURL in
            let (event, _) = try populate(source)
            let archive = try BackupArchive.decode(legacyExport(source))
            XCTAssertEqual(archive.sourceFormatVersion, 5)
            let preview = try target.previewBackup(archive)
            XCTAssertEqual(preview.sourceFormatVersion, 5)
            _ = try target.restoreBackup(archive, preview: preview, mode: .replace)
            let reopened = try SQLiteDatabase(url: targetURL)
            XCTAssertEqual(try reopened.transactions().count, 3)
            XCTAssertEqual(try reopened.captureNotification(event).status, .duplicateIgnored)
            XCTAssertEqual(try reopened.historicalBackup()?.provenance.first?.sourceID, "fictional-source-1")
            XCTAssertEqual(try reopened.recurringOccurrences().count, 1)
            XCTAssertEqual(try reopened.parserRuleHistory(XCTUnwrap(reopened.parserRules().first?.id)).count, 1)
            try reopened.checkDatabase()
        }
    }

    func testVersionSixBackupUpgradesToCurrentWithoutChangingLegacyTotals() throws {
        try withDatabases { source, target, targetURL in
            _ = try populate(source)
            let before = LedgerTotals(transactions: try source.transactions())
            let current = try source.exportBackup()
            let olderTables = current.tables.prefix(22).map { table -> BackupTable in
                switch table.name {
                case "recurring_rules_local":
                    let index = table.columns.firstIndex(of: "review_window_days")!
                    return BackupTable(name: table.name,
                        columns: table.columns.enumerated().filter { $0.offset != index }.map(\.element),
                        rows: table.rows.map { row in row.enumerated().filter { $0.offset != index }.map(\.element) })
                case "recurring_occurrences_local":
                    let indexes = ["id", "rule_id", "scheduled_day", "status", "transaction_id", "created_at"]
                        .map { table.columns.firstIndex(of: $0)! }
                    return BackupTable(name: table.name, columns: ["id", "rule_id", "scheduled_day",
                        "status", "transaction_id", "created_at"], rows: table.rows.map { row in
                            var old = indexes.map { row[$0] }
                            old[3] = old[4] == nil ? "skipped" : "materialized"
                            return old
                        })
                default: return table
                }
            }
            let older = BackupArchive(schemaVersion: 6, databaseSchemaVersion: 5,
                exportID: UUID(), exportedAt: .now,
                contentSHA256: try SQLiteDatabase.digest(olderTables),
                tables: olderTables, sourceFormatVersion: nil)
            let converted = try BackupArchive.decode(JSONEncoder().encode(older))
            XCTAssertEqual(converted.schemaVersion, 10)
            XCTAssertEqual(converted.sourceFormatVersion, 6)
            let preview = try target.previewBackup(converted)
            XCTAssertEqual(preview.sourceFormatVersion, 6)
            _ = try target.restoreBackup(converted, preview: preview, mode: .replace)
            let reopened = try SQLiteDatabase(url: targetURL)
            XCTAssertEqual(LedgerTotals(transactions: try reopened.transactions()), before)
            XCTAssertEqual(try reopened.recurringOccurrences().first?.status, .legacyCounted)
            XCTAssertEqual(try reopened.exportBackup().schemaVersion, 10)
            try reopened.checkDatabase()
        }
    }

    func testExportReplaceReopenAndExportPreservesEveryTable() throws {
        try withDatabases { source, target, targetURL in
            let (event, parsedID) = try populate(source)
            let original = try source.exportBackup()
            let encoded = try JSONEncoder().encode(original)
            let decoded = try BackupArchive.decode(encoded)
            XCTAssertEqual(decoded.tables.count, SQLiteDatabase.backupTableNames.count)
            XCTAssertGreaterThan(decoded.tables.first { $0.name == "exact_dedup" }?.rows.count ?? 0, 0)
            XCTAssertGreaterThan(decoded.tables.first { $0.name == "recurring_occurrences_local" }?.rows.count ?? 0, 0)
            let preview = try target.previewBackup(decoded)
            XCTAssertEqual(preview.incomingHistoricalMovements, 1)
            XCTAssertEqual(preview.incomingOccurrences, 2)
            _ = try target.restoreBackup(decoded, preview: preview, mode: .replace)
            let reopened = try SQLiteDatabase(url: targetURL)
            let after = try reopened.exportBackup()
            XCTAssertEqual(after.tables, original.tables)
            XCTAssertEqual(try reopened.captureNotification(event).status, .duplicateIgnored)
            XCTAssertEqual(try reopened.transactions().filter { $0.sourceEventID == event.id }.count, 1)
            XCTAssertEqual(try reopened.transactions().first { $0.id == parsedID }?.sourceEventID, event.id)
            XCTAssertEqual(try reopened.historicalBackup()?.provenance.first?.sourceID, "fictional-source-1")
        }
    }

    func testRepeatedReplaceAndMergeDoNotDuplicate() throws {
        try withDatabases { source, target, _ in
            _ = try populate(source)
            let backup = try source.exportBackup()
            _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .replace)
            let rows = try target.backupTables()
            let repeatPreview = try target.previewBackup(backup)
            XCTAssertEqual(repeatPreview.newRowsForMerge, 0)
            XCTAssertEqual(try target.restoreBackup(backup, preview: repeatPreview, mode: .merge), 0)
            XCTAssertEqual(try target.backupTables(), rows)
            _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .replace)
            XCTAssertEqual(try target.backupTables(), rows)
        }
    }

    func testMergeAddsNewRowsFromSharedHistoryAndKeepsExistingRows() throws {
        try withDatabases { source, target, _ in
            _ = try populate(source)
            let first = try source.exportBackup()
            _ = try target.restoreBackup(first, preview: target.previewBackup(first), mode: .replace)
            let added = Transaction(id: UUID(), kind: .income, amountMinor: 700, currency: "EUR",
                merchant: "Fictional later income", account: "Fictional checking", category: "", note: "",
                occurredAt: .now, updatedAt: .now, deletedAt: nil, isDemo: false,
                revision: 0, sourceEventID: nil)
            _ = try source.save(added)
            let second = try source.exportBackup()
            let preview = try target.previewBackup(second)
            XCTAssertNil(preview.mergeConflict)
            XCTAssertEqual(preview.newRowsForMerge, 2) // Transaction and operation.
            XCTAssertEqual(try target.restoreBackup(second, preview: preview, mode: .merge), 2)
            XCTAssertEqual(try target.transactions().count, 4)
            XCTAssertEqual(try target.backupTables(), second.tables)
        }
    }

    func testMalformedUnsupportedIncompleteAndChangedPreviewLeaveLedgerUntouched() throws {
        try withDatabases { source, target, _ in
            _ = try populate(source)
            let backup = try source.exportBackup()
            let original = try target.backupTables()
            XCTAssertThrowsError(try BackupArchive.decode(Data("{".utf8)))
            for version in [2, 3, 4, 11] {
                XCTAssertThrowsError(try BackupArchive.decode(Data("{\"schemaVersion\":\(version)}".utf8)))
            }
            XCTAssertThrowsError(try BackupArchive.decode(Data("{\"schemaVersion\":5}".utf8)))
            let incomplete = BackupArchive(schemaVersion: 10, databaseSchemaVersion: 9,
                exportID: backup.exportID, exportedAt: backup.exportedAt,
                contentSHA256: backup.contentSHA256, tables: Array(backup.tables.dropLast()),
                sourceFormatVersion: nil)
            XCTAssertThrowsError(try target.previewBackup(incomplete))
            for (column, value) in [("id", "invalid-uuid"), ("amount_minor", "not-a-number")] {
                var changed = backup.tables
                let position = try XCTUnwrap(changed.firstIndex { $0.name == "transactions" })
                var rows = changed[position].rows
                let index = try XCTUnwrap(changed[position].columns.firstIndex(of: column))
                rows[0][index] = value
                changed[position] = BackupTable(name: "transactions", columns: changed[position].columns, rows: rows)
                let damaged = BackupArchive(schemaVersion: 10, databaseSchemaVersion: 9,
                    exportID: backup.exportID, exportedAt: backup.exportedAt,
                    contentSHA256: try SQLiteDatabase.digest(changed), tables: changed,
                    sourceFormatVersion: nil)
                XCTAssertThrowsError(try target.previewBackup(damaged))
                XCTAssertEqual(try target.backupTables(), original)
            }
            let preview = try target.previewBackup(backup)
            let extra = Transaction(id: UUID(), kind: .income, amountMinor: 100, currency: "EUR",
                merchant: "Fictional extra", account: "Fictional checking", category: "", note: "",
                occurredAt: .now, updatedAt: .now, deletedAt: nil, isDemo: false,
                revision: 0, sourceEventID: nil)
            _ = try target.save(extra)
            XCTAssertThrowsError(try target.restoreBackup(backup, preview: preview, mode: .replace))
            XCTAssertEqual(try target.transactions().count, 1)
            XCTAssertNotEqual(try target.backupTables(), original)
        }
    }

    func testConflictingMergeRollsBackWithoutPartialRows() throws {
        try withDatabases { source, target, _ in
            _ = try populate(source)
            let backup = try source.exportBackup()
            _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .replace)
            let item = try XCTUnwrap(target.transactions().first)
            var edited = item
            edited.note = "Fictional local edit"
            _ = try target.save(edited)
            let before = try target.backupTables()
            let preview = try target.previewBackup(backup)
            XCTAssertNotNil(preview.mergeConflict)
            XCTAssertThrowsError(try target.restoreBackup(backup, preview: preview, mode: .merge))
            XCTAssertEqual(try target.backupTables(), before)
        }
    }

    func testMidRestoreSQLiteFailureRollsBackAllDeletedAndInsertedRows() throws {
        try withDatabases { source, target, _ in
            _ = try populate(source)
            _ = try target.seedDemoIfNeeded()
            let backup = try source.exportBackup()
            let preview = try target.previewBackup(backup)
            let before = try target.backupTables()
            try target.execute("CREATE TRIGGER fail_restore BEFORE INSERT ON operations BEGIN SELECT RAISE(ABORT, 'fictional injected failure'); END")
            XCTAssertThrowsError(try target.restoreBackup(backup, preview: preview, mode: .replace))
            XCTAssertEqual(try target.backupTables(), before)
            XCTAssertEqual(try target.transactions().count, 3)
            try target.checkDatabase()
        }
    }
}
