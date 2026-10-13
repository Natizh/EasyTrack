import Foundation
import SQLite3

enum DatabaseError: LocalizedError {
    case sqlite(String)
    var errorDescription: String? {
        switch self { case .sqlite(let message): "Local database error: \(message)" }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SQLiteDatabase {
    private var handle: OpaquePointer?

    static func open() throws -> SQLiteDatabase {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try SQLiteDatabase(url: directory.appendingPathComponent("EasyTrack.sqlite"))
    }

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw DatabaseError.sqlite("Could not open local database")
        }
        do {
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA busy_timeout=5000")
            try execute("PRAGMA foreign_keys=ON")
            let versionStatement = try statement("PRAGMA user_version")
            guard sqlite3_step(versionStatement) == SQLITE_ROW else {
                sqlite3_finalize(versionStatement)
                throw DatabaseError.sqlite("could not read schema version")
            }
            let existingVersion = sqlite3_column_int(versionStatement, 0)
            sqlite3_finalize(versionStatement)
            guard existingVersion <= 2 else { throw DatabaseError.sqlite("newer local database version is unsupported") }
            try execute("""
                CREATE TABLE IF NOT EXISTS transactions (
                    id TEXT PRIMARY KEY, kind TEXT NOT NULL, amount_minor INTEGER NOT NULL,
                    currency TEXT NOT NULL, merchant TEXT NOT NULL, account TEXT NOT NULL,
                    category TEXT NOT NULL, note TEXT NOT NULL, occurred_at REAL NOT NULL,
                    updated_at REAL NOT NULL, deleted_at REAL, is_demo INTEGER NOT NULL,
                    revision INTEGER NOT NULL, source_event_id TEXT
                )
                """)
            try execute("CREATE INDEX IF NOT EXISTS transactions_by_date ON transactions(occurred_at DESC)")
            try execute("CREATE UNIQUE INDEX IF NOT EXISTS unique_active_source_event ON transactions(source_event_id) WHERE deleted_at IS NULL AND source_event_id IS NOT NULL")
            for (name, type) in [
                ("subcategory", "TEXT"), ("eur_minor", "INTEGER"), ("exchange_rate_eur", "TEXT"),
                ("personal_expense_eur_minor", "INTEGER"), ("recoverable_eur_minor", "INTEGER"),
                ("trip_id", "TEXT"), ("paid_by", "TEXT"), ("affects_my_accounts", "INTEGER"),
                ("source_movement_id", "TEXT"), ("source_sheet", "TEXT"), ("source_row", "INTEGER"),
                ("source_occurred_at", "TEXT"), ("source_kind", "TEXT")
            ] { try ensureColumn(name, type: type, in: "transactions") }
            try execute("CREATE UNIQUE INDEX IF NOT EXISTS unique_source_movement ON transactions(source_movement_id) WHERE source_movement_id IS NOT NULL")
            try execute("""
                CREATE TABLE IF NOT EXISTS notification_events (
                    id TEXT PRIMARY KEY, source_app TEXT NOT NULL, title TEXT NOT NULL,
                    subtitle TEXT NOT NULL, message TEXT NOT NULL, received_at REAL,
                    captured_at REAL NOT NULL, fingerprint TEXT NOT NULL UNIQUE
                )
                """)
            try execute("""
                CREATE TABLE IF NOT EXISTS operations (
                    id TEXT PRIMARY KEY, entity_id TEXT NOT NULL, action TEXT NOT NULL,
                    revision INTEGER NOT NULL, payload_json TEXT NOT NULL, created_at REAL NOT NULL
                )
                """)
            try execute("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
            try execute("""
                CREATE TABLE IF NOT EXISTS historical_imported_movements (
                    source_id TEXT PRIMARY KEY, transaction_id TEXT NOT NULL UNIQUE,
                    source_fingerprint TEXT NOT NULL, source_sheet TEXT NOT NULL,
                    source_row INTEGER NOT NULL, source_payload_json TEXT NOT NULL,
                    UNIQUE(source_sheet, source_row)
                )
                """)
            try execute("""
                CREATE TABLE IF NOT EXISTS historical_accounts (
                    source_name TEXT PRIMARY KEY, kind TEXT, currency TEXT, opening_at TEXT,
                    opening_eur_minor INTEGER, is_active INTEGER, note TEXT,
                    source_sheet TEXT NOT NULL, source_row INTEGER NOT NULL, cell_values_json TEXT NOT NULL
                )
                """)
            try execute("""
                CREATE TABLE IF NOT EXISTS historical_trips (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL, destination TEXT, starts_at TEXT,
                    ends_at TEXT, currency TEXT, note TEXT, source_sheet TEXT NOT NULL,
                    source_row INTEGER NOT NULL, cell_values_json TEXT NOT NULL
                )
                """)
            try execute("""
                CREATE TABLE IF NOT EXISTS historical_recurring_rules (
                    id TEXT PRIMARY KEY, rule_kind TEXT NOT NULL, name TEXT NOT NULL,
                    amount_minor INTEGER NOT NULL, currency TEXT NOT NULL, frequency TEXT,
                    nominal_day INTEGER, starts_at TEXT, ends_at TEXT, account TEXT,
                    is_active INTEGER, investment_kind TEXT, date_rule TEXT,
                    initial_contribution_minor INTEGER, initial_contribution_at TEXT, note TEXT,
                    source_sheet TEXT NOT NULL, source_row INTEGER NOT NULL, cell_values_json TEXT NOT NULL
                )
                """)
            try execute("""
                CREATE TABLE IF NOT EXISTS expected_occurrences (
                    id TEXT PRIMARY KEY, rule_source_id TEXT NOT NULL,
                    scheduled_at TEXT NOT NULL, matched_transaction_id TEXT UNIQUE,
                    status TEXT NOT NULL CHECK(status IN ('expected', 'matched', 'skipped')),
                    UNIQUE(rule_source_id, scheduled_at),
                    FOREIGN KEY(rule_source_id) REFERENCES historical_recurring_rules(id),
                    FOREIGN KEY(matched_transaction_id) REFERENCES transactions(id),
                    CHECK((status = 'matched') = (matched_transaction_id IS NOT NULL))
                )
                """)
            try execute("""
                CREATE TABLE IF NOT EXISTS historical_exchange_rates (
                    source_row INTEGER PRIMARY KEY, date TEXT NOT NULL, currency TEXT NOT NULL,
                    eur_rate TEXT NOT NULL, status TEXT, origin TEXT, source_key TEXT,
                    cell_values_json TEXT NOT NULL
                )
                """)
            try execute("""
                CREATE TABLE IF NOT EXISTS historical_source_rows (
                    source_sheet TEXT NOT NULL, source_row INTEGER NOT NULL,
                    cell_values_json TEXT NOT NULL, PRIMARY KEY(source_sheet, source_row)
                )
                """)
            try execute("""
                CREATE TABLE IF NOT EXISTS historical_import_warnings (
                    source_sheet TEXT NOT NULL, source_row INTEGER NOT NULL,
                    code TEXT NOT NULL, detail TEXT, PRIMARY KEY(source_sheet, source_row, code)
                )
                """)
            if existingVersion < 2 { try execute("PRAGMA user_version=2") }
        } catch {
            sqlite3_close(handle)
            handle = nil
            throw error
        }
    }

    deinit { sqlite3_close(handle) }

    private func error() -> DatabaseError {
        DatabaseError.sqlite(String(cString: sqlite3_errmsg(handle)))
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }

    private func ensureColumn(_ name: String, type: String, in table: String) throws {
        let columns = try statement("PRAGMA table_info(\(table))")
        var present = false
        while sqlite3_step(columns) == SQLITE_ROW {
            if string(columns, 1) == name { present = true; break }
        }
        sqlite3_finalize(columns)
        if !present { try execute("ALTER TABLE \(table) ADD COLUMN \(name) \(type)") }
    }

    private func statement(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw error() }
        return statement
    }

    private func bind(_ text: String, at index: Int32, to statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
    }

    private func bindOptional(_ value: String?, at index: Int32, to statement: OpaquePointer) {
        if let value { bind(value, at: index, to: statement) }
        else { sqlite3_bind_null(statement, index) }
    }

    private func bindOptional(_ value: Int64?, at index: Int32, to statement: OpaquePointer) {
        if let value { sqlite3_bind_int64(statement, index, value) }
        else { sqlite3_bind_null(statement, index) }
    }

    private func string(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    private func optionalString(_ statement: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : string(statement, index)
    }

    private func optionalInt(_ statement: OpaquePointer, _ index: Int32) -> Int64? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, index)
    }

    func seedDemoIfNeeded() throws {
        let check = try statement("SELECT value FROM metadata WHERE key = 'demo_seeded'")
        defer { sqlite3_finalize(check) }
        guard sqlite3_step(check) == SQLITE_DONE else { return }
        let countStatement = try statement("SELECT COUNT(*) FROM transactions")
        defer { sqlite3_finalize(countStatement) }
        guard sqlite3_step(countStatement) == SQLITE_ROW else { throw error() }
        if sqlite3_column_int(countStatement, 0) == 0 {
            let now = Date()
            for (id, kind, amount, merchant, category, daysAgo) in [
                ("00000000-0000-4000-8000-000000000001", TransactionKind.expense, Int64(450), "Demo · Coffee Shop", "Food & drink", 0.0),
                ("00000000-0000-4000-8000-000000000002", .expense, 2290, "Demo · Book Store", "Shopping", 1.0),
                ("00000000-0000-4000-8000-000000000003", .income, 250000, "Demo · Salary", "Income", 2.0)
            ] {
                let item = Transaction(id: UUID(uuidString: id)!, kind: kind, amountMinor: amount,
                                       currency: "EUR", merchant: merchant, account: "Demo account",
                                       category: category, note: "Demonstration record", occurredAt: now.addingTimeInterval(-daysAgo * 86_400),
                                       updatedAt: now, deletedAt: nil, isDemo: true, revision: 0, sourceEventID: nil)
                try save(item)
            }
        }
        try execute("INSERT OR REPLACE INTO metadata(key, value) VALUES ('demo_seeded', '1')")
    }

    @discardableResult func save(_ input: Transaction, manageTransaction: Bool = true) throws -> Transaction {
        if manageTransaction { try execute("BEGIN IMMEDIATE") }
        do {
            let version = try statement("SELECT revision FROM transactions WHERE id = ?")
            bind(input.id.uuidString, at: 1, to: version)
            let result = sqlite3_step(version)
            let nextRevision = result == SQLITE_ROW ? sqlite3_column_int64(version, 0) + 1 : 1
            sqlite3_finalize(version)

            var item = input
            item.revision = nextRevision
            item.updatedAt = Date()
            let save = try statement("""
                INSERT INTO transactions(id, kind, amount_minor, currency, merchant, account, category, note,
                    occurred_at, updated_at, deleted_at, is_demo, revision, source_event_id,
                    subcategory, eur_minor, exchange_rate_eur, personal_expense_eur_minor,
                    recoverable_eur_minor, trip_id, paid_by, affects_my_accounts,
                    source_movement_id, source_sheet, source_row, source_occurred_at, source_kind)
                VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET kind=excluded.kind, amount_minor=excluded.amount_minor,
                    currency=excluded.currency, merchant=excluded.merchant, account=excluded.account,
                    category=excluded.category, note=excluded.note, occurred_at=excluded.occurred_at,
                    updated_at=excluded.updated_at, deleted_at=excluded.deleted_at,
                    is_demo=excluded.is_demo, revision=excluded.revision, source_event_id=excluded.source_event_id,
                    subcategory=excluded.subcategory, eur_minor=excluded.eur_minor,
                    exchange_rate_eur=excluded.exchange_rate_eur,
                    personal_expense_eur_minor=excluded.personal_expense_eur_minor,
                    recoverable_eur_minor=excluded.recoverable_eur_minor, trip_id=excluded.trip_id,
                    paid_by=excluded.paid_by, affects_my_accounts=excluded.affects_my_accounts,
                    source_movement_id=excluded.source_movement_id, source_sheet=excluded.source_sheet,
                    source_row=excluded.source_row, source_occurred_at=excluded.source_occurred_at,
                    source_kind=excluded.source_kind
                """)
            bind(item.id.uuidString, at: 1, to: save)
            bind(item.kind.rawValue, at: 2, to: save)
            sqlite3_bind_int64(save, 3, item.amountMinor)
            bind(item.currency, at: 4, to: save)
            bind(item.merchant, at: 5, to: save)
            bind(item.account, at: 6, to: save)
            bind(item.category, at: 7, to: save)
            bind(item.note, at: 8, to: save)
            sqlite3_bind_double(save, 9, item.occurredAt.timeIntervalSince1970)
            sqlite3_bind_double(save, 10, item.updatedAt.timeIntervalSince1970)
            if let deletedAt = item.deletedAt { sqlite3_bind_double(save, 11, deletedAt.timeIntervalSince1970) }
            else { sqlite3_bind_null(save, 11) }
            sqlite3_bind_int(save, 12, item.isDemo ? 1 : 0)
            sqlite3_bind_int64(save, 13, item.revision)
            if let sourceEventID = item.sourceEventID { bind(sourceEventID.uuidString, at: 14, to: save) }
            else { sqlite3_bind_null(save, 14) }
            bindOptional(item.subcategory, at: 15, to: save)
            bindOptional(item.eurMinor, at: 16, to: save)
            bindOptional(item.exchangeRateEUR, at: 17, to: save)
            bindOptional(item.personalExpenseEURMinor, at: 18, to: save)
            bindOptional(item.recoverableEURMinor, at: 19, to: save)
            bindOptional(item.tripID, at: 20, to: save)
            bindOptional(item.paidBy, at: 21, to: save)
            bindOptional(item.affectsMyAccounts.map { $0 ? Int64(1) : Int64(0) }, at: 22, to: save)
            bindOptional(item.sourceMovementID, at: 23, to: save)
            bindOptional(item.sourceSheet, at: 24, to: save)
            bindOptional(item.sourceRow.map(Int64.init), at: 25, to: save)
            bindOptional(item.sourceOccurredAt, at: 26, to: save)
            bindOptional(item.sourceKind, at: 27, to: save)
            let saveResult = sqlite3_step(save)
            sqlite3_finalize(save)
            guard saveResult == SQLITE_DONE else { throw error() }

            let action = item.deletedAt == nil ? (nextRevision == 1 ? "create" : "update") : "delete"
            let payload = String(data: try JSONEncoder().encode(item), encoding: .utf8)!
            let operation = try statement("INSERT INTO operations VALUES (?, ?, ?, ?, ?, ?)")
            bind(UUID().uuidString, at: 1, to: operation)
            bind(item.id.uuidString, at: 2, to: operation)
            bind(action, at: 3, to: operation)
            sqlite3_bind_int64(operation, 4, item.revision)
            bind(payload, at: 5, to: operation)
            sqlite3_bind_double(operation, 6, item.updatedAt.timeIntervalSince1970)
            let operationResult = sqlite3_step(operation)
            sqlite3_finalize(operation)
            guard operationResult == SQLITE_DONE else { throw error() }
            if manageTransaction { try execute("COMMIT") }
            return item
        } catch {
            if manageTransaction { try? execute("ROLLBACK") }
            throw error
        }
    }

    func transactions(includeDeleted: Bool = false) throws -> [Transaction] {
        let query = "SELECT * FROM transactions" + (includeDeleted ? "" : " WHERE deleted_at IS NULL") + " ORDER BY occurred_at DESC"
        let statement = try statement(query)
        defer { sqlite3_finalize(statement) }
        var items: [Transaction] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(statement, 0)),
                  let kind = TransactionKind(rawValue: string(statement, 1)) else { continue }
            var item = Transaction(id: id, kind: kind, amountMinor: sqlite3_column_int64(statement, 2),
                                     currency: string(statement, 3), merchant: string(statement, 4),
                                     account: string(statement, 5), category: string(statement, 6), note: string(statement, 7),
                                     occurredAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8)),
                                     updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
                                     deletedAt: sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 10)),
                                     isDemo: sqlite3_column_int(statement, 11) != 0, revision: sqlite3_column_int64(statement, 12),
                                     sourceEventID: UUID(uuidString: string(statement, 13)))
            item.subcategory = optionalString(statement, 14)
            item.eurMinor = optionalInt(statement, 15)
            item.exchangeRateEUR = optionalString(statement, 16)
            item.personalExpenseEURMinor = optionalInt(statement, 17)
            item.recoverableEURMinor = optionalInt(statement, 18)
            item.tripID = optionalString(statement, 19)
            item.paidBy = optionalString(statement, 20)
            item.affectsMyAccounts = optionalInt(statement, 21).map { $0 != 0 }
            item.sourceMovementID = optionalString(statement, 22)
            item.sourceSheet = optionalString(statement, 23)
            item.sourceRow = optionalInt(statement, 24).map(Int.init)
            item.sourceOccurredAt = optionalString(statement, 25)
            item.sourceKind = optionalString(statement, 26)
            items.append(item)
        }
        return items
    }

    @discardableResult func insertEvent(_ event: NotificationEvent) throws -> Bool {
        let statement = try statement("INSERT OR IGNORE INTO notification_events VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        bind(event.id.uuidString, at: 1, to: statement)
        bind(event.sourceApp, at: 2, to: statement)
        bind(event.title, at: 3, to: statement)
        bind(event.subtitle, at: 4, to: statement)
        bind(event.message, at: 5, to: statement)
        if let date = event.receivedAt { sqlite3_bind_double(statement, 6, date.timeIntervalSince1970) }
        else { sqlite3_bind_null(statement, 6) }
        sqlite3_bind_double(statement, 7, event.capturedAt.timeIntervalSince1970)
        bind(event.fingerprint, at: 8, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw error() }
        return sqlite3_changes(handle) > 0
    }

    func notificationEvents() throws -> [NotificationEvent] {
        let statement = try statement("SELECT * FROM notification_events ORDER BY captured_at DESC")
        defer { sqlite3_finalize(statement) }
        var events: [NotificationEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(statement, 0)) else { continue }
            events.append(NotificationEvent(id: id, sourceApp: string(statement, 1), title: string(statement, 2),
                                            subtitle: string(statement, 3), message: string(statement, 4),
                                            receivedAt: sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                                            capturedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                                            fingerprint: string(statement, 7)))
        }
        return events
    }

    func operations() throws -> [LedgerOperation] {
        let statement = try statement("SELECT * FROM operations ORDER BY created_at")
        defer { sqlite3_finalize(statement) }
        var items: [LedgerOperation] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(statement, 0)), let entityID = UUID(uuidString: string(statement, 1)) else { continue }
            items.append(LedgerOperation(id: id, entityID: entityID, action: string(statement, 2),
                                         revision: sqlite3_column_int64(statement, 3), payloadJSON: string(statement, 4),
                                         createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))))
        }
        return items
    }

    private enum SQLValue {
        case text(String?)
        case integer(Int64?)
    }

    private func insert(into table: String, columns: [String], values: [SQLValue]) throws {
        precondition(columns.count == values.count)
        let placeholders = Array(repeating: "?", count: values.count).joined(separator: ",")
        let stmt = try statement("INSERT INTO \(table)(\(columns.joined(separator: ","))) VALUES(\(placeholders))")
        defer { sqlite3_finalize(stmt) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let text): bindOptional(text, at: index, to: stmt)
            case .integer(let number): bindOptional(number, at: index, to: stmt)
            }
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
    }

    private func metadata(_ key: String) throws -> String? {
        let stmt = try statement("SELECT value FROM metadata WHERE key=?")
        defer { sqlite3_finalize(stmt) }
        bind(key, at: 1, to: stmt)
        return sqlite3_step(stmt) == SQLITE_ROW ? string(stmt, 0) : nil
    }

    func historicalImportPreview(_ seed: ValidatedSeed) throws -> HistoricalImportPreview {
        let stmt = try statement("SELECT source_id,source_fingerprint FROM historical_imported_movements")
        defer { sqlite3_finalize(stmt) }
        var existing: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW { existing[string(stmt, 0)] = string(stmt, 1) }
        var duplicate = 0
        var changed = 0
        for movement in seed.movements {
            if let old = existing[movement.transaction.sourceMovementID ?? ""] {
                if old == movement.sourceFingerprint { duplicate += 1 }
                else { changed += 1 }
            }
        }
        let sourceChanged = try metadata("historical_import_digest").map { $0 != seed.digest } ?? false
        return HistoricalImportPreview(movements: seed.movements.count,
                                       newMovements: seed.movements.count - duplicate - changed,
                                       alreadyImported: duplicate, changedIdentities: changed,
                                       accounts: seed.accounts.count, trips: seed.trips.count,
                                       recurringRules: seed.rules.count, exchangeRates: seed.rates.count,
                                       migrationWarnings: seed.warnings.count,
                                       unmatchedAccountLabels: seed.unmatchedAccountLabels,
                                       missingAccountLabels: seed.missingAccountLabels,
                                       sourceChanged: sourceChanged)
    }

    @discardableResult func importHistoricalSeed(_ seed: ValidatedSeed) throws -> HistoricalImportPreview {
        try execute("BEGIN IMMEDIATE")
        do {
            let preview = try historicalImportPreview(seed)
            guard preview.canImport else { throw SeedImportError.changedSource(preview.changedIdentities + (preview.sourceChanged ? 1 : 0)) }
            if preview.newMovements == 0 {
                try execute("COMMIT")
                return preview
            }
            try execute("DELETE FROM operations WHERE entity_id IN (SELECT id FROM transactions WHERE is_demo=1)")
            try execute("DELETE FROM transactions WHERE is_demo=1")

            for account in seed.accounts {
                try insert(into: "historical_accounts",
                           columns: ["source_name", "kind", "currency", "opening_at", "opening_eur_minor", "is_active", "note", "source_sheet", "source_row", "cell_values_json"],
                           values: [.text(account.sourceName), .text(account.kind), .text(account.currency),
                                    .text(account.openingAt), .integer(account.openingEURMinor),
                                    .integer(account.isActive.map { $0 ? 1 : 0 }), .text(account.note),
                                    .text(account.sourceSheet), .integer(Int64(account.sourceRow)), .text(account.cellValuesJSON)])
            }
            for trip in seed.trips {
                try insert(into: "historical_trips",
                           columns: ["id", "name", "destination", "starts_at", "ends_at", "currency", "note", "source_sheet", "source_row", "cell_values_json"],
                           values: [.text(trip.id), .text(trip.name), .text(trip.destination), .text(trip.startsAt),
                                    .text(trip.endsAt), .text(trip.currency), .text(trip.note), .text(trip.sourceSheet),
                                    .integer(Int64(trip.sourceRow)), .text(trip.cellValuesJSON)])
            }
            for rule in seed.rules {
                try insert(into: "historical_recurring_rules",
                           columns: ["id", "rule_kind", "name", "amount_minor", "currency", "frequency", "nominal_day", "starts_at", "ends_at", "account", "is_active", "investment_kind", "date_rule", "initial_contribution_minor", "initial_contribution_at", "note", "source_sheet", "source_row", "cell_values_json"],
                           values: [.text(rule.id), .text(rule.ruleKind), .text(rule.name), .integer(rule.amountMinor),
                                    .text(rule.currency), .text(rule.frequency), .integer(rule.nominalDay.map(Int64.init)),
                                    .text(rule.startsAt), .text(rule.endsAt), .text(rule.account),
                                    .integer(rule.isActive.map { $0 ? 1 : 0 }), .text(rule.investmentKind),
                                    .text(rule.dateRule), .integer(rule.initialContributionMinor),
                                    .text(rule.initialContributionAt), .text(rule.note), .text(rule.sourceSheet),
                                    .integer(Int64(rule.sourceRow)), .text(rule.cellValuesJSON)])
            }
            for rate in seed.rates {
                try insert(into: "historical_exchange_rates",
                           columns: ["source_row", "date", "currency", "eur_rate", "status", "origin", "source_key", "cell_values_json"],
                           values: [.integer(Int64(rate.sourceRow)), .text(rate.date), .text(rate.currency),
                                    .text(rate.eurRate), .text(rate.status), .text(rate.origin), .text(rate.sourceKey),
                                    .text(rate.cellValuesJSON)])
            }
            for row in seed.sourceRows {
                try insert(into: "historical_source_rows", columns: ["source_sheet", "source_row", "cell_values_json"],
                           values: [.text(row.sheet), .integer(Int64(row.row)), .text(row.cellValuesJSON)])
            }
            for warning in seed.warnings {
                try insert(into: "historical_import_warnings", columns: ["source_sheet", "source_row", "code", "detail"],
                           values: [.text(warning.sheet), .integer(Int64(warning.row)), .text(warning.code), .text(warning.detail)])
            }
            for movement in seed.movements {
                let item = movement.transaction
                try save(item, manageTransaction: false)
                try insert(into: "historical_imported_movements",
                           columns: ["source_id", "transaction_id", "source_fingerprint", "source_sheet", "source_row", "source_payload_json"],
                           values: [.text(item.sourceMovementID), .text(item.id.uuidString),
                                    .text(movement.sourceFingerprint), .text(item.sourceSheet),
                                    .integer(item.sourceRow.map(Int64.init)), .text(movement.sourcePayloadJSON)])
            }
            try insert(into: "metadata", columns: ["key", "value"],
                       values: [.text("historical_import_digest"), .text(seed.digest)])
            try insert(into: "metadata", columns: ["key", "value"],
                       values: [.text("historical_import_format_version"), .text("1")])
            try execute("COMMIT")
            return preview
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func historicalCounts() throws -> [String: Int] {
        let tables = ["historical_imported_movements", "historical_accounts", "historical_trips",
                      "historical_recurring_rules", "expected_occurrences", "historical_exchange_rates", "historical_source_rows",
                      "historical_import_warnings"]
        var result: [String: Int] = [:]
        for table in tables {
            let stmt = try statement("SELECT COUNT(*) FROM \(table)")
            guard sqlite3_step(stmt) == SQLITE_ROW else { sqlite3_finalize(stmt); throw error() }
            result[table] = Int(sqlite3_column_int64(stmt, 0))
            sqlite3_finalize(stmt)
        }
        return result
    }

    func historicalAccounts() throws -> [HistoricalAccount] {
        let stmt = try statement("SELECT source_name,kind,currency,opening_at,opening_eur_minor,is_active,note,source_sheet,source_row,cell_values_json FROM historical_accounts ORDER BY source_name")
        defer { sqlite3_finalize(stmt) }
        var result: [HistoricalAccount] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(HistoricalAccount(sourceName: string(stmt, 0), kind: optionalString(stmt, 1),
                                            currency: optionalString(stmt, 2), openingAt: optionalString(stmt, 3),
                                            openingEURMinor: optionalInt(stmt, 4),
                                            isActive: optionalInt(stmt, 5).map { $0 != 0 }, note: optionalString(stmt, 6),
                                            sourceSheet: string(stmt, 7), sourceRow: Int(sqlite3_column_int64(stmt, 8)),
                                            cellValuesJSON: string(stmt, 9)))
        }
        return result
    }

    func historicalTrips() throws -> [HistoricalTrip] {
        let stmt = try statement("SELECT id,name,destination,starts_at,ends_at,currency,note,source_sheet,source_row,cell_values_json FROM historical_trips ORDER BY name")
        defer { sqlite3_finalize(stmt) }
        var result: [HistoricalTrip] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(HistoricalTrip(id: string(stmt, 0), name: string(stmt, 1),
                                         destination: optionalString(stmt, 2), startsAt: optionalString(stmt, 3),
                                         endsAt: optionalString(stmt, 4), currency: optionalString(stmt, 5),
                                         note: optionalString(stmt, 6), sourceSheet: string(stmt, 7),
                                         sourceRow: Int(sqlite3_column_int64(stmt, 8)), cellValuesJSON: string(stmt, 9)))
        }
        return result
    }

    func historicalRules() throws -> [HistoricalRecurringRule] {
        let stmt = try statement("SELECT id,rule_kind,name,amount_minor,currency,frequency,nominal_day,starts_at,ends_at,account,is_active,investment_kind,date_rule,initial_contribution_minor,initial_contribution_at,note,source_sheet,source_row,cell_values_json FROM historical_recurring_rules ORDER BY name")
        defer { sqlite3_finalize(stmt) }
        var result: [HistoricalRecurringRule] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(HistoricalRecurringRule(id: string(stmt, 0), ruleKind: string(stmt, 1), name: string(stmt, 2),
                                                  amountMinor: sqlite3_column_int64(stmt, 3), currency: string(stmt, 4),
                                                  frequency: optionalString(stmt, 5), nominalDay: optionalInt(stmt, 6).map(Int.init),
                                                  startsAt: optionalString(stmt, 7), endsAt: optionalString(stmt, 8),
                                                  account: optionalString(stmt, 9), isActive: optionalInt(stmt, 10).map { $0 != 0 },
                                                  investmentKind: optionalString(stmt, 11), dateRule: optionalString(stmt, 12),
                                                  initialContributionMinor: optionalInt(stmt, 13),
                                                  initialContributionAt: optionalString(stmt, 14), note: optionalString(stmt, 15),
                                                  sourceSheet: string(stmt, 16), sourceRow: Int(sqlite3_column_int64(stmt, 17)),
                                                  cellValuesJSON: string(stmt, 18)))
        }
        return result
    }

    func historicalBackup() throws -> HistoricalImportBackup? {
        guard (try historicalCounts()["historical_imported_movements"] ?? 0) > 0 else { return nil }
        let provenanceStatement = try statement("SELECT source_id,transaction_id,source_fingerprint,source_sheet,source_row,source_payload_json FROM historical_imported_movements ORDER BY source_row")
        var provenance: [HistoricalProvenanceRecord] = []
        while sqlite3_step(provenanceStatement) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(provenanceStatement, 1)) else {
                sqlite3_finalize(provenanceStatement)
                throw DatabaseError.sqlite("invalid historical provenance identifier")
            }
            provenance.append(HistoricalProvenanceRecord(sourceID: string(provenanceStatement, 0), transactionID: id,
                                                         sourceFingerprint: string(provenanceStatement, 2),
                                                         sourceSheet: string(provenanceStatement, 3),
                                                         sourceRow: Int(sqlite3_column_int64(provenanceStatement, 4)),
                                                         sourcePayloadJSON: string(provenanceStatement, 5)))
        }
        sqlite3_finalize(provenanceStatement)

        let rateStatement = try statement("SELECT source_row,date,currency,eur_rate,status,origin,source_key,cell_values_json FROM historical_exchange_rates ORDER BY source_row")
        var rates: [HistoricalExchangeRate] = []
        while sqlite3_step(rateStatement) == SQLITE_ROW {
            rates.append(HistoricalExchangeRate(sourceRow: Int(sqlite3_column_int64(rateStatement, 0)),
                                                date: string(rateStatement, 1), currency: string(rateStatement, 2),
                                                eurRate: string(rateStatement, 3), status: optionalString(rateStatement, 4),
                                                origin: optionalString(rateStatement, 5), sourceKey: optionalString(rateStatement, 6),
                                                cellValuesJSON: string(rateStatement, 7)))
        }
        sqlite3_finalize(rateStatement)

        let rawStatement = try statement("SELECT source_sheet,source_row,cell_values_json FROM historical_source_rows ORDER BY source_row")
        var rawRows: [HistoricalSourceRow] = []
        while sqlite3_step(rawStatement) == SQLITE_ROW {
            rawRows.append(HistoricalSourceRow(sheet: string(rawStatement, 0),
                                               row: Int(sqlite3_column_int64(rawStatement, 1)),
                                               cellValuesJSON: string(rawStatement, 2)))
        }
        sqlite3_finalize(rawStatement)

        let warningStatement = try statement("SELECT source_sheet,source_row,code,detail FROM historical_import_warnings ORDER BY source_row")
        var warnings: [HistoricalImportWarning] = []
        while sqlite3_step(warningStatement) == SQLITE_ROW {
            warnings.append(HistoricalImportWarning(sheet: string(warningStatement, 0),
                                                    row: Int(sqlite3_column_int64(warningStatement, 1)),
                                                    code: string(warningStatement, 2),
                                                    detail: optionalString(warningStatement, 3)))
        }
        sqlite3_finalize(warningStatement)
        return HistoricalImportBackup(sourceDigest: try metadata("historical_import_digest"),
                                      provenance: provenance, accounts: try historicalAccounts(),
                                      trips: try historicalTrips(), recurringRules: try historicalRules(),
                                      exchangeRates: rates, sourceRows: rawRows, importWarnings: warnings)
    }
}
