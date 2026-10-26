import CryptoKit
import CoreFoundation
import Foundation
import SQLite3

enum BackupError: LocalizedError {
    case unsupportedVersion(Int)
    case invalid(String)
    case changedSincePreview
    case conflict(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            version < 5
                ? "Backup format \(version) is incomplete for safe restoration. Use a version 5 through 10 backup."
                : "Backup format \(version) is newer than this app supports. Update EasyTrack before restoring it."
        case .invalid(let reason): "Backup is incomplete or damaged: \(reason)"
        case .changedSincePreview: "Local data changed after the preview. Choose the backup again."
        case .conflict(let table): "Merge found a different record with the same identity in \(table). Nothing was changed. Use Replace after reviewing the preview."
        }
    }
}

struct BackupTable: Codable, Equatable {
    let name: String
    let columns: [String]
    let rows: [[String?]]
}

struct BackupArchive: Codable {
    let schemaVersion: Int
    let databaseSchemaVersion: Int
    let exportID: UUID
    let exportedAt: Date
    let contentSHA256: String
    let tables: [BackupTable]
    let sourceFormatVersion: Int?

    static func decode(_ data: Data) throws -> BackupArchive {
        // Read the version before decoding the full shape so older exports get a useful error.
        guard let header = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = header["schemaVersion"] as? Int else {
            throw BackupError.invalid("Missing format version or invalid JSON.")
        }
        if version == 5 { return try LegacyBackupConverter.convert(data) }
        guard (6...10).contains(version) else { throw BackupError.unsupportedVersion(version) }
        do {
            let archive = try JSONDecoder().decode(BackupArchive.self, from: data)
            if version == 6 { return try archive.upgradedFromSix().upgradedFromSeven().upgradedFromEight().upgradedFromNine() }
            if version == 7 { return try archive.upgradedFromSeven().upgradedFromEight().upgradedFromNine() }
            if version == 8 { return try archive.upgradedFromEight().upgradedFromNine() }
            if version == 9 { return try archive.upgradedFromNine() }
            return archive
        }
        catch { throw BackupError.invalid("Required fields could not be decoded.") }
    }
}

extension BackupArchive {
    func upgradedFromSix() throws -> BackupArchive {
        guard schemaVersion == 6, databaseSchemaVersion == 5,
              tables.map(\.name) == Array(SQLiteDatabase.backupTableNames.prefix(22)),
              try SQLiteDatabase.digest(tables) == contentSHA256 else {
            throw BackupError.invalid("The version 6 table list or checksum is invalid.")
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-backup-upgrade-\(UUID().uuidString).sqlite")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: file.path + suffix) } }
        let schema = try SQLiteDatabase(url: file)
        let targetTables = Array(try schema.backupTables().prefix(25))
        let transactionTable = tables.first { $0.name == "transactions" }!
        guard let idIndex = transactionTable.columns.firstIndex(of: "id"),
              let deletedIndex = transactionTable.columns.firstIndex(of: "deleted_at") else {
            throw BackupError.invalid("Version 6 transaction identities are incomplete.")
        }
        let active = Set(transactionTable.rows.compactMap { row in
            row.count == transactionTable.columns.count && row[deletedIndex] == nil ? row[idIndex] : nil
        })
        var upgraded: [BackupTable] = []
        for (index, original) in tables.enumerated() {
            let target = targetTables[index]
            let oldColumns: [String]
            switch original.name {
            case "recurring_rules_local": oldColumns = target.columns.filter { $0 != "review_window_days" }
            case "recurring_occurrences_local":
                oldColumns = ["id", "rule_id", "scheduled_day", "status", "transaction_id", "created_at"]
            default: oldColumns = target.columns
            }
            guard original.columns == oldColumns,
                  original.rows.allSatisfy({ $0.count == oldColumns.count }) else {
                throw BackupError.invalid("Version 6 \(original.name) columns are incomplete.")
            }
            let rows: [[String?]]
            switch original.name {
            case "recurring_rules_local": rows = original.rows.map { $0 + ["3"] }
            case "recurring_occurrences_local":
                rows = try original.rows.map { row in
                    guard row[3] == "materialized" || row[3] == "skipped",
                          (row[3] == "materialized") == (row[4] != nil) else {
                        throw BackupError.invalid("Version 6 occurrence status is invalid.")
                    }
                    let oldID = row[4]
                    let counted = row[3] == "materialized" && oldID.map(active.contains) == true
                    return [row[0], row[1], row[2],
                            row[3] == "skipped" ? "skipped" : (counted ? "legacy_counted" : "expected"),
                            counted ? oldID : nil, row[3] == "materialized" ? oldID : nil,
                            row[5], row[5], "1",
                            row[3] == "materialized" && !counted ?
                                "Previous transaction was deleted; review before recording." : nil]
                }
            default: rows = original.rows
            }
            upgraded.append(BackupTable(name: target.name, columns: target.columns, rows: rows))
        }
        upgraded.append(contentsOf: targetTables.dropFirst(tables.count))
        return BackupArchive(schemaVersion: 7, databaseSchemaVersion: 6,
                             exportID: exportID, exportedAt: exportedAt,
                             contentSHA256: try SQLiteDatabase.digest(upgraded), tables: upgraded,
                             sourceFormatVersion: sourceFormatVersion ?? 6)
    }
}

extension BackupArchive {
    func upgradedFromSeven() throws -> BackupArchive {
        let legacyNames = Array(SQLiteDatabase.backupTableNames.prefix(25))
        guard schemaVersion == 7, databaseSchemaVersion == 6,
              tables.map(\.name) == legacyNames,
              try SQLiteDatabase.digest(tables) == contentSHA256 else {
            throw BackupError.invalid("The version 7 table list or checksum is invalid.")
        }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyTrack-backup-upgrade-\(UUID().uuidString).sqlite")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: file.path + suffix) } }
        let targetTables = try SQLiteDatabase(url: file).backupTables()
        guard Array(targetTables.prefix(25)).enumerated().allSatisfy({ index, target in
            tables[index].columns == target.columns &&
                tables[index].rows.allSatisfy { $0.count == target.columns.count }
        }) else {
            throw BackupError.invalid("Version 7 table columns are incomplete.")
        }
        let upgraded = tables + [targetTables[25]]
        return BackupArchive(schemaVersion: 8, databaseSchemaVersion: 7,
                             exportID: exportID, exportedAt: exportedAt,
                             contentSHA256: try SQLiteDatabase.digest(upgraded), tables: upgraded,
                             sourceFormatVersion: sourceFormatVersion ?? 7)
    }
}

extension BackupArchive {
    func upgradedFromEight() throws -> BackupArchive {
        let legacyNames = Array(SQLiteDatabase.backupTableNames.prefix(26))
        guard schemaVersion == 8, databaseSchemaVersion == 7,
              tables.map(\.name) == legacyNames,
              try SQLiteDatabase.digest(tables) == contentSHA256 else {
            throw BackupError.invalid("The version 8 table list or checksum is invalid.")
        }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyTrack-backup-upgrade-\(UUID().uuidString).sqlite")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: file.path + suffix) } }
        let targetTables = try SQLiteDatabase(url: file).backupTables()
        guard Array(targetTables.prefix(26)).enumerated().allSatisfy({ index, target in
            tables[index].columns == target.columns &&
                tables[index].rows.allSatisfy { $0.count == target.columns.count }
        }) else {
            throw BackupError.invalid("Version 8 table columns are incomplete.")
        }
        let upgraded = tables + [targetTables[26]]
        return BackupArchive(schemaVersion: 9, databaseSchemaVersion: 8,
                             exportID: exportID, exportedAt: exportedAt,
                             contentSHA256: try SQLiteDatabase.digest(upgraded), tables: upgraded,
                             sourceFormatVersion: sourceFormatVersion ?? 8)
    }
}

extension BackupArchive {
    func upgradedFromNine() throws -> BackupArchive {
        let legacyNames = Array(SQLiteDatabase.backupTableNames.prefix(27))
        guard schemaVersion == 9, databaseSchemaVersion == 8,
              tables.map(\.name) == legacyNames,
              try SQLiteDatabase.digest(tables) == contentSHA256 else {
            throw BackupError.invalid("The version 9 table list or checksum is invalid.")
        }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyTrack-backup-upgrade-\(UUID().uuidString).sqlite")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: file.path + suffix) } }
        let targetTables = try SQLiteDatabase(url: file).backupTables()
        guard Array(targetTables.prefix(27)).enumerated().allSatisfy({ index, target in
            tables[index].columns == target.columns &&
                tables[index].rows.allSatisfy { $0.count == target.columns.count }
        }) else {
            throw BackupError.invalid("Version 9 table columns are incomplete.")
        }
        let upgraded = tables + Array(targetTables.suffix(2))
        return BackupArchive(schemaVersion: 10, databaseSchemaVersion: 9,
                             exportID: exportID, exportedAt: exportedAt,
                             contentSHA256: try SQLiteDatabase.digest(upgraded), tables: upgraded,
                             sourceFormatVersion: sourceFormatVersion ?? 9)
    }
}

enum BackupRestoreMode: Equatable { case replace, merge }

struct BackupRestorePreview {
    let exportID: UUID
    let exportedAt: Date
    let incomingTransactions: Int
    let existingTransactions: Int
    let incomingEvents: Int
    let incomingRules: Int
    let incomingOccurrences: Int
    let incomingHistoricalMovements: Int
    let incomingOperations: Int
    let incomingCandidates: Int
    let incomingApprovedPayees: Int
    let incomingReconciliationAudit: Int
    let existingReconciliationRows: Int
    let newRowsForMerge: Int?
    let mergeConflict: String?
    let localFingerprint: String
    let sourceFormatVersion: Int?
}

extension SQLiteDatabase {
    // Every persistent schema-7 table is listed here. A format change must update this list and
    // bump the backup format; unknown tables must never be silently discarded.
    static let backupTableNames = [
        "metadata", "local_accounts", "ledger_categories", "historical_accounts",
        "historical_trips", "historical_recurring_rules", "historical_exchange_rates",
        "historical_source_rows", "historical_import_warnings", "transactions",
        "notification_events", "parser_sources", "parser_rules", "parser_rule_versions",
        "notification_attempts", "exact_dedup", "semantic_dedup",
        "historical_imported_movements", "expected_occurrences", "recurring_rules_local",
        "recurring_occurrences_local", "operations", "recurring_candidates",
        "recurring_payee_aliases", "recurring_reconciliation_audit",
        "dashboard_widget_preferences", "merchant_alias_groups",
        "expense_reimbursement_plans", "expense_reimbursement_links"
    ]

    private func backupColumns(_ table: String) throws -> (columns: [String], primary: [String]) {
        let stmt = try statement("PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(stmt) }
        var columns: [String] = []
        var primary: [(Int, String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = string(stmt, 1)
            columns.append(name)
            let position = Int(sqlite3_column_int(stmt, 5))
            if position > 0 { primary.append((position, name)) }
        }
        guard !columns.isEmpty, !primary.isEmpty else { throw BackupError.invalid("Unknown table \(table).") }
        return (columns, primary.sorted { $0.0 < $1.0 }.map(\.1))
    }

    private func backupValue(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        switch sqlite3_column_type(stmt, index) {
        case SQLITE_NULL: return nil
        case SQLITE_INTEGER: return String(sqlite3_column_int64(stmt, index))
        case SQLITE_FLOAT: return String(sqlite3_column_double(stmt, index))
        case SQLITE_TEXT: return string(stmt, index)
        default: return nil // schema 5 has no BLOB columns
        }
    }

    private func backupTable(_ name: String) throws -> BackupTable {
        let definition = try backupColumns(name)
        let order = definition.primary.joined(separator: ",")
        let stmt = try statement("SELECT * FROM \(name) ORDER BY \(order)")
        defer { sqlite3_finalize(stmt) }
        var rows: [[String?]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append((0..<definition.columns.count).map { backupValue(stmt, Int32($0)) })
        }
        return BackupTable(name: name, columns: definition.columns, rows: rows)
    }

    func backupTables() throws -> [BackupTable] {
        try Self.backupTableNames.map { try backupTable($0) }
    }

    static func digest(_ tables: [BackupTable]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(tables)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func exportBackup() throws -> BackupArchive {
        try execute("BEGIN DEFERRED")
        do {
            try checkDatabase()
            let tables = try backupTables()
            try checkReadableRows(tables)
            let archive = BackupArchive(schemaVersion: 10, databaseSchemaVersion: 9,
                                        exportID: UUID(), exportedAt: .now,
                                        contentSHA256: try Self.digest(tables), tables: tables,
                                        sourceFormatVersion: nil)
            try validate(archive)
            try execute("COMMIT")
            return archive
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func checkDatabase() throws {
        for query in ["PRAGMA integrity_check", "PRAGMA foreign_key_check"] {
            let stmt = try statement(query)
            defer { sqlite3_finalize(stmt) }
            let result = sqlite3_step(stmt)
            if query.contains("foreign_key") {
                guard result == SQLITE_DONE else { throw BackupError.invalid("Database references are broken.") }
            } else {
                guard result == SQLITE_ROW, string(stmt, 0) == "ok", sqlite3_step(stmt) == SQLITE_DONE else {
                    throw BackupError.invalid("Database integrity check failed.")
                }
            }
        }
    }

    private func countBackupRows(_ sql: String) throws -> Int {
        let stmt = try statement(sql)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw BackupError.invalid("A row check failed.") }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func checkReadableRows(_ tables: [BackupTable]) throws {
        func expected(_ name: String) -> Int { tables.first { $0.name == name }?.rows.count ?? 0 }
        let readable: [(String, Int)] = [
            ("transactions", try transactions(includeDeleted: true).count),
            ("notification_events", try notificationEvents().count),
            ("operations", try operations().count),
            ("local_accounts", try localAccounts().count),
            ("ledger_categories", try ledgerCategories().count),
            ("parser_sources", try parserSources().count),
            ("parser_rules", try parserRules(includeDeleted: true).count),
            ("notification_attempts", try parserAttempts().count),
            ("recurring_rules_local", try recurringRules(includeArchived: true).count),
            ("recurring_occurrences_local", try recurringOccurrences().count),
            ("recurring_candidates", try recurringCandidates().count),
            ("historical_accounts", try historicalAccounts().count),
            ("historical_trips", try historicalTrips().count),
            ("historical_recurring_rules", try historicalRules().count)
        ]
        for (name, count) in readable where count != expected(name) {
            throw BackupError.invalid("Some \(name) records cannot be opened by this app.")
        }
        let versions = try parserRules(includeDeleted: true).reduce(0) { count, rule in
            count + (try parserRuleHistory(rule.id).count)
        }
        guard versions == expected("parser_rule_versions") else {
            throw BackupError.invalid("Some parser rule revisions cannot be opened by this app.")
        }
        for table in tables {
            let info = try statement("PRAGMA table_info(\(table.name))")
            defer { sqlite3_finalize(info) }
            while sqlite3_step(info) == SQLITE_ROW {
                let column = string(info, 1)
                let type = string(info, 2).uppercased()
                let allowed: String
                if type.contains("INT") { allowed = "'integer','null'" }
                else if type.contains("REAL") { allowed = "'integer','real','null'" }
                else { allowed = "'text','null'" }
                if try countBackupRows("SELECT COUNT(*) FROM \(table.name) WHERE typeof(\(column)) NOT IN (\(allowed))") > 0 {
                    throw BackupError.invalid("The \(table.name) table has an invalid \(column) value.")
                }
            }
        }
        let missingProvenance = try countBackupRows("""
            SELECT COUNT(*) FROM historical_imported_movements p
            LEFT JOIN transactions t ON t.id=p.transaction_id
            WHERE t.id IS NULL OR t.source_movement_id!=p.source_id
            """)
        guard missingProvenance == 0 else { throw BackupError.invalid("Historical identities do not match transactions.") }
        let brokenOccurrences = try countBackupRows("""
            SELECT COUNT(*) FROM recurring_occurrences_local o
            LEFT JOIN transactions t ON t.id=o.transaction_id
            WHERE o.transaction_id IS NOT NULL AND
                  (t.id IS NULL OR t.deleted_at IS NOT NULL OR t.recurring_occurrence_id!=o.id)
            """)
        guard brokenOccurrences == 0 else { throw BackupError.invalid("Recurring occurrence links are broken.") }
        let reverseLinks = try countBackupRows("""
            SELECT COUNT(*) FROM transactions t
            LEFT JOIN recurring_occurrences_local o ON o.id=t.recurring_occurrence_id
            WHERE t.deleted_at IS NULL AND t.recurring_occurrence_id IS NOT NULL
                  AND (o.id IS NULL OR o.transaction_id!=t.id)
            """)
        guard reverseLinks == 0 else { throw BackupError.invalid("An active recurring transaction has no effective occurrence.") }
        let brokenCandidates = try countBackupRows("""
            SELECT COUNT(*) FROM recurring_candidates c
            LEFT JOIN recurring_occurrences_local o ON o.id=c.occurrence_id
            WHERE o.id IS NULL OR (c.status='confirmed' AND
                (c.transaction_id IS NULL OR o.transaction_id IS NULL OR
                 c.transaction_id!=o.transaction_id))
            """)
        guard brokenCandidates == 0 else { throw BackupError.invalid("Recurring candidate links are broken.") }
        let orphanEvents = try countBackupRows("""
            SELECT COUNT(*) FROM transactions t LEFT JOIN notification_events e ON e.id=t.source_event_id
            WHERE t.source_event_id IS NOT NULL AND e.id IS NULL
            """)
        guard orphanEvents == 0 else { throw BackupError.invalid("A transaction has a missing notification event.") }
        let brokenReimbursements = try countBackupRows("""
            SELECT COUNT(*) FROM expense_reimbursement_plans p
            JOIN transactions e ON e.id=p.expense_id
            LEFT JOIN (SELECT expense_id,SUM(amount_eur_minor) received
                       FROM expense_reimbursement_links GROUP BY expense_id) s ON s.expense_id=p.expense_id
            WHERE e.deleted_at IS NOT NULL OR e.kind!='expense' OR
                  p.expected_eur_minor>(CASE WHEN e.currency='EUR' THEN e.amount_minor ELSE e.eur_minor END) OR
                  p.written_off_eur_minor+COALESCE(s.received,0)>p.expected_eur_minor OR
                  e.personal_expense_eur_minor!=(CASE WHEN e.currency='EUR' THEN e.amount_minor ELSE e.eur_minor END)
                    -p.expected_eur_minor+p.written_off_eur_minor OR
                  e.recoverable_eur_minor!=p.expected_eur_minor-p.written_off_eur_minor-COALESCE(s.received,0)
            """)
        guard brokenReimbursements == 0 else { throw BackupError.invalid("Expected reimbursement totals are inconsistent.") }
        let brokenReceipts = try countBackupRows("""
            SELECT COUNT(*) FROM expense_reimbursement_links l
            JOIN transactions r ON r.id=l.reimbursement_id
            WHERE r.deleted_at IS NOT NULL OR r.kind!='reimbursement' OR
                  l.amount_eur_minor!=(CASE WHEN r.currency='EUR' THEN r.amount_minor ELSE r.eur_minor END) OR
                  r.personal_expense_eur_minor!=0
            """)
        guard brokenReceipts == 0 else { throw BackupError.invalid("A linked reimbursement is inconsistent.") }
    }

    private func validate(_ archive: BackupArchive) throws {
        guard archive.schemaVersion == 10, archive.databaseSchemaVersion == 9 else {
            throw BackupError.unsupportedVersion(archive.schemaVersion)
        }
        guard archive.tables.map(\.name) == Self.backupTableNames else {
            throw BackupError.invalid("The table list is missing or has an unexpected table.")
        }
        let metadata = archive.tables[0]
        guard let key = metadata.columns.firstIndex(of: "key"),
              let value = metadata.columns.firstIndex(of: "value"),
              metadata.rows.contains(where: { $0.count > max(key, value) && $0[key] == "demo_seeded" && $0[value] == "1" }) else {
            throw BackupError.invalid("The app initialization marker is missing.")
        }
        guard try Self.digest(archive.tables) == archive.contentSHA256 else {
            throw BackupError.invalid("The content checksum does not match.")
        }
        for table in archive.tables {
            guard table.columns == (try backupColumns(table.name).columns),
                  table.rows.allSatisfy({ $0.count == table.columns.count }) else {
                throw BackupError.invalid("The \(table.name) table has missing or extra columns.")
            }
        }
    }

    private func insert(_ table: BackupTable, row: [String?]) throws {
        let markers = Array(repeating: "?", count: table.columns.count).joined(separator: ",")
        let stmt = try statement("INSERT INTO \(table.name)(\(table.columns.joined(separator: ","))) VALUES(\(markers))")
        defer { sqlite3_finalize(stmt) }
        for (index, value) in row.enumerated() { bindOptional(value, at: Int32(index + 1), to: stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
    }

    private func apply(_ archive: BackupArchive, mode: BackupRestoreMode) throws -> Int {
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("PRAGMA defer_foreign_keys=ON")
            if mode == .replace {
                for name in Self.backupTableNames.reversed() { try execute("DELETE FROM \(name)") }
            }
            var inserted = 0
            for table in archive.tables {
                if mode == .merge,
                   table.name == "dashboard_widget_preferences" || table.name == "merchant_alias_groups" {
                    continue // Local visualization choices deliberately win every merge.
                }
                let definition = try backupColumns(table.name)
                let indexes = definition.primary.map { table.columns.firstIndex(of: $0)! }
                var existing: [String: [String?]] = [:]
                if mode == .merge {
                    let current = try backupTable(table.name)
                    for row in current.rows { existing[Self.rowKey(row, indexes: indexes)] = row }
                }
                for row in table.rows {
                    if mode == .merge, let old = existing[Self.rowKey(row, indexes: indexes)] {
                        guard old == row else { throw BackupError.conflict(table.name) }
                        continue
                    }
                    try insert(table, row: row)
                    inserted += 1
                }
            }
            try checkDatabase()
            try checkReadableRows(try backupTables())
            if mode == .replace, try backupTables() != archive.tables {
                throw BackupError.invalid("Restored rows differ from the selected backup.")
            }
            try execute("COMMIT")
            return inserted
        } catch { try? execute("ROLLBACK"); throw error }
    }

    private static func rowKey(_ row: [String?], indexes: [Int]) -> String {
        indexes.map { value in
            let text = row[value] ?? ""
            return "\(text.utf8.count):\(text)"
        }.joined(separator: "|")
    }

    private func withDisposableDatabase<T>(_ body: (SQLiteDatabase) throws -> T) throws -> T {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-restore-check-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: temporary.path + suffix)
            }
        }
        return try body(SQLiteDatabase(url: temporary))
    }

    func previewBackup(_ archive: BackupArchive) throws -> BackupRestorePreview {
        try validate(archive)
        try withDisposableDatabase { scratch in
            _ = try scratch.apply(archive, mode: .replace)
        }
        let live = try backupTables()
        let fingerprint = try Self.digest(live)
        var mergeCount: Int?
        var conflict: String?
        do {
            mergeCount = try withDisposableDatabase { scratch in
                // Copy the current database into a disposable file using SQLite's snapshot API.
                guard let backup = sqlite3_backup_init(scratch.handle, "main", handle, "main") else {
                    throw DatabaseError.sqlite("Could not stage the current ledger")
                }
                let status = sqlite3_backup_step(backup, -1)
                let finish = sqlite3_backup_finish(backup)
                guard status == SQLITE_DONE, finish == SQLITE_OK else {
                    throw DatabaseError.sqlite("Could not stage the current ledger")
                }
                return try scratch.apply(archive, mode: .merge)
            }
        } catch BackupError.conflict(let name) { conflict = name }
        catch { conflict = "database constraints" }
        func count(_ name: String) -> Int { archive.tables.first { $0.name == name }?.rows.count ?? 0 }
        return BackupRestorePreview(exportID: archive.exportID, exportedAt: archive.exportedAt,
                                    incomingTransactions: count("transactions"),
                                    existingTransactions: live.first { $0.name == "transactions" }?.rows.count ?? 0,
                                    incomingEvents: count("notification_events"),
                                    incomingRules: count("parser_rules") + count("recurring_rules_local"),
                                    incomingOccurrences: count("recurring_occurrences_local") + count("expected_occurrences"),
                                    incomingHistoricalMovements: count("historical_imported_movements"),
                                    incomingOperations: count("operations"),
                                    incomingCandidates: count("recurring_candidates"),
                                    incomingApprovedPayees: count("recurring_payee_aliases"),
                                    incomingReconciliationAudit: count("recurring_reconciliation_audit"),
                                    existingReconciliationRows: ["recurring_candidates", "recurring_payee_aliases",
                                        "recurring_reconciliation_audit"].reduce(0) { total, name in
                                            total + (live.first { $0.name == name }?.rows.count ?? 0)
                                        },
                                    newRowsForMerge: mergeCount, mergeConflict: conflict,
                                    localFingerprint: fingerprint,
                                    sourceFormatVersion: archive.sourceFormatVersion)
    }

    @discardableResult func restoreBackup(_ archive: BackupArchive, preview: BackupRestorePreview,
                                           mode: BackupRestoreMode) throws -> Int {
        guard preview.exportID == archive.exportID,
              try Self.digest(backupTables()) == preview.localFingerprint else {
            throw BackupError.changedSincePreview
        }
        _ = try previewBackup(archive) // Revalidate the selected file and the proposed result.
        let inserted = try apply(archive, mode: mode)
        let reopened = try SQLiteDatabase(url: url)
        try reopened.checkDatabase()
        try reopened.checkReadableRows(try reopened.backupTables())
        if mode == .replace, try reopened.backupTables() != archive.tables {
            throw BackupError.invalid("The reopened ledger differs from the backup.")
        }
        return inserted
    }
}

actor BackupRestoreCoordinator {
    static let shared = BackupRestoreCoordinator()
    private var staged: (BackupArchive, BackupRestorePreview)?

    func stage(_ selectedURL: URL) throws -> BackupRestorePreview {
        staged = nil
        let scoped = selectedURL.startAccessingSecurityScopedResource()
        let ownContainer = selectedURL.standardizedFileURL.path.hasPrefix(
            URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path + "/")
        guard scoped || ownContainer else { throw BackupError.invalid("Files access was not granted.") }
        defer { if scoped { selectedURL.stopAccessingSecurityScopedResource() } }
        var readError: Error?
        var data: Data?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: selectedURL, options: [], error: &coordinationError) { file in
            do {
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 100_000_000 else { throw BackupError.invalid("The file exceeds 100 MB.") }
                let reader = try FileHandle(forReadingFrom: file)
                defer { try? reader.close() }
                data = try reader.read(upToCount: 100_000_001) ?? Data()
            } catch { readError = error }
        }
        if let readError { throw readError }
        if coordinationError != nil { throw BackupError.invalid("Files could not read the selected backup.") }
        guard let data, data.count <= 100_000_000 else { throw BackupError.invalid("The file exceeds 100 MB.") }
        let archive = try BackupArchive.decode(data)
        let preview = try SQLiteDatabase.open().previewBackup(archive)
        staged = (archive, preview)
        return preview
    }

    func confirm(_ mode: BackupRestoreMode) throws -> Int {
        guard let staged else { throw BackupError.invalid("Choose the backup again.") }
        let inserted = try SQLiteDatabase.open().restoreBackup(staged.0, preview: staged.1, mode: mode)
        self.staged = nil
        return inserted
    }

    func discard() { staged = nil }
}
