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
    var handle: OpaquePointer?
    let url: URL

    static func open() throws -> SQLiteDatabase {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try SQLiteDatabase(url: directory.appendingPathComponent("EasyTrack.sqlite"))
    }

    static func openReadOnly() throws -> SQLiteDatabase {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return try SQLiteDatabase(readOnlyURL: directory.appendingPathComponent("EasyTrack.sqlite"))
    }

    init(readOnlyURL: URL) throws {
        url = readOnlyURL
        guard sqlite3_open_v2(readOnlyURL.path, &handle,
                              SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            handle = nil
            throw DatabaseError.sqlite("Could not open the ledger for read-only export")
        }
        do {
            try execute("PRAGMA busy_timeout=5000")
            try execute("PRAGMA query_only=ON")
            let stmt = try statement("PRAGMA user_version")
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_int(stmt, 0) == 13 else {
                throw DatabaseError.sqlite("Ledger schema must be version 13 before export")
            }
        } catch {
            sqlite3_close(handle)
            handle = nil
            throw error
        }
    }

    init(url: URL) throws {
        self.url = url
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
            guard existingVersion <= 13 else { throw DatabaseError.sqlite("newer local database version is unsupported") }
            try execute("""
                CREATE TABLE IF NOT EXISTS transactions (
                    id TEXT PRIMARY KEY, kind TEXT NOT NULL, amount_minor INTEGER NOT NULL,
                    currency TEXT NOT NULL, merchant TEXT NOT NULL, account TEXT NOT NULL,
                    category TEXT, note TEXT NOT NULL, occurred_at REAL NOT NULL,
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
            if existingVersion < 3 {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("""
                        CREATE TABLE parser_sources (
                            id TEXT PRIMARY KEY, name TEXT NOT NULL,
                            normalized_name TEXT NOT NULL UNIQUE, created_at REAL NOT NULL
                        )
                        """)
                    try execute("""
                        CREATE TABLE parser_rules (
                            id TEXT PRIMARY KEY, source_id TEXT NOT NULL,
                            name TEXT NOT NULL, enabled INTEGER NOT NULL,
                            priority INTEGER NOT NULL, version INTEGER NOT NULL,
                            config_json TEXT NOT NULL, created_at REAL NOT NULL,
                            updated_at REAL NOT NULL, deleted_at REAL,
                            FOREIGN KEY(source_id) REFERENCES parser_sources(id)
                        )
                        """)
                    try execute("CREATE INDEX parser_rules_by_source ON parser_rules(source_id, enabled, priority)")
                    try execute("""
                        CREATE TABLE parser_rule_versions (
                            rule_id TEXT NOT NULL, version INTEGER NOT NULL,
                            config_json TEXT NOT NULL, changed_at REAL NOT NULL,
                            PRIMARY KEY(rule_id, version),
                            FOREIGN KEY(rule_id) REFERENCES parser_rules(id)
                        )
                        """)
                    try execute("""
                        CREATE TABLE notification_attempts (
                            id TEXT PRIMARY KEY, event_id TEXT NOT NULL,
                            source_id TEXT NOT NULL, raw_json TEXT NOT NULL,
                            captured_at REAL NOT NULL, status TEXT NOT NULL,
                            rule_id TEXT, rule_version INTEGER, transaction_id TEXT,
                            exact_fingerprint TEXT NOT NULL, semantic_fingerprint TEXT,
                            detail TEXT,
                            FOREIGN KEY(event_id) REFERENCES notification_events(id),
                            FOREIGN KEY(source_id) REFERENCES parser_sources(id),
                            FOREIGN KEY(transaction_id) REFERENCES transactions(id)
                        )
                        """)
                    try execute("CREATE INDEX attempts_by_source ON notification_attempts(source_id, captured_at DESC)")
                    try execute("""
                        CREATE TABLE exact_dedup (
                            id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL,
                            occurred_at REAL NOT NULL, has_payload_date INTEGER NOT NULL,
                            transaction_id TEXT NOT NULL, created_at REAL NOT NULL,
                            FOREIGN KEY(transaction_id) REFERENCES transactions(id)
                        )
                        """)
                    try execute("CREATE INDEX exact_dedup_lookup ON exact_dedup(fingerprint, occurred_at)")
                    try execute("""
                        CREATE TABLE semantic_dedup (
                            id TEXT PRIMARY KEY, semantic_key TEXT NOT NULL,
                            occurred_at REAL NOT NULL, transaction_id TEXT NOT NULL UNIQUE,
                            rule_id TEXT NOT NULL, created_at REAL NOT NULL,
                            FOREIGN KEY(transaction_id) REFERENCES transactions(id),
                            FOREIGN KEY(rule_id) REFERENCES parser_rules(id)
                        )
                        """)
                    try execute("CREATE INDEX semantic_dedup_lookup ON semantic_dedup(semantic_key, occurred_at)")
                    try execute("PRAGMA user_version=3")
                    try execute("COMMIT")
                } catch {
                    try? execute("ROLLBACK")
                    throw error
                }
            }
            if existingVersion < 4 { try migrateToSchemaFour() }
            if existingVersion < 5 { try migrateToSchemaFive() }
            if existingVersion < 6 { try migrateToSchemaSix() }
            if existingVersion < 7 { try migrateToSchemaSeven() }
            if existingVersion < 8 { try migrateToSchemaEight() }
            if existingVersion < 9 { try migrateToSchemaNine() }
            if existingVersion < 10 { try migrateToSchemaTen() }
            if existingVersion < 11 { try migrateToSchemaEleven() }
            if existingVersion < 12 { try migrateToSchemaTwelve() }
            if existingVersion < 13 { try migrateToSchemaThirteen() }
            try backfillSourceAccountsFromLegacyRules()
            try backfillLegacyNotificationEvents()
        } catch {
            sqlite3_close(handle)
            handle = nil
            throw error
        }
    }

    deinit { sqlite3_close(handle) }

    func error() -> DatabaseError {
        DatabaseError.sqlite(String(cString: sqlite3_errmsg(handle)))
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }

    func ensureColumn(_ name: String, type: String, in table: String) throws {
        let columns = try statement("PRAGMA table_info(\(table))")
        var present = false
        while sqlite3_step(columns) == SQLITE_ROW {
            if string(columns, 1) == name { present = true; break }
        }
        sqlite3_finalize(columns)
        if !present { try execute("ALTER TABLE \(table) ADD COLUMN \(name) \(type)") }
    }

    private func migrateToSchemaTwelve() throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try ensureColumn("eur_value_source", type: "TEXT", in: "transactions")
            try ensureColumn("exchange_rate_date", type: "TEXT", in: "transactions")
            try ensureColumn("exchange_rate_provider", type: "TEXT", in: "transactions")
            try execute("""
                UPDATE transactions SET eur_value_source=CASE
                    WHEN eur_minor IS NULL AND currency!='EUR' THEN NULL
                    WHEN currency='EUR' THEN 'confirmed'
                    ELSE 'historical' END
                WHERE eur_value_source IS NULL
                """)
            try execute("PRAGMA user_version=12")
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    private func migrateToSchemaThirteen() throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try ensureColumn("native_currency", type: "TEXT NOT NULL DEFAULT 'EUR'", in: "local_accounts")
            try ensureColumn("account_amount_minor", type: "INTEGER", in: "transactions")
            try ensureColumn("account_currency", type: "TEXT", in: "transactions")
            try execute("""
                UPDATE transactions SET account_amount_minor=amount_minor,account_currency=currency
                WHERE account_amount_minor IS NULL AND account_currency IS NULL
                """)
            try execute("PRAGMA user_version=13")
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    private func migrateToSchemaFour() throws {
        // A nullable category requires a table rebuild for databases created by schema 2/3.
        // Foreign keys are checked again before the migration commits.
        try execute("PRAGMA foreign_keys=OFF")
        do {
            try execute("BEGIN IMMEDIATE")
            try execute("""
                CREATE TABLE IF NOT EXISTS local_accounts (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL,
                    normalized_name TEXT NOT NULL UNIQUE, created_at REAL NOT NULL
                )
                """)
            try ensureColumn("account_id", type: "TEXT REFERENCES local_accounts(id)", in: "parser_sources")
            let columns = try statement("PRAGMA table_info(transactions)")
            var rebuild = false
            while sqlite3_step(columns) == SQLITE_ROW {
                if string(columns, 1) == "category" { rebuild = sqlite3_column_int(columns, 3) != 0; break }
            }
            sqlite3_finalize(columns)
            if rebuild {
                try execute("""
                    CREATE TABLE transactions_v4 (
                        id TEXT PRIMARY KEY, kind TEXT NOT NULL, amount_minor INTEGER NOT NULL,
                        currency TEXT NOT NULL, merchant TEXT NOT NULL, account TEXT NOT NULL,
                        category TEXT, note TEXT NOT NULL, occurred_at REAL NOT NULL,
                        updated_at REAL NOT NULL, deleted_at REAL, is_demo INTEGER NOT NULL,
                        revision INTEGER NOT NULL, source_event_id TEXT, subcategory TEXT,
                        eur_minor INTEGER, exchange_rate_eur TEXT,
                        personal_expense_eur_minor INTEGER, recoverable_eur_minor INTEGER,
                        trip_id TEXT, paid_by TEXT, affects_my_accounts INTEGER,
                        source_movement_id TEXT, source_sheet TEXT, source_row INTEGER,
                        source_occurred_at TEXT, source_kind TEXT
                    )
                    """)
                try execute("""
                    INSERT INTO transactions_v4
                    SELECT id,kind,amount_minor,currency,merchant,account,
                        CASE WHEN trim(category)='' THEN NULL ELSE category END,
                        note,occurred_at,updated_at,deleted_at,is_demo,revision,source_event_id,
                        subcategory,eur_minor,exchange_rate_eur,personal_expense_eur_minor,
                        recoverable_eur_minor,trip_id,paid_by,affects_my_accounts,
                        source_movement_id,source_sheet,source_row,source_occurred_at,source_kind
                    FROM transactions
                    """)
                try execute("DROP TABLE transactions")
                try execute("ALTER TABLE transactions_v4 RENAME TO transactions")
                try execute("CREATE INDEX transactions_by_date ON transactions(occurred_at DESC)")
                try execute("CREATE UNIQUE INDEX unique_active_source_event ON transactions(source_event_id) WHERE deleted_at IS NULL AND source_event_id IS NOT NULL")
                try execute("CREATE UNIQUE INDEX unique_source_movement ON transactions(source_movement_id) WHERE source_movement_id IS NOT NULL")
            }
            let check = try statement("PRAGMA foreign_key_check")
            let brokenReference = sqlite3_step(check) == SQLITE_ROW
            sqlite3_finalize(check)
            guard !brokenReference else { throw DatabaseError.sqlite("schema migration found a broken data link") }
            try execute("PRAGMA user_version=4")
            try execute("COMMIT")
            try execute("PRAGMA foreign_keys=ON")
        } catch {
            try? execute("ROLLBACK")
            try? execute("PRAGMA foreign_keys=ON")
            throw error
        }
    }

    func statement(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw error() }
        return statement
    }

    func bind(_ text: String, at index: Int32, to statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
    }

    func bindOptional(_ value: String?, at index: Int32, to statement: OpaquePointer) {
        if let value { bind(value, at: index, to: statement) }
        else { sqlite3_bind_null(statement, index) }
    }

    func bindOptional(_ value: Int64?, at index: Int32, to statement: OpaquePointer) {
        if let value { sqlite3_bind_int64(statement, index, value) }
        else { sqlite3_bind_null(statement, index) }
    }

    func string(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    func optionalString(_ statement: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : string(statement, index)
    }

    func optionalInt(_ statement: OpaquePointer, _ index: Int32) -> Int64? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, index)
    }

    func appPreference(_ key: String) throws -> String? {
        let query = try statement("SELECT value FROM metadata WHERE key=?")
        defer { sqlite3_finalize(query) }
        bind("preference.\(key)", at: 1, to: query)
        return sqlite3_step(query) == SQLITE_ROW ? string(query, 0) : nil
    }

    func setAppPreference(_ value: String, for key: String) throws {
        let save = try statement("INSERT OR REPLACE INTO metadata(key,value) VALUES(?,?)")
        defer { sqlite3_finalize(save) }
        bind("preference.\(key)", at: 1, to: save)
        bind(value, at: 2, to: save)
        guard sqlite3_step(save) == SQLITE_DONE else { throw error() }
    }

    func automationSetupMilestones() throws -> Set<AutomationSetupMilestone> {
        guard let value = try appPreference("automationSetupMilestones"),
              let data = value.data(using: .utf8),
              let rawValues = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(rawValues.compactMap(AutomationSetupMilestone.init(rawValue:)))
    }

    func markAutomationSetupMilestone(_ milestone: AutomationSetupMilestone) throws {
        var milestones = try automationSetupMilestones()
        milestones.insert(milestone)
        let values = milestones.map(\.rawValue).sorted()
        let data = try JSONEncoder().encode(values)
        guard let value = String(data: data, encoding: .utf8) else {
            throw DatabaseError.sqlite("Could not save notification setup progress")
        }
        try setAppPreference(value, for: "automationSetupMilestones")
    }

    func appearancePreferences() throws -> AppearancePreferences {
        guard let value = try appPreference("appearance"),
              let data = value.data(using: .utf8),
              let preferences = try? JSONDecoder().decode(AppearancePreferences.self, from: data) else {
            return .default
        }
        return preferences
    }

    func saveAppearancePreferences(_ preferences: AppearancePreferences) throws {
        let data = try JSONEncoder().encode(preferences)
        guard let value = String(data: data, encoding: .utf8) else {
            throw DatabaseError.sqlite("Could not save appearance settings")
        }
        try setAppPreference(value, for: "appearance")
    }

    func backupReminderPreferences() throws -> BackupReminderPreferences {
        guard let value = try appPreference("backupReminder"),
              let data = value.data(using: .utf8),
              let preferences = try? JSONDecoder().decode(BackupReminderPreferences.self, from: data) else {
            return .default
        }
        return preferences
    }

    func saveBackupReminderPreferences(_ preferences: BackupReminderPreferences) throws {
        let data = try JSONEncoder().encode(preferences)
        guard let value = String(data: data, encoding: .utf8) else {
            throw DatabaseError.sqlite("Could not save backup reminder settings")
        }
        try setAppPreference(value, for: "backupReminder")
    }

    func shouldPresentOnboarding() throws -> Bool {
        if let value = try appPreference("onboardingCompleted") { return value != "true" }
        let query = try statement("""
            SELECT
                EXISTS(SELECT 1 FROM transactions WHERE is_demo=0) OR
                EXISTS(SELECT 1 FROM local_accounts) OR
                EXISTS(SELECT 1 FROM parser_sources) OR
                EXISTS(SELECT 1 FROM historical_imported_movements)
            """)
        defer { sqlite3_finalize(query) }
        guard sqlite3_step(query) == SQLITE_ROW else { throw error() }
        let existingInstallation = sqlite3_column_int(query, 0) != 0
        if existingInstallation { try setAppPreference("true", for: "onboardingCompleted") }
        return !existingInstallation
    }

    func completeOnboarding() throws {
        try setAppPreference("true", for: "onboardingCompleted")
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
            try prepareReimbursementDeletion(input)
            let input = try reimbursementAdjusted(input)
            if input.deletedAt == nil, let occurrenceID = input.recurringOccurrenceID,
               let occurrence = try recurringOccurrences().first(where: { $0.id == occurrenceID }),
               occurrence.status == .confirmed,
               let rule = try recurringRules(includeArchived: true).first(where: { $0.id == occurrence.ruleID }),
               (input.accountID != rule.accountID || input.kind != rule.type.transactionKind) {
                throw RecurringError.linkRequiresUnlink
            }
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
                    source_movement_id, source_sheet, source_row, source_occurred_at, source_kind,
                    account_id, category_id, recurring_occurrence_id,eur_value_source,
                    exchange_rate_date,exchange_rate_provider,account_amount_minor,account_currency)
                VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                    source_kind=excluded.source_kind, account_id=excluded.account_id,
                    category_id=excluded.category_id,
                    recurring_occurrence_id=excluded.recurring_occurrence_id,
                    eur_value_source=excluded.eur_value_source,
                    exchange_rate_date=excluded.exchange_rate_date,
                    exchange_rate_provider=excluded.exchange_rate_provider,
                    account_amount_minor=excluded.account_amount_minor,
                    account_currency=excluded.account_currency
                """)
            bind(item.id.uuidString, at: 1, to: save)
            bind(item.kind.rawValue, at: 2, to: save)
            sqlite3_bind_int64(save, 3, item.amountMinor)
            bind(item.currency, at: 4, to: save)
            bind(item.merchant, at: 5, to: save)
            bind(item.account, at: 6, to: save)
            bindOptional(item.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : item.category,
                         at: 7, to: save)
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
            bindOptional(item.accountID?.uuidString, at: 28, to: save)
            bindOptional(item.categoryID?.uuidString, at: 29, to: save)
            bindOptional(item.recurringOccurrenceID, at: 30, to: save)
            bindOptional(item.eurValueSource?.rawValue, at: 31, to: save)
            bindOptional(item.exchangeRateDate, at: 32, to: save)
            bindOptional(item.exchangeRateProvider, at: 33, to: save)
            bindOptional(item.accountAmountMinor, at: 34, to: save)
            bindOptional(item.accountCurrency, at: 35, to: save)
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
            if item.deletedAt != nil, let occurrenceID = item.recurringOccurrenceID,
               let occurrence = try recurringOccurrences().first(where: {
                   $0.id == occurrenceID && $0.transactionID == item.id
               }), let rule = try recurringRules(includeArchived: true).first(where: { $0.id == occurrence.ruleID }) {
                try setOccurrence(occurrence, status: .expected, transactionID: nil,
                                  provisionalID: item.id,
                                  reviewReason: "The linked transaction was deleted; review before recording.")
                try rejectConfirmedCandidates(for: occurrenceID)
                try appendReconciliationAudit(occurrenceID: occurrenceID, action: "delete-linked",
                                              actor: "user", oldStatus: occurrence.status,
                                              newStatus: .expected, oldTransactionID: item.id,
                                              newTransactionID: nil, ruleRevision: rule.revision)
            }
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
            item.accountID = UUID(uuidString: string(statement, 27))
            item.categoryID = UUID(uuidString: string(statement, 28))
            item.recurringOccurrenceID = optionalString(statement, 29)
            item.eurValueSource = optionalString(statement, 30).flatMap(EURValueSource.init(rawValue:))
            item.exchangeRateDate = optionalString(statement, 31)
            item.exchangeRateProvider = optionalString(statement, 32)
            item.accountAmountMinor = optionalInt(statement, 33)
            item.accountCurrency = optionalString(statement, 34)
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

    func notificationRetentionDays() throws -> Int {
        guard let value = try appPreference("notificationRetentionDays"),
              let days = Int(value), NotificationRetentionPolicy.supportedDays.contains(days) else {
            return NotificationRetentionPolicy.defaultDays
        }
        return days
    }

    @discardableResult
    func setNotificationRetentionDays(_ days: Int, now: Date = .now) throws -> Int {
        guard NotificationRetentionPolicy.supportedDays.contains(days) else {
            throw ParserValidationError.invalidRule("Choose 0, 7, 30, or 90 days of diagnostic retention.")
        }
        try setAppPreference(String(days), for: "notificationRetentionDays")
        return try purgeExpiredNotificationContents(now: now)
    }

    @discardableResult
    func purgeExpiredNotificationContents(now: Date = .now) throws -> Int {
        let days = try notificationRetentionDays()
        let cutoff = days == 0 ? now : now.addingTimeInterval(-Double(days) * 86_400)
        return try scrubNotificationContents(before: cutoff)
    }

    @discardableResult
    func clearNotificationDiagnosticContents() throws -> Int {
        try scrubNotificationContents(before: nil)
    }

    private func scrubNotificationContents(before cutoff: Date?) throws -> Int {
        let suffix = cutoff == nil ? "" : " WHERE captured_at<?"
        let query = try statement("SELECT id,raw_json FROM notification_attempts\(suffix)")
        if let cutoff { sqlite3_bind_double(query, 1, cutoff.timeIntervalSince1970) }
        var sanitized: [(String, String)] = []
        while sqlite3_step(query) == SQLITE_ROW {
            let id = string(query, 0)
            guard var event = try? JSONDecoder().decode(NotificationEvent.self,
                                                        from: Data(string(query, 1).utf8)),
                  !event.title.isEmpty || !event.subtitle.isEmpty || !event.message.isEmpty else { continue }
            event.title = ""
            event.subtitle = ""
            event.message = ""
            if let data = try? JSONEncoder().encode(event), let json = String(data: data, encoding: .utf8) {
                sanitized.append((id, json))
            }
        }
        sqlite3_finalize(query)
        try execute("BEGIN IMMEDIATE")
        do {
            for (id, json) in sanitized {
                let update = try statement("UPDATE notification_attempts SET raw_json=? WHERE id=?")
                bind(json, at: 1, to: update)
                bind(id, at: 2, to: update)
                guard sqlite3_step(update) == SQLITE_DONE else { sqlite3_finalize(update); throw error() }
                sqlite3_finalize(update)
            }
            let contentFilter = cutoff == nil
                ? " WHERE title!='' OR subtitle!='' OR message!=''"
                : " WHERE captured_at<? AND (title!='' OR subtitle!='' OR message!='')"
            let eventUpdate = try statement("UPDATE notification_events SET title='',subtitle='',message=''" + contentFilter)
            if let cutoff { sqlite3_bind_double(eventUpdate, 1, cutoff.timeIntervalSince1970) }
            guard sqlite3_step(eventUpdate) == SQLITE_DONE else { sqlite3_finalize(eventUpdate); throw error() }
            let eventCount = Int(sqlite3_changes(handle))
            sqlite3_finalize(eventUpdate)
            try execute("COMMIT")
            return max(sanitized.count, eventCount)
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
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
        var preview = HistoricalImportPreview(movements: seed.movements.count,
                                       newMovements: seed.movements.count - duplicate - changed,
                                       alreadyImported: duplicate, changedIdentities: changed,
                                       accounts: seed.accounts.count, trips: seed.trips.count,
                                       recurringRules: seed.rules.count, exchangeRates: seed.rates.count,
                                       migrationWarnings: seed.warnings.count,
                                       unmatchedAccountLabels: seed.unmatchedAccountLabels,
                                       missingAccountLabels: seed.missingAccountLabels,
                                       sourceChanged: sourceChanged)
        if preview.newMovements > 0 && preview.canImport {
            preview.recurringConflicts = try historicalImportConflicts(seed)
            preview.incomingTotals = LedgerTotals(transactions: seed.movements.map(\.transaction))
        }
        return preview
    }

    func historicalImportConflicts(_ seed: ValidatedSeed) throws -> [HistoricalImportConflict] {
        let alreadyImported = Set(try transactions(includeDeleted: true).compactMap(\.sourceMovementID))
        let actuals = seed.movements.map(\.transaction).filter {
            $0.sourceMovementID.map { !alreadyImported.contains($0) } ?? true
        }
        let active = try transactions()
        let rules = Dictionary(uniqueKeysWithValues: try recurringRules(includeArchived: true).map { ($0.id, $0) })
        let accounts = Dictionary(uniqueKeysWithValues: try localAccounts().map { ($0.id, $0) })
        var conflicts: [HistoricalImportConflict] = []
        for occurrence in try recurringOccurrences() where
            occurrence.status == .legacyCounted || occurrence.status == .recordedManual {
            guard let rule = rules[occurrence.ruleID], let oldID = occurrence.transactionID,
                  let old = active.first(where: { $0.id == oldID }),
                  let account = accounts[rule.accountID] else { continue }
            let zone = try RecurringSchedule.timeZone(for: rule)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            guard let due = occurrence.scheduledDay.noon(in: zone) else { continue }
            let aliases = Set(try recurringPayeeAliases(ruleID: rule.id))
            for actual in actuals where actual.kind == rule.type.transactionKind && !actual.isDemo {
                if let managedID = actual.accountID, managedID != rule.accountID { continue }
                let actualDay = LocalDay(date: actual.occurredAt, timeZone: zone)
                guard let noon = actualDay.noon(in: zone),
                      let distance = calendar.dateComponents([.day], from: due, to: noon).day,
                      abs(distance) <= rule.reviewWindowDays else { continue }
                let payee = NotificationParser.normalize(actual.merchant)
                let amount = actual.eurMinor ?? (actual.currency == "EUR" ? actual.amountMinor : 0)
                let exactAmount = amount == (old.eurMinor ?? old.amountMinor)
                let named = payee == NotificationParser.normalize(rule.name) || aliases.contains(payee)
                guard exactAmount || named else { continue }
                let reason = actual.accountID == nil ?
                    "Historical account label is not linked to a managed account; confirm the identity." :
                    (exactAmount ? "Same account, kind, date window and EUR amount." :
                     "Same approved payee with a different amount.")
                conflicts.append(HistoricalImportConflict(occurrenceID: occurrence.id,
                    ruleName: rule.name, managedAccountName: account.name,
                    imported: actual, counted: old, reason: reason))
            }
        }
        return conflicts.sorted { $0.id < $1.id }
    }

    @discardableResult func importHistoricalSeed(_ seed: ValidatedSeed,
        decisions: [String: HistoricalImportDecision] = [:]) throws -> HistoricalImportPreview {
        try execute("BEGIN IMMEDIATE")
        do {
            let preview = try historicalImportPreview(seed)
            guard preview.canImport else { throw SeedImportError.changedSource(preview.changedIdentities + (preview.sourceChanged ? 1 : 0)) }
            let conflicts = preview.recurringConflicts
            let ids = Set(conflicts.map(\.id))
            guard Set(decisions.keys) == ids else {
                throw SeedImportError.database("Resolve every recurring overlap in the collective preview before importing.")
            }
            let same = conflicts.filter { decisions[$0.id] == .samePayment }
            guard Set(same.map(\.occurrenceID)).count == same.count,
                  Set(same.map { $0.imported.id }).count == same.count else {
                throw SeedImportError.database("One payment cannot settle multiple recurring occurrences.")
            }
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
                var item = movement.transaction
                if let chosen = same.first(where: { $0.imported.id == item.id }),
                   let occurrence = try recurringOccurrences().first(where: { $0.id == chosen.occurrenceID }),
                   let rule = try recurringRules(includeArchived: true).first(where: { $0.id == occurrence.ruleID }) {
                    item.accountID = rule.accountID // explicit user confirmation; original label stays intact
                }
                try save(item, manageTransaction: false)
                try insert(into: "historical_imported_movements",
                           columns: ["source_id", "transaction_id", "source_fingerprint", "source_sheet", "source_row", "source_payload_json"],
                           values: [.text(item.sourceMovementID), .text(item.id.uuidString),
                                    .text(movement.sourceFingerprint), .text(item.sourceSheet),
                                    .integer(item.sourceRow.map(Int64.init)), .text(movement.sourcePayloadJSON)])
            }
            for chosen in same {
                try linkRecurringTransactionInTransaction(chosen.imported.id,
                                                          to: chosen.occurrenceID, actor: "import-review")
            }
            try insert(into: "metadata", columns: ["key", "value"],
                       values: [.text("historical_import_digest"), .text(seed.digest)])
            try insert(into: "metadata", columns: ["key", "value"],
                       values: [.text("historical_import_format_version"), .text("1")])
            try seedHistoricalAccountsAsManaged()
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

extension SQLiteDatabase {
    private func localAccount(named name: String) throws -> LocalAccount {
        let normalized = NotificationParser.normalize(name)
        guard !normalized.isEmpty else { throw ParserValidationError.invalidRule("Choose an account name.") }
        let query = try statement("""
            SELECT id,name,created_at,updated_at,symbol_name,color_name,archived_at,revision,native_currency
            FROM local_accounts WHERE normalized_name=?
            """)
        bind(normalized, at: 1, to: query)
        if sqlite3_step(query) == SQLITE_ROW, let id = UUID(uuidString: string(query, 0)) {
            var found = LocalAccount(id: id, name: string(query, 1),
                                     createdAt: Date(timeIntervalSince1970: sqlite3_column_double(query, 2)))
            found.updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(query, 3))
            found.symbolName = string(query, 4)
            found.colorName = string(query, 5)
            found.archivedAt = sqlite3_column_type(query, 6) == SQLITE_NULL ? nil :
                Date(timeIntervalSince1970: sqlite3_column_double(query, 6))
            found.revision = sqlite3_column_int64(query, 7)
            found.nativeCurrency = string(query, 8)
            sqlite3_finalize(query)
            return found
        }
        sqlite3_finalize(query)
        let account = LocalAccount(id: UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                   createdAt: .now)
        let insert = try statement("""
            INSERT INTO local_accounts(id,name,normalized_name,created_at,updated_at,revision)
            VALUES(?,?,?,?,?,1)
            """)
        defer { sqlite3_finalize(insert) }
        bind(account.id.uuidString, at: 1, to: insert)
        bind(account.name, at: 2, to: insert)
        bind(normalized, at: 3, to: insert)
        sqlite3_bind_double(insert, 4, account.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(insert, 5, account.createdAt.timeIntervalSince1970)
        guard sqlite3_step(insert) == SQLITE_DONE else { throw error() }
        return account
    }

    func localAccounts() throws -> [LocalAccount] {
        let query = try statement("""
            SELECT id,name,created_at,updated_at,symbol_name,color_name,archived_at,revision,native_currency
            FROM local_accounts ORDER BY archived_at IS NOT NULL,name COLLATE NOCASE
            """)
        defer { sqlite3_finalize(query) }
        var accounts: [LocalAccount] = []
        while sqlite3_step(query) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(query, 0)) else { continue }
            var account = LocalAccount(id: id, name: string(query, 1),
                                       createdAt: Date(timeIntervalSince1970: sqlite3_column_double(query, 2)))
            account.updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(query, 3))
            account.symbolName = string(query, 4)
            account.colorName = string(query, 5)
            account.archivedAt = sqlite3_column_type(query, 6) == SQLITE_NULL ? nil :
                Date(timeIntervalSince1970: sqlite3_column_double(query, 6))
            account.revision = sqlite3_column_int64(query, 7)
            account.nativeCurrency = string(query, 8)
            accounts.append(account)
        }
        return accounts
    }

    private func matchingExistingAccountName(for sourceName: String) throws -> String? {
        let normalized = NotificationParser.normalize(sourceName)
        let archived = Set(try localAccounts().filter { $0.archivedAt != nil }
            .map { NotificationParser.normalize($0.name) })
        let query = try statement("""
            SELECT name FROM local_accounts UNION SELECT source_name FROM historical_accounts
            UNION SELECT DISTINCT account FROM transactions WHERE account != ''
            """)
        defer { sqlite3_finalize(query) }
        while sqlite3_step(query) == SQLITE_ROW {
            let candidate = string(query, 0)
            if NotificationParser.normalize(candidate) == normalized && !archived.contains(normalized) {
                return candidate
            }
        }
        return nil
    }

    private func setSourceAccount(_ sourceID: UUID, name: String) throws {
        let account = try localAccount(named: name)
        let current = try parserSources().first(where: { $0.id == sourceID })?.accountID
        if account.archivedAt != nil && current != account.id { throw DailyValidationError.archivedAccount }
        let update = try statement("UPDATE parser_sources SET account_id=? WHERE id=?")
        defer { sqlite3_finalize(update) }
        bind(account.id.uuidString, at: 1, to: update)
        bind(sourceID.uuidString, at: 2, to: update)
        guard sqlite3_step(update) == SQLITE_DONE else { throw error() }
        guard sqlite3_changes(handle) == 1 else {
            throw ParserValidationError.invalidRule("Notification source was not found.")
        }
    }

    func mapParserSource(_ sourceID: UUID, to accountName: String) throws -> ParserSource {
        try execute("BEGIN IMMEDIATE")
        do {
            try setSourceAccount(sourceID, name: accountName)
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
        guard let source = try parserSources().first(where: { $0.id == sourceID }) else {
            throw ParserValidationError.invalidRule("Notification source was not found.")
        }
        return source
    }

    func configureParserSource(named sourceName: String, accountID: UUID) throws -> ParserSource {
        let cleanName = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.utf8.count <= 120 else {
            throw ParserValidationError.invalidRule("Enter a source label under 120 characters.")
        }
        guard let account = try localAccounts().first(where: { $0.id == accountID && $0.archivedAt == nil }) else {
            throw ParserValidationError.invalidRule("Choose an active EasyTrack account.")
        }
        try execute("BEGIN IMMEDIATE")
        do {
            let source = try parserSource(named: cleanName)
            try setSourceAccount(source.id, name: account.name)
            try execute("COMMIT")
            guard let configured = try parserSources().first(where: { $0.id == source.id }) else {
                throw ParserValidationError.invalidRule("Notification source was not found.")
            }
            return configured
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func backfillSourceAccountsFromLegacyRules() throws {
        let unmapped = try statement("SELECT id,name FROM parser_sources WHERE account_id IS NULL")
        var sources: [(UUID, String)] = []
        while sqlite3_step(unmapped) == SQLITE_ROW {
            if let id = UUID(uuidString: string(unmapped, 0)) {
                sources.append((id, string(unmapped, 1)))
            }
        }
        sqlite3_finalize(unmapped)
        guard !sources.isEmpty else { return }
        var assignments: [(UUID, String)] = []
        for (id, sourceName) in sources {
            let rules = try parserRules(sourceID: id, includeDeleted: true)
            let legacy = rules.first { !NotificationParser.normalize($0.config.account).isEmpty }?.config.account
            if let name = try legacy ?? matchingExistingAccountName(for: sourceName) {
                assignments.append((id, name))
            }
        }
        guard !assignments.isEmpty else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            for (id, name) in assignments {
                try setSourceAccount(id, name: name)
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    private func parserSource(named name: String) throws -> ParserSource {
        let normalized = NotificationParser.normalize(name)
        let query = try statement("""
            SELECT s.id,s.name,s.created_at,s.account_id,a.name
            FROM parser_sources s LEFT JOIN local_accounts a ON a.id=s.account_id
            WHERE s.normalized_name=?
            """)
        bind(normalized, at: 1, to: query)
        if sqlite3_step(query) == SQLITE_ROW,
           let id = UUID(uuidString: string(query, 0)) {
            let source = ParserSource(id: id, name: string(query, 1),
                                      createdAt: Date(timeIntervalSince1970: sqlite3_column_double(query, 2)),
                                      accountID: UUID(uuidString: string(query, 3)),
                                      accountName: optionalString(query, 4))
            sqlite3_finalize(query)
            return source
        }
        sqlite3_finalize(query)
        let sourceName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchedName = try matchingExistingAccountName(for: sourceName)
        let matchedAccount = try matchedName.map { try localAccount(named: $0) }
        let source = ParserSource(id: UUID(), name: sourceName, createdAt: .now,
                                  accountID: matchedAccount?.id, accountName: matchedAccount?.name)
        let insert = try statement("INSERT INTO parser_sources(id,name,normalized_name,created_at,account_id) VALUES(?,?,?,?,?)")
        defer { sqlite3_finalize(insert) }
        bind(source.id.uuidString, at: 1, to: insert)
        bind(source.name, at: 2, to: insert)
        bind(normalized, at: 3, to: insert)
        sqlite3_bind_double(insert, 4, source.createdAt.timeIntervalSince1970)
        bindOptional(source.accountID?.uuidString, at: 5, to: insert)
        guard sqlite3_step(insert) == SQLITE_DONE else { throw error() }
        return source
    }

    private func backfillLegacyNotificationEvents() throws {
        let check = try statement("SELECT COUNT(*) FROM notification_attempts")
        guard sqlite3_step(check) == SQLITE_ROW else { sqlite3_finalize(check); throw error() }
        let hasAttempts = sqlite3_column_int64(check, 0) > 0
        sqlite3_finalize(check)
        guard !hasAttempts else { return }
        let legacy = try notificationEvents()
        guard !legacy.isEmpty else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            for event in legacy {
                let source = try parserSource(named: event.sourceApp)
                _ = try insertAttempt(event: event, canonicalEventID: event.id, sourceID: source.id,
                                      status: .setupRequired)
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func parserSources() throws -> [ParserSource] {
        let query = try statement("""
            SELECT s.id,s.name,s.created_at,s.account_id,a.name
            FROM parser_sources s LEFT JOIN local_accounts a ON a.id=s.account_id
            ORDER BY s.name COLLATE NOCASE
            """)
        defer { sqlite3_finalize(query) }
        var sources: [ParserSource] = []
        while sqlite3_step(query) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(query, 0)) else { continue }
            sources.append(ParserSource(id: id, name: string(query, 1),
                                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(query, 2)),
                                        accountID: UUID(uuidString: string(query, 3)),
                                        accountName: optionalString(query, 4)))
        }
        return sources
    }

    private func mappedAccountName(for sourceID: UUID) throws -> String? {
        let query = try statement("""
            SELECT a.name FROM parser_sources s JOIN local_accounts a ON a.id=s.account_id
            WHERE s.id=? AND a.archived_at IS NULL
            """)
        defer { sqlite3_finalize(query) }
        bind(sourceID.uuidString, at: 1, to: query)
        return sqlite3_step(query) == SQLITE_ROW ? string(query, 0) : nil
    }

    private func mappedAccountID(for sourceID: UUID) throws -> UUID? {
        let query = try statement("SELECT account_id FROM parser_sources WHERE id=?")
        defer { sqlite3_finalize(query) }
        bind(sourceID.uuidString, at: 1, to: query)
        return sqlite3_step(query) == SQLITE_ROW ? UUID(uuidString: string(query, 0)) : nil
    }

    func parserRules(sourceID: UUID? = nil, includeDeleted: Bool = false) throws -> [ParserRule] {
        let sql = "SELECT id,source_id,name,enabled,priority,version,config_json,created_at,updated_at,deleted_at FROM parser_rules" +
            (sourceID == nil ? " WHERE 1=1" : " WHERE source_id=?") +
            (includeDeleted ? "" : " AND deleted_at IS NULL") + " ORDER BY priority ASC, created_at ASC"
        let query = try statement(sql)
        defer { sqlite3_finalize(query) }
        if let sourceID { bind(sourceID.uuidString, at: 1, to: query) }
        var rules: [ParserRule] = []
        while sqlite3_step(query) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(query, 0)),
                  let source = UUID(uuidString: string(query, 1)),
                  let config = try? JSONDecoder().decode(ParserRuleConfig.self, from: Data(string(query, 6).utf8)) else { continue }
            rules.append(ParserRule(id: id, sourceID: source, name: string(query, 2),
                                    enabled: sqlite3_column_int(query, 3) != 0,
                                    priority: Int(sqlite3_column_int(query, 4)),
                                    version: Int(sqlite3_column_int(query, 5)), config: config,
                                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(query, 7)),
                                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(query, 8)),
                                    deletedAt: sqlite3_column_type(query, 9) == SQLITE_NULL ? nil :
                                        Date(timeIntervalSince1970: sqlite3_column_double(query, 9))))
        }
        return rules
    }

    func parserRuleHistory(_ id: UUID) throws -> [ParserRuleRevision] {
        let query = try statement("SELECT version,config_json,changed_at FROM parser_rule_versions WHERE rule_id=? ORDER BY version DESC")
        defer { sqlite3_finalize(query) }
        bind(id.uuidString, at: 1, to: query)
        var revisions: [ParserRuleRevision] = []
        while sqlite3_step(query) == SQLITE_ROW {
            guard let config = try? JSONDecoder().decode(ParserRuleConfig.self, from: Data(string(query, 1).utf8)) else { continue }
            revisions.append(ParserRuleRevision(ruleID: id, version: Int(sqlite3_column_int(query, 0)),
                                                config: config, changedAt: Date(timeIntervalSince1970: sqlite3_column_double(query, 2))))
        }
        return revisions
    }

    @discardableResult func saveParserRule(_ input: ParserRule) throws -> ParserRule {
        try NotificationParser.validate(input.config)
        guard try mappedAccountName(for: input.sourceID) != nil else {
            throw ParserValidationError.invalidRule("Map this notification source to an account first.")
        }
        guard !input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParserValidationError.invalidRule("Name this automation.")
        }
        try execute("BEGIN IMMEDIATE")
        do {
            let current = try statement("SELECT version,created_at FROM parser_rules WHERE id=?")
            bind(input.id.uuidString, at: 1, to: current)
            let exists = sqlite3_step(current) == SQLITE_ROW
            if exists && input.version != Int(sqlite3_column_int(current, 0)) {
                sqlite3_finalize(current)
                throw ParserValidationError.invalidRule("This automation changed. Reopen it before saving.")
            }
            let version = exists ? Int(sqlite3_column_int(current, 0)) + 1 : 1
            let createdAt = exists ? Date(timeIntervalSince1970: sqlite3_column_double(current, 1)) : Date()
            sqlite3_finalize(current)
            var rule = input
            rule.version = version
            rule.createdAt = createdAt
            rule.updatedAt = .now
            let configJSON = String(data: try JSONEncoder().encode(rule.config), encoding: .utf8)!
            let save = try statement("""
                INSERT INTO parser_rules(id,source_id,name,enabled,priority,version,config_json,created_at,updated_at,deleted_at)
                VALUES(?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET name=excluded.name, enabled=excluded.enabled,
                    priority=excluded.priority, version=excluded.version, config_json=excluded.config_json,
                    updated_at=excluded.updated_at, deleted_at=excluded.deleted_at
                """)
            bind(rule.id.uuidString, at: 1, to: save)
            bind(rule.sourceID.uuidString, at: 2, to: save)
            bind(rule.name.trimmingCharacters(in: .whitespacesAndNewlines), at: 3, to: save)
            sqlite3_bind_int(save, 4, rule.enabled ? 1 : 0)
            sqlite3_bind_int(save, 5, Int32(rule.priority))
            sqlite3_bind_int(save, 6, Int32(rule.version))
            bind(configJSON, at: 7, to: save)
            sqlite3_bind_double(save, 8, rule.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(save, 9, rule.updatedAt.timeIntervalSince1970)
            if let deletedAt = rule.deletedAt { sqlite3_bind_double(save, 10, deletedAt.timeIntervalSince1970) }
            else { sqlite3_bind_null(save, 10) }
            guard sqlite3_step(save) == SQLITE_DONE else { sqlite3_finalize(save); throw error() }
            sqlite3_finalize(save)
            let revision = try statement("INSERT INTO parser_rule_versions(rule_id,version,config_json,changed_at) VALUES(?,?,?,?)")
            bind(rule.id.uuidString, at: 1, to: revision)
            sqlite3_bind_int(revision, 2, Int32(rule.version))
            bind(configJSON, at: 3, to: revision)
            sqlite3_bind_double(revision, 4, rule.updatedAt.timeIntervalSince1970)
            guard sqlite3_step(revision) == SQLITE_DONE else { sqlite3_finalize(revision); throw error() }
            sqlite3_finalize(revision)
            try execute("COMMIT")
            return rule
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func swapParserRulePriorities(_ first: ParserRule, _ second: ParserRule) throws {
        guard first.sourceID == second.sourceID, first.id != second.id,
              first.deletedAt == nil, second.deletedAt == nil else {
            throw ParserValidationError.invalidRule("These automations cannot be reordered together.")
        }
        try execute("BEGIN IMMEDIATE")
        do {
            for (rule, priority) in [(first, second.priority), (second, first.priority)] {
                let update = try statement("""
                    UPDATE parser_rules SET priority=?,version=version+1,updated_at=?
                    WHERE id=? AND source_id=? AND version=? AND deleted_at IS NULL
                    """)
                sqlite3_bind_int(update, 1, Int32(priority))
                sqlite3_bind_double(update, 2, Date().timeIntervalSince1970)
                bind(rule.id.uuidString, at: 3, to: update)
                bind(rule.sourceID.uuidString, at: 4, to: update)
                sqlite3_bind_int(update, 5, Int32(rule.version))
                guard sqlite3_step(update) == SQLITE_DONE else { sqlite3_finalize(update); throw error() }
                sqlite3_finalize(update)
                guard sqlite3_changes(handle) == 1 else {
                    throw ParserValidationError.invalidRule("This automation changed. Reopen the source and try again.")
                }
                let audit = try statement("""
                    INSERT INTO parser_rule_versions(rule_id,version,config_json,changed_at)
                    SELECT id,version,config_json,updated_at FROM parser_rules WHERE id=?
                    """)
                bind(rule.id.uuidString, at: 1, to: audit)
                guard sqlite3_step(audit) == SQLITE_DONE else { sqlite3_finalize(audit); throw error() }
                sqlite3_finalize(audit)
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func parserAttempts(sourceID: UUID? = nil) throws -> [ParserAttempt] {
        let sql = "SELECT id,event_id,source_id,raw_json,captured_at,status,rule_id,rule_version,transaction_id,detail FROM notification_attempts" +
            (sourceID == nil ? "" : " WHERE source_id=?") + " ORDER BY captured_at DESC"
        let query = try statement(sql)
        defer { sqlite3_finalize(query) }
        if let sourceID { bind(sourceID.uuidString, at: 1, to: query) }
        var attempts: [ParserAttempt] = []
        while sqlite3_step(query) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(query, 0)),
                  let eventID = UUID(uuidString: string(query, 1)),
                  let source = UUID(uuidString: string(query, 2)),
                  var event = try? JSONDecoder().decode(NotificationEvent.self, from: Data(string(query, 3).utf8)),
                  let status = ParserAttemptStatus(rawValue: string(query, 5)) else { continue }
            event.id = eventID
            attempts.append(ParserAttempt(id: id, event: event, sourceID: source,
                                          capturedAt: Date(timeIntervalSince1970: sqlite3_column_double(query, 4)),
                                          status: status, ruleID: UUID(uuidString: string(query, 6)),
                                          ruleVersion: optionalInt(query, 7).map(Int.init),
                                          transactionID: UUID(uuidString: string(query, 8)), detail: optionalString(query, 9)))
        }
        return attempts
    }

    private func insertAttempt(event: NotificationEvent, canonicalEventID: UUID, sourceID: UUID,
                               status: ParserAttemptStatus = .captured) throws -> UUID {
        let id = UUID()
        let insert = try statement("""
            INSERT INTO notification_attempts(id,event_id,source_id,raw_json,captured_at,status,exact_fingerprint)
            VALUES(?,?,?,?,?,?,?)
            """)
        defer { sqlite3_finalize(insert) }
        bind(id.uuidString, at: 1, to: insert)
        bind(canonicalEventID.uuidString, at: 2, to: insert)
        bind(sourceID.uuidString, at: 3, to: insert)
        bind(String(data: try JSONEncoder().encode(event), encoding: .utf8)!, at: 4, to: insert)
        sqlite3_bind_double(insert, 5, event.capturedAt.timeIntervalSince1970)
        bind(status.rawValue, at: 6, to: insert)
        bind(NotificationParser.exactFingerprint(event), at: 7, to: insert)
        guard sqlite3_step(insert) == SQLITE_DONE else { throw error() }
        return id
    }

    @discardableResult func captureNotification(_ event: NotificationEvent) throws -> ParserAttempt {
        _ = try purgeExpiredNotificationContents()
        let attemptID: UUID
        try execute("BEGIN IMMEDIATE")
        do {
            let source = try parserSource(named: event.sourceApp)
            _ = try insertEvent(event)
            let canonical = try statement("SELECT id FROM notification_events WHERE fingerprint=?")
            bind(event.fingerprint, at: 1, to: canonical)
            guard sqlite3_step(canonical) == SQLITE_ROW,
                  let canonicalID = UUID(uuidString: string(canonical, 0)) else {
                sqlite3_finalize(canonical)
                throw error()
            }
            sqlite3_finalize(canonical)
            attemptID = try insertAttempt(event: event, canonicalEventID: canonicalID, sourceID: source.id)
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
        let result: ParserAttempt
        do { result = try processNotificationAttempt(attemptID) }
        catch {
            // The raw capture has already committed. A processing failure cannot erase it.
            try markAttempt(attemptID, status: .failed, detail: "Local save failed. Retry this sample.")
            result = try notificationAttempt(attemptID)
        }
        if try notificationRetentionDays() == 0 { _ = try purgeExpiredNotificationContents() }
        return result
    }

    private func notificationAttempt(_ id: UUID) throws -> ParserAttempt {
        let query = try statement("""
            SELECT event_id,source_id,raw_json,captured_at,status,rule_id,rule_version,transaction_id,detail
            FROM notification_attempts WHERE id=?
            """)
        defer { sqlite3_finalize(query) }
        bind(id.uuidString, at: 1, to: query)
        guard sqlite3_step(query) == SQLITE_ROW,
              let eventID = UUID(uuidString: string(query, 0)),
              let sourceID = UUID(uuidString: string(query, 1)),
              var event = try? JSONDecoder().decode(NotificationEvent.self, from: Data(string(query, 2).utf8)),
              let status = ParserAttemptStatus(rawValue: string(query, 4)) else {
            throw DatabaseError.sqlite("Notification sample was not found")
        }
        event.id = eventID
        return ParserAttempt(id: id, event: event, sourceID: sourceID,
                             capturedAt: Date(timeIntervalSince1970: sqlite3_column_double(query, 3)),
                             status: status, ruleID: UUID(uuidString: string(query, 5)),
                             ruleVersion: optionalInt(query, 6).map(Int.init),
                             transactionID: UUID(uuidString: string(query, 7)), detail: optionalString(query, 8))
    }

    private func markAttempt(_ id: UUID, status: ParserAttemptStatus, rule: ParserRule? = nil,
                             transactionID: UUID? = nil, semantic: String? = nil,
                             detail: String? = nil) throws {
        let update = try statement("""
            UPDATE notification_attempts SET status=?,rule_id=?,rule_version=?,transaction_id=?,
                semantic_fingerprint=?,detail=? WHERE id=?
            """)
        defer { sqlite3_finalize(update) }
        bind(status.rawValue, at: 1, to: update)
        bindOptional(rule?.id.uuidString, at: 2, to: update)
        bindOptional(rule.map { Int64($0.version) }, at: 3, to: update)
        bindOptional(transactionID?.uuidString, at: 4, to: update)
        bindOptional(semantic, at: 5, to: update)
        bindOptional(detail, at: 6, to: update)
        bind(id.uuidString, at: 7, to: update)
        guard sqlite3_step(update) == SQLITE_DONE else { throw error() }
    }

    private func existingTransaction(sql: String, fingerprint: String, date: Date,
                                     window: Int? = nil) throws -> UUID? {
        let query = try statement(sql)
        defer { sqlite3_finalize(query) }
        bind(fingerprint, at: 1, to: query)
        sqlite3_bind_double(query, 2, date.timeIntervalSince1970)
        if let window { sqlite3_bind_double(query, 3, Double(window)) }
        guard sqlite3_step(query) == SQLITE_ROW else { return nil }
        return UUID(uuidString: string(query, 0))
    }

    private func exactDuplicate(_ event: NotificationEvent, window: Int) throws -> UUID? {
        try existingTransaction(sql: """
            SELECT transaction_id FROM exact_dedup
            WHERE fingerprint=? AND (has_payload_date=1 OR ABS(occurred_at-?)<=?)
            ORDER BY created_at DESC LIMIT 1
            """, fingerprint: NotificationParser.exactFingerprint(event),
            date: event.receivedAt ?? event.capturedAt, window: window)
    }

    private func semanticDuplicate(key: String, date: Date, window: Int) throws -> UUID? {
        try existingTransaction(sql: """
            SELECT transaction_id FROM semantic_dedup
            WHERE semantic_key=? AND ABS(occurred_at-?)<=?
            ORDER BY created_at DESC LIMIT 1
            """, fingerprint: key, date: date, window: window)
    }

    // Shared by ordinary parser creation and a user-confirmed held recurring notification.
    func insertParserDedup(event: NotificationEvent, date: Date, semantic: String,
                           parserRuleID: UUID, transactionID: UUID) throws {
        let exact = try statement("""
            INSERT INTO exact_dedup(id,fingerprint,occurred_at,has_payload_date,transaction_id,created_at)
            VALUES(?,?,?,?,?,?)
            """)
        bind(UUID().uuidString, at: 1, to: exact)
        bind(NotificationParser.exactFingerprint(event), at: 2, to: exact)
        sqlite3_bind_double(exact, 3, date.timeIntervalSince1970)
        sqlite3_bind_int(exact, 4, event.receivedAt == nil ? 0 : 1)
        bind(transactionID.uuidString, at: 5, to: exact)
        sqlite3_bind_double(exact, 6, Date().timeIntervalSince1970)
        guard sqlite3_step(exact) == SQLITE_DONE else { sqlite3_finalize(exact); throw error() }
        sqlite3_finalize(exact)
        let semanticRow = try statement("""
            INSERT INTO semantic_dedup(id,semantic_key,occurred_at,transaction_id,rule_id,created_at)
            VALUES(?,?,?,?,?,?)
            """)
        bind(UUID().uuidString, at: 1, to: semanticRow)
        bind(semantic, at: 2, to: semanticRow)
        sqlite3_bind_double(semanticRow, 3, date.timeIntervalSince1970)
        bind(transactionID.uuidString, at: 4, to: semanticRow)
        bind(parserRuleID.uuidString, at: 5, to: semanticRow)
        sqlite3_bind_double(semanticRow, 6, Date().timeIntervalSince1970)
        guard sqlite3_step(semanticRow) == SQLITE_DONE else { sqlite3_finalize(semanticRow); throw error() }
        sqlite3_finalize(semanticRow)
    }

    // The caller owns BEGIN IMMEDIATE and commits the candidate and financial edits together.
    func confirmHeldRecurringNotification(_ candidate: RecurringCandidate) throws -> UUID {
        guard let eventID = candidate.eventID,
              let occurrence = try recurringOccurrences().first(where: { $0.id == candidate.occurrenceID }),
              let oldID = occurrence.transactionID,
              occurrence.status == .legacyCounted || occurrence.status == .recordedManual,
              let recurringRule = try recurringRules(includeArchived: true).first(where: { $0.id == occurrence.ruleID }),
              var old = try transactions().first(where: { $0.id == oldID }),
              old.sourceEventID == nil, old.sourceMovementID == nil,
              let attempt = try parserAttempts().first(where: { $0.event.id == eventID && $0.status == .recurringReview }),
              let parserID = attempt.ruleID,
              var parserRule = try parserRules(includeDeleted: true).first(where: { $0.id == parserID }),
              let account = try localAccounts().first(where: { $0.id == recurringRule.accountID }) else {
            throw RecurringError.occurrenceChanged
        }
        if let version = attempt.ruleVersion, version != parserRule.version {
            guard let historical = try parserRuleHistory(parserID).first(where: { $0.version == version }) else {
                throw RecurringError.occurrenceChanged
            }
            parserRule.config = historical.config
            parserRule.version = version
        }
        let preview = NotificationParser.preview(attempt.event, config: parserRule.config,
                                                 mappedAccount: account.name)
        guard preview.ready, let amount = preview.amount, let merchant = preview.merchant,
              parserRule.config.kind == recurringRule.type.transactionKind,
              old.accountID == recurringRule.accountID else { throw RecurringError.occurrenceChanged }
        let date = attempt.event.receivedAt ?? attempt.event.capturedAt
        let values = TransactionEditPolicy.values(original: old, kind: old.kind,
                                                  newEURMinor: amount.cents)
        old.amountMinor = amount.cents
        old.eurMinor = amount.cents
        old.personalExpenseEURMinor = values.personal
        old.recoverableEURMinor = values.recoverable
        old.occurredAt = date
        if old.revision == 1 { old.merchant = merchant }
        old.sourceEventID = eventID
        _ = try save(old, manageTransaction: false)
        try confirmCountedOccurrence(occurrence.id, transactionID: oldID, actor: "user")
        let semantic = NotificationParser.semanticFingerprint(amountMinor: amount.cents,
                                                              merchant: merchant, account: account.name)
        try insertParserDedup(event: attempt.event, date: date, semantic: semantic,
                              parserRuleID: parserID, transactionID: oldID)
        try markAttempt(attempt.id, status: .matchedExisting, rule: parserRule,
                        transactionID: oldID, semantic: semantic,
                        detail: "Confirmed as the existing recurring payment.")
        return oldID
    }

    private func commitAttempt(_ id: UUID) throws -> ParserAttempt {
        let result = try notificationAttempt(id)
        try execute("COMMIT")
        return result
    }

    @discardableResult func processNotificationAttempt(_ id: UUID, preferredRuleID: UUID? = nil) throws -> ParserAttempt {
        var attemptedRule: ParserRule?
        try execute("BEGIN IMMEDIATE")
        do {
            let attempt = try notificationAttempt(id)
            let event = attempt.event
            let date = event.receivedAt ?? event.capturedAt
            if let reason = NotificationSafetyFilter.rejectionReason(for: event) {
                try markAttempt(id, status: .rejected, detail: reason)
                return try commitAttempt(id)
            }
            if let duplicate = try exactDuplicate(event, window: 600) {
                try markAttempt(id, status: .duplicateIgnored, transactionID: duplicate,
                                detail: "This notification was already recorded.")
                return try commitAttempt(id)
            }
            guard let accountName = try mappedAccountName(for: attempt.sourceID) else {
                try markAttempt(id, status: .setupRequired,
                                detail: "Choose the account for this notification source.")
                return try commitAttempt(id)
            }
            let rules = try parserRules(sourceID: attempt.sourceID).filter { $0.enabled &&
                (preferredRuleID == nil || $0.id == preferredRuleID) }
            var chosen: (ParserRule, ParserPreview)?
            var incomplete: ParserRule?
            for rule in rules {
                let preview = NotificationParser.preview(event, config: rule.config,
                                                         mappedAccount: accountName)
                if preview.ready { chosen = (rule, preview); break }
                if preview.conditionMatched && incomplete == nil { incomplete = rule }
            }
            guard let (rule, preview) = chosen, let amount = preview.amount,
                  let merchant = preview.merchant else {
                let status: ParserAttemptStatus = incomplete == nil ? (rules.isEmpty ? .setupRequired : .unmatched) : .failed
                try markAttempt(id, status: status, rule: incomplete,
                                detail: incomplete == nil ? nil : "A matching rule needs a usable EUR amount and description.")
                return try commitAttempt(id)
            }
            attemptedRule = rule
            let semantic = NotificationParser.semanticFingerprint(amountMinor: amount.cents,
                                                                  merchant: merchant, account: accountName)
            if let duplicate = try semanticDuplicate(key: semantic, date: date,
                                                     window: rule.config.duplicateWindowSeconds) {
                try markAttempt(id, status: .duplicateIgnored, rule: rule,
                                transactionID: duplicate, semantic: semantic,
                                detail: "A matching transaction was recorded recently.")
                return try commitAttempt(id)
            }
            let linked = try statement("SELECT id FROM transactions WHERE source_event_id=? AND deleted_at IS NULL LIMIT 1")
            bind(event.id.uuidString, at: 1, to: linked)
            let existingID = sqlite3_step(linked) == SQLITE_ROW ? UUID(uuidString: string(linked, 0)) : nil
            sqlite3_finalize(linked)
            if let existingID {
                try markAttempt(id, status: .duplicateIgnored, rule: rule, transactionID: existingID,
                                semantic: semantic, detail: "This notification already has a transaction.")
                return try commitAttempt(id)
            }
            let mappedID = try mappedAccountID(for: attempt.sourceID)
            let options = try recurringMatchOptions(accountID: mappedID, kind: rule.config.kind,
                                                    amountMinor: amount.cents, merchant: merchant,
                                                    at: date, eventID: event.id)
            let activeTransactions = try transactions()
            let competing = options.count == 1 && activeTransactions.contains { existing in
                existing.id != options[0].occurrence.transactionID && !existing.isDemo &&
                existing.accountID == mappedID && existing.kind == rule.config.kind &&
                existing.amountMinor == amount.cents &&
                NotificationParser.normalize(existing.merchant) == NotificationParser.normalize(merchant) &&
                LocalDay(date: existing.occurredAt,
                         timeZone: TimeZone(identifier: options[0].rule.timeZoneIdentifier) ?? .current) ==
                    LocalDay(date: date,
                             timeZone: TimeZone(identifier: options[0].rule.timeZoneIdentifier) ?? .current)
            }
            let automatic = options.count == 1 && options[0].strict && !competing
            if options.contains(where: \.counted) && !automatic || competing {
                for option in options {
                    _ = try saveRecurringCandidate(occurrenceID: option.occurrence.id, eventID: event.id,
                                                   transactionID: nil,
                                                   reason: competing ? "A similar transaction already exists." : option.reason)
                }
                try markAttempt(id, status: .recurringReview, rule: rule, semantic: semantic,
                                detail: "Review the possible recurring payment before recording this notification.")
                return try commitAttempt(id)
            }
            let values = TransactionEditPolicy.values(original: nil, kind: rule.config.kind,
                                                      newEURMinor: amount.cents)
            var transaction = Transaction(id: UUID(), kind: rule.config.kind, amountMinor: amount.cents,
                                          currency: "EUR", merchant: merchant, account: accountName,
                                          category: "", note: "", occurredAt: date,
                                          updatedAt: .now, deletedAt: nil, isDemo: false, revision: 0,
                                          sourceEventID: event.id)
            transaction.eurMinor = amount.cents
            transaction.personalExpenseEURMinor = values.personal
            transaction.recoverableEURMinor = values.recoverable
            transaction.accountID = mappedID
#if DEBUG
            if preferredRuleID != nil,
               let token = ProcessInfo.processInfo.environment["EASYTRACK_TEST_FAIL_PARSER_ONCE"] {
                let key = "syntheticParserFailureConsumed-\(token)"
                if !UserDefaults.standard.bool(forKey: key) {
                    UserDefaults.standard.set(true, forKey: key)
                    throw DatabaseError.sqlite("Synthetic parser save failure")
                }
            }
#endif
            let matchedExisting = automatic && options[0].counted
            if matchedExisting {
                guard let oldID = options[0].occurrence.transactionID,
                      var existing = try transactions().first(where: { $0.id == oldID }) else {
                    throw RecurringError.occurrenceChanged
                }
                existing.sourceEventID = event.id
                existing.occurredAt = date
                existing.merchant = merchant
                transaction = try save(existing, manageTransaction: false)
                try confirmCountedOccurrence(options[0].occurrence.id,
                                             transactionID: transaction.id, actor: "parser")
                let candidate = try saveRecurringCandidate(occurrenceID: options[0].occurrence.id,
                                                           eventID: event.id, transactionID: transaction.id,
                                                           reason: "Exact approved match.", status: .confirmed)
                if candidate.status != .confirmed {
                    try setRecurringCandidateStatus(candidate.id, to: .confirmed,
                                                    transactionID: transaction.id)
                }
            } else {
                if automatic { transaction.recurringOccurrenceID = options[0].occurrence.id }
                transaction = try save(transaction, manageTransaction: false)
                if automatic {
                    try confirmExpectedOccurrence(options[0].occurrence.id,
                                                  transactionID: transaction.id, actor: "parser")
                    let candidate = try saveRecurringCandidate(occurrenceID: options[0].occurrence.id,
                                                               eventID: event.id, transactionID: transaction.id,
                                                               reason: "Exact approved match.", status: .confirmed)
                    if candidate.status != .confirmed {
                        try setRecurringCandidateStatus(candidate.id, to: .confirmed,
                                                        transactionID: transaction.id)
                    }
                } else {
                    for option in options {
                        _ = try saveRecurringCandidate(occurrenceID: option.occurrence.id,
                                                       eventID: event.id, transactionID: transaction.id,
                                                       reason: option.reason)
                    }
                }
            }
            let exactRecord = try statement("""
                INSERT INTO exact_dedup(id,fingerprint,occurred_at,has_payload_date,transaction_id,created_at)
                VALUES(?,?,?,?,?,?)
                """)
            bind(UUID().uuidString, at: 1, to: exactRecord)
            bind(NotificationParser.exactFingerprint(event), at: 2, to: exactRecord)
            sqlite3_bind_double(exactRecord, 3, date.timeIntervalSince1970)
            sqlite3_bind_int(exactRecord, 4, event.receivedAt == nil ? 0 : 1)
            bind(transaction.id.uuidString, at: 5, to: exactRecord)
            sqlite3_bind_double(exactRecord, 6, Date().timeIntervalSince1970)
            guard sqlite3_step(exactRecord) == SQLITE_DONE else { sqlite3_finalize(exactRecord); throw error() }
            sqlite3_finalize(exactRecord)
            let semanticRecord = try statement("""
                INSERT INTO semantic_dedup(id,semantic_key,occurred_at,transaction_id,rule_id,created_at)
                VALUES(?,?,?,?,?,?)
                """)
            bind(UUID().uuidString, at: 1, to: semanticRecord)
            bind(semantic, at: 2, to: semanticRecord)
            sqlite3_bind_double(semanticRecord, 3, date.timeIntervalSince1970)
            bind(transaction.id.uuidString, at: 4, to: semanticRecord)
            bind(rule.id.uuidString, at: 5, to: semanticRecord)
            sqlite3_bind_double(semanticRecord, 6, Date().timeIntervalSince1970)
            guard sqlite3_step(semanticRecord) == SQLITE_DONE else { sqlite3_finalize(semanticRecord); throw error() }
            sqlite3_finalize(semanticRecord)
            try markAttempt(id, status: matchedExisting ? .matchedExisting :
                            (!options.isEmpty && !automatic ? .recurringReview : .created),
                            rule: rule, transactionID: transaction.id, semantic: semantic,
                            detail: !options.isEmpty && !automatic ?
                                "Transaction recorded once; review its possible recurring match." : nil)
            return try commitAttempt(id)
        } catch {
            try? execute("ROLLBACK")
            try markAttempt(id, status: .failed, rule: attemptedRule,
                            detail: "Local save failed. Retry this sample.")
            return try notificationAttempt(id)
        }
    }

    func leaveSampleReady(_ id: UUID) throws {
        try markAttempt(id, status: .ready, detail: "Automation active. This sample was not added to Activity.")
    }
}
