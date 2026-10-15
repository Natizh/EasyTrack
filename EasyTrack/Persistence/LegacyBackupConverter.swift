import CoreFoundation
import Foundation
import SQLite3

// Schema-5 JSON exports used typed arrays and omitted the two deduplication tables,
// expected occurrences, and metadata. Rebuild the deduplication keys from created
// parser attempts; the other omitted records were not produced by schema-5 workflows.
enum LegacyBackupConverter {
    static func convert(_ data: Data) throws -> BackupArchive {
        let old: BackupEnvelope
        do { old = try JSONDecoder().decode(BackupEnvelope.self, from: data) }
        catch { throw BackupError.invalid("The version 5 backup is missing required records.") }
        guard old.schemaVersion == 5 else { throw BackupError.unsupportedVersion(old.schemaVersion) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-legacy-backup-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: file.path + suffix) }
        }
        let database = try SQLiteDatabase(url: file)
        try database.execute("BEGIN IMMEDIATE")
        do {
            try database.execute("PRAGMA defer_foreign_keys=ON")
            for name in SQLiteDatabase.backupTableNames.reversed() { try database.execute("DELETE FROM \(name)") }
            try insert(database, "metadata", ["key": "demo_seeded", "value": "1"])
            if let historical = old.historical {
                if let digest = historical.sourceDigest {
                    try insert(database, "metadata", ["key": "historical_import_digest", "value": digest])
                }
                try insert(database, "metadata", ["key": "historical_import_format_version", "value": "1"])
            }
            for item in old.localAccounts {
                var row = try mapped(item, accountFields)
                row["normalized_name"] = NotificationParser.normalize(item.name)
                try insert(database, "local_accounts", row)
            }
            for item in old.ledgerCategories {
                var row = try mapped(item, categoryFields)
                row["normalized_name"] = NotificationParser.normalize(item.name)
                try insert(database, "ledger_categories", row)
            }
            if let historical = old.historical {
                for item in historical.accounts { try insert(database, "historical_accounts", mapped(item, historicalAccountFields)) }
                for item in historical.trips { try insert(database, "historical_trips", mapped(item, historicalTripFields)) }
                for item in historical.recurringRules { try insert(database, "historical_recurring_rules", mapped(item, historicalRuleFields)) }
                for item in historical.exchangeRates { try insert(database, "historical_exchange_rates", mapped(item, rateFields)) }
                for item in historical.sourceRows { try insert(database, "historical_source_rows", mapped(item, sourceRowFields)) }
                for item in historical.importWarnings { try insert(database, "historical_import_warnings", mapped(item, warningFields)) }
            }
            for item in old.transactions { try insert(database, "transactions", mapped(item, transactionFields)) }
            var events: [UUID: NotificationEvent] = [:]
            for event in old.notificationEvents {
                if events[event.id] != nil { throw BackupError.invalid("Duplicate notification event identity.") }
                events[event.id] = event
            }
            for attempt in old.parserAttempts {
                if let existing = events[attempt.event.id], existing != attempt.event {
                    throw BackupError.invalid("A notification event has conflicting payloads.")
                }
                events[attempt.event.id] = attempt.event
            }
            for item in events.values { try insert(database, "notification_events", mapped(item, eventFields)) }
            for item in old.parserSources {
                var row = try mapped(item, sourceFields)
                row["normalized_name"] = NotificationParser.normalize(item.name)
                try insert(database, "parser_sources", row)
            }
            for item in old.parserRules {
                var row = try mapped(item, ruleFields)
                row["config_json"] = try json(item.config)
                try insert(database, "parser_rules", row)
            }
            for item in old.parserRuleVersions {
                var row = try mapped(item, revisionFields)
                row["config_json"] = try json(item.config)
                try insert(database, "parser_rule_versions", row)
            }
            var transactions: [UUID: Transaction] = [:]
            for transaction in old.transactions {
                if transactions[transaction.id] != nil { throw BackupError.invalid("Duplicate transaction identity.") }
                transactions[transaction.id] = transaction
            }
            for item in old.parserAttempts {
                var row = try mapped(item, attemptFields)
                row["event_id"] = item.event.id.uuidString
                row["raw_json"] = try json(item.event)
                row["exact_fingerprint"] = NotificationParser.exactFingerprint(item.event)
                if let id = item.transactionID, let transaction = transactions[id] {
                    row["semantic_fingerprint"] = NotificationParser.semanticFingerprint(
                        amountMinor: transaction.eurMinor ?? transaction.amountMinor,
                        merchant: transaction.merchant, account: transaction.account)
                }
                try insert(database, "notification_attempts", row)
                if item.status == .created {
                    guard let transactionID = item.transactionID, let transaction = transactions[transactionID],
                          let ruleID = item.ruleID else {
                        throw BackupError.invalid("A created parser attempt is missing its transaction or rule.")
                    }
                    let occurred = item.event.receivedAt ?? item.event.capturedAt
                    try insert(database, "exact_dedup", [
                        "id": UUID().uuidString, "fingerprint": NotificationParser.exactFingerprint(item.event),
                        "occurred_at": String(occurred.timeIntervalSince1970),
                        "has_payload_date": item.event.receivedAt == nil ? "0" : "1",
                        "transaction_id": transactionID.uuidString,
                        "created_at": String(item.capturedAt.timeIntervalSince1970)
                    ])
                    try insert(database, "semantic_dedup", [
                        "id": UUID().uuidString,
                        "semantic_key": NotificationParser.semanticFingerprint(
                            amountMinor: transaction.eurMinor ?? transaction.amountMinor,
                            merchant: transaction.merchant, account: transaction.account),
                        "occurred_at": String(occurred.timeIntervalSince1970),
                        "transaction_id": transactionID.uuidString, "rule_id": ruleID.uuidString,
                        "created_at": String(item.capturedAt.timeIntervalSince1970)
                    ])
                }
            }
            if let historical = old.historical {
                for item in historical.provenance {
                    try insert(database, "historical_imported_movements", mapped(item, provenanceFields))
                }
            }
            for item in old.recurringRules {
                var row = try mapped(item, recurringRuleFields)
                row["start_day"] = item.startDay.isoString
                row["end_day"] = item.endDay?.isoString
                try insert(database, "recurring_rules_local", row)
            }
            for item in old.recurringOccurrences {
                var row = try mapped(item, occurrenceFields)
                row["scheduled_day"] = item.scheduledDay.isoString
                try insert(database, "recurring_occurrences_local", row)
            }
            for item in old.operations { try insert(database, "operations", mapped(item, operationFields)) }
            try database.checkDatabase()
            try database.execute("COMMIT")
        } catch { try? database.execute("ROLLBACK"); throw error }
        let tables = try database.backupTables()
        return BackupArchive(schemaVersion: 6, databaseSchemaVersion: 5,
                             exportID: old.exportID, exportedAt: old.exportedAt,
                             contentSHA256: try SQLiteDatabase.digest(tables), tables: tables,
                             sourceFormatVersion: 5)
    }

    private static func json<T: Encodable>(_ value: T) throws -> String {
        guard let text = String(data: try JSONEncoder().encode(value), encoding: .utf8) else {
            throw BackupError.invalid("An encoded legacy record is invalid.")
        }
        return text
    }

    private static let dateColumns: Set<String> = ["occurred_at", "updated_at", "deleted_at",
        "captured_at", "received_at", "created_at", "changed_at", "archived_at"]

    private static func mapped<T: Encodable>(_ value: T, _ fields: [String: String]) throws -> [String: String?] {
        guard let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any] else {
            throw BackupError.invalid("A legacy record cannot be decoded.")
        }
        var row: [String: String?] = [:]
        for (column, property) in fields {
            guard let raw = object[property], !(raw is NSNull) else { row[column] = nil; continue }
            if let number = raw as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    row[column] = number.boolValue ? "1" : "0"
                } else if dateColumns.contains(column) {
                    row[column] = String(number.doubleValue + Date.timeIntervalBetween1970AndReferenceDate)
                } else { row[column] = number.stringValue }
            } else if let string = raw as? String { row[column] = string }
            else { throw BackupError.invalid("A legacy \(column) value is invalid.") }
        }
        return row
    }

    private static func insert(_ database: SQLiteDatabase, _ table: String, _ row: [String: String?]) throws {
        let columns = row.keys.sorted()
        let stmt = try database.statement("INSERT INTO \(table)(\(columns.joined(separator: ","))) VALUES(\(Array(repeating: "?", count: columns.count).joined(separator: ",")))")
        defer { sqlite3_finalize(stmt) }
        for (index, column) in columns.enumerated() {
            database.bindOptional(row[column] ?? nil, at: Int32(index + 1), to: stmt)
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw BackupError.invalid("Legacy \(table) records conflict or are incomplete.") }
    }

    private static let accountFields = ["id":"id","name":"name","created_at":"createdAt","updated_at":"updatedAt","symbol_name":"symbolName","color_name":"colorName","archived_at":"archivedAt","revision":"revision"]
    private static let categoryFields = ["id":"id","name":"name","symbol_name":"symbolName","color_name":"colorName","sort_index":"sortIndex","created_at":"createdAt","updated_at":"updatedAt","archived_at":"archivedAt","revision":"revision"]
    private static let transactionFields = ["id":"id","kind":"kind","amount_minor":"amountMinor","currency":"currency","merchant":"merchant","account":"account","category":"category","note":"note","occurred_at":"occurredAt","updated_at":"updatedAt","deleted_at":"deletedAt","is_demo":"isDemo","revision":"revision","source_event_id":"sourceEventID","subcategory":"subcategory","eur_minor":"eurMinor","exchange_rate_eur":"exchangeRateEUR","personal_expense_eur_minor":"personalExpenseEURMinor","recoverable_eur_minor":"recoverableEURMinor","trip_id":"tripID","paid_by":"paidBy","affects_my_accounts":"affectsMyAccounts","source_movement_id":"sourceMovementID","source_sheet":"sourceSheet","source_row":"sourceRow","source_occurred_at":"sourceOccurredAt","source_kind":"sourceKind","account_id":"accountID","category_id":"categoryID","recurring_occurrence_id":"recurringOccurrenceID"]
    private static let eventFields = ["id":"id","source_app":"sourceApp","title":"title","subtitle":"subtitle","message":"message","received_at":"receivedAt","captured_at":"capturedAt","fingerprint":"fingerprint"]
    private static let sourceFields = ["id":"id","name":"name","created_at":"createdAt","account_id":"accountID"]
    private static let ruleFields = ["id":"id","source_id":"sourceID","name":"name","enabled":"enabled","priority":"priority","version":"version","created_at":"createdAt","updated_at":"updatedAt","deleted_at":"deletedAt"]
    private static let revisionFields = ["rule_id":"ruleID","version":"version","changed_at":"changedAt"]
    private static let attemptFields = ["id":"id","source_id":"sourceID","captured_at":"capturedAt","status":"status","rule_id":"ruleID","rule_version":"ruleVersion","transaction_id":"transactionID","detail":"detail"]
    private static let recurringRuleFields = ["id":"id","name":"name","kind":"type","amount_minor":"amountMinor","account_id":"accountID","category_id":"categoryID","frequency":"frequency","next_index":"nextIndex","timezone_id":"timeZoneIdentifier","is_active":"isActive","note":"note","created_at":"createdAt","updated_at":"updatedAt","archived_at":"archivedAt","revision":"revision","historical_source_id":"historicalSourceID"]
    private static let occurrenceFields = ["id":"id","rule_id":"ruleID","status":"status","transaction_id":"transactionID","created_at":"createdAt"]
    private static let operationFields = ["id":"id","entity_id":"entityID","action":"action","revision":"revision","payload_json":"payloadJSON","created_at":"createdAt"]
    private static let provenanceFields = ["source_id":"sourceID","transaction_id":"transactionID","source_fingerprint":"sourceFingerprint","source_sheet":"sourceSheet","source_row":"sourceRow","source_payload_json":"sourcePayloadJSON"]
    private static let historicalAccountFields = ["source_name":"sourceName","kind":"kind","currency":"currency","opening_at":"openingAt","opening_eur_minor":"openingEURMinor","is_active":"isActive","note":"note","source_sheet":"sourceSheet","source_row":"sourceRow","cell_values_json":"cellValuesJSON"]
    private static let historicalTripFields = ["id":"id","name":"name","destination":"destination","starts_at":"startsAt","ends_at":"endsAt","currency":"currency","note":"note","source_sheet":"sourceSheet","source_row":"sourceRow","cell_values_json":"cellValuesJSON"]
    private static let historicalRuleFields = ["id":"id","rule_kind":"ruleKind","name":"name","amount_minor":"amountMinor","currency":"currency","frequency":"frequency","nominal_day":"nominalDay","starts_at":"startsAt","ends_at":"endsAt","account":"account","is_active":"isActive","investment_kind":"investmentKind","date_rule":"dateRule","initial_contribution_minor":"initialContributionMinor","initial_contribution_at":"initialContributionAt","note":"note","source_sheet":"sourceSheet","source_row":"sourceRow","cell_values_json":"cellValuesJSON"]
    private static let rateFields = ["source_row":"sourceRow","date":"date","currency":"currency","eur_rate":"eurRate","status":"status","origin":"origin","source_key":"sourceKey","cell_values_json":"cellValuesJSON"]
    private static let sourceRowFields = ["source_sheet":"sheet","source_row":"row","cell_values_json":"cellValuesJSON"]
    private static let warningFields = ["source_sheet":"sheet","source_row":"row","code":"code","detail":"detail"]
}
