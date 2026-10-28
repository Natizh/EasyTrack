import Foundation
import SQLite3

extension SQLiteDatabase {
    func migrateToSchemaFive() throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try ensureColumn("symbol_name", type: "TEXT NOT NULL DEFAULT 'creditcard.fill'", in: "local_accounts")
            try ensureColumn("color_name", type: "TEXT NOT NULL DEFAULT 'teal'", in: "local_accounts")
            try ensureColumn("updated_at", type: "REAL NOT NULL DEFAULT 0", in: "local_accounts")
            try ensureColumn("archived_at", type: "REAL", in: "local_accounts")
            try ensureColumn("revision", type: "INTEGER NOT NULL DEFAULT 1", in: "local_accounts")
            try execute("UPDATE local_accounts SET updated_at=created_at WHERE updated_at=0")

            try execute("""
                CREATE TABLE IF NOT EXISTS ledger_categories (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL,
                    normalized_name TEXT NOT NULL UNIQUE,
                    symbol_name TEXT NOT NULL, color_name TEXT NOT NULL,
                    sort_index INTEGER NOT NULL, created_at REAL NOT NULL,
                    updated_at REAL NOT NULL, archived_at REAL,
                    revision INTEGER NOT NULL
                )
                """)
            try execute("CREATE INDEX IF NOT EXISTS categories_by_order ON ledger_categories(archived_at,sort_index,name)")
            try execute("""
                CREATE TABLE IF NOT EXISTS recurring_rules_local (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL,
                    amount_minor INTEGER NOT NULL CHECK(amount_minor>0),
                    account_id TEXT NOT NULL, category_id TEXT,
                    start_day TEXT NOT NULL, frequency TEXT NOT NULL,
                    next_index INTEGER NOT NULL CHECK(next_index>=0), end_day TEXT,
                    timezone_id TEXT NOT NULL, is_active INTEGER NOT NULL,
                    note TEXT NOT NULL, created_at REAL NOT NULL,
                    updated_at REAL NOT NULL, archived_at REAL,
                    revision INTEGER NOT NULL, historical_source_id TEXT UNIQUE,
                    FOREIGN KEY(account_id) REFERENCES local_accounts(id),
                    FOREIGN KEY(category_id) REFERENCES ledger_categories(id),
                    FOREIGN KEY(historical_source_id) REFERENCES historical_recurring_rules(id)
                )
                """)
            try execute("CREATE INDEX IF NOT EXISTS recurring_rules_active ON recurring_rules_local(archived_at,is_active)")
            try execute("""
                CREATE TABLE IF NOT EXISTS recurring_occurrences_local (
                    id TEXT PRIMARY KEY, rule_id TEXT NOT NULL,
                    scheduled_day TEXT NOT NULL,
                    status TEXT NOT NULL CHECK(status IN ('materialized','skipped')),
                    transaction_id TEXT UNIQUE, created_at REAL NOT NULL,
                    UNIQUE(rule_id,scheduled_day),
                    FOREIGN KEY(rule_id) REFERENCES recurring_rules_local(id),
                    FOREIGN KEY(transaction_id) REFERENCES transactions(id),
                    CHECK((status='materialized')=(transaction_id IS NOT NULL))
                )
                """)
            try ensureColumn("account_id", type: "TEXT REFERENCES local_accounts(id)", in: "transactions")
            try ensureColumn("category_id", type: "TEXT REFERENCES ledger_categories(id)", in: "transactions")
            try ensureColumn("recurring_occurrence_id", type: "TEXT", in: "transactions")
            try execute("""
                CREATE UNIQUE INDEX IF NOT EXISTS unique_transaction_recurring_occurrence
                ON transactions(recurring_occurrence_id)
                WHERE recurring_occurrence_id IS NOT NULL
                """)
            try seedHistoricalAccountsAsManaged()
            try seedDefaultCategories()
            try execute("PRAGMA user_version=5")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func insertManagedAccountIfAbsent(_ name: String, symbol: String = "creditcard.fill",
                                              color: String = "teal") throws {
        let normalized = NotificationParser.normalize(name)
        guard !normalized.isEmpty else { return }
        let stmt = try statement("""
            INSERT OR IGNORE INTO local_accounts
            (id,name,normalized_name,created_at,symbol_name,color_name,updated_at,revision)
            VALUES(?,?,?,?,?,?,?,1)
            """)
        defer { sqlite3_finalize(stmt) }
        let now = Date().timeIntervalSince1970
        bind(UUID().uuidString, at: 1, to: stmt)
        bind(name, at: 2, to: stmt)
        bind(normalized, at: 3, to: stmt)
        sqlite3_bind_double(stmt, 4, now)
        bind(symbol, at: 5, to: stmt)
        bind(color, at: 6, to: stmt)
        sqlite3_bind_double(stmt, 7, now)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
    }

    func seedHistoricalAccountsAsManaged() throws {
        let stmt = try statement("SELECT source_name FROM historical_accounts ORDER BY source_name")
        var names: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW { names.append(string(stmt, 0)) }
        sqlite3_finalize(stmt)
        for name in names { try insertManagedAccountIfAbsent(name) }
    }

    private func seedDefaultCategories() throws {
        let defaults: [(String, String, String)] = [
            ("Groceries", "cart.fill", "green"),
            ("Eating Out", "fork.knife", "orange"),
            ("Transport", "car.fill", "blue"),
            ("Shopping", "bag.fill", "purple"),
            ("Home", "house.fill", "teal"),
            ("Bills", "doc.text.fill", "orange"),
            ("Health", "cross.case.fill", "red"),
            ("Entertainment", "ticket.fill", "indigo"),
            ("Travel", "airplane", "blue"),
            ("Education", "book.fill", "indigo"),
            ("Salary", "banknote.fill", "green"),
            ("Other", "square.grid.2x2.fill", "gray")
        ]
        for (position, entry) in defaults.enumerated() {
            let stmt = try statement("""
                INSERT OR IGNORE INTO ledger_categories
                (id,name,normalized_name,symbol_name,color_name,sort_index,created_at,updated_at,revision)
                VALUES(?,?,?,?,?,?,?,?,1)
                """)
            let now = Date().timeIntervalSince1970
            bind(UUID().uuidString, at: 1, to: stmt)
            bind(entry.0, at: 2, to: stmt)
            bind(NotificationParser.normalize(entry.0), at: 3, to: stmt)
            bind(entry.1, at: 4, to: stmt)
            bind(entry.2, at: 5, to: stmt)
            sqlite3_bind_int(stmt, 6, Int32(position))
            sqlite3_bind_double(stmt, 7, now)
            sqlite3_bind_double(stmt, 8, now)
            let result = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
            guard result == SQLITE_DONE else { throw error() }
        }
    }

    func appendDailyOperation<T: Encodable>(entityID: UUID, action: String,
                                            revision: Int64, value: T) throws {
        let payload = String(data: try JSONEncoder().encode(value), encoding: .utf8)!
        let stmt = try statement("INSERT INTO operations(id,entity_id,action,revision,payload_json,created_at) VALUES(?,?,?,?,?,?)")
        defer { sqlite3_finalize(stmt) }
        bind(UUID().uuidString, at: 1, to: stmt)
        bind(entityID.uuidString, at: 2, to: stmt)
        bind(action, at: 3, to: stmt)
        sqlite3_bind_int64(stmt, 4, revision)
        bind(payload, at: 5, to: stmt)
        sqlite3_bind_double(stmt, 6, Date().timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
    }

    @discardableResult func saveLocalAccount(_ input: LocalAccount) throws -> LocalAccount {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 100 else { throw DailyValidationError.emptyName }
        guard LedgerAppearance.symbols.contains(input.symbolName),
              LedgerAppearance.colors.contains(input.colorName),
              CurrencyMetadata.supportedCodes.contains(input.nativeCurrency) else { throw DailyValidationError.invalidAppearance }
        let normalized = NotificationParser.normalize(name)
        try execute("BEGIN IMMEDIATE")
        do {
            let duplicate = try statement("SELECT id FROM local_accounts WHERE normalized_name=? AND id!=? LIMIT 1")
            bind(normalized, at: 1, to: duplicate)
            bind(input.id.uuidString, at: 2, to: duplicate)
            let nameTaken = sqlite3_step(duplicate) == SQLITE_ROW
            sqlite3_finalize(duplicate)
            guard !nameTaken else { throw DailyValidationError.duplicateName }
            let existing = try localAccounts().first { $0.id == input.id }
            guard existing?.revision == input.revision || (existing == nil && input.revision == 0) else {
                throw DailyValidationError.staleRecord
            }
            var item = input
            if let existing, existing.nativeCurrency != item.nativeCurrency {
                let count = try statement("SELECT COUNT(*) FROM transactions WHERE account_id=? AND deleted_at IS NULL")
                bind(item.id.uuidString, at: 1, to: count)
                guard sqlite3_step(count) == SQLITE_ROW else { sqlite3_finalize(count); throw error() }
                let hasMovements = sqlite3_column_int64(count, 0) > 0
                sqlite3_finalize(count)
                guard !hasMovements else {
                    throw DatabaseError.sqlite("Account currency cannot change after movements are recorded.")
                }
            }
            item.name = name
            item.updatedAt = .now
            item.revision = (existing?.revision ?? 0) + 1
            let stmt = try statement("""
                INSERT INTO local_accounts
                (id,name,normalized_name,created_at,updated_at,symbol_name,color_name,archived_at,revision,native_currency)
                VALUES(?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET name=excluded.name,
                    normalized_name=excluded.normalized_name,updated_at=excluded.updated_at,
                    symbol_name=excluded.symbol_name,color_name=excluded.color_name,
                    archived_at=excluded.archived_at,revision=excluded.revision,native_currency=excluded.native_currency
                """)
            bind(item.id.uuidString, at: 1, to: stmt)
            bind(name, at: 2, to: stmt)
            bind(normalized, at: 3, to: stmt)
            sqlite3_bind_double(stmt, 4, item.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 5, item.updatedAt.timeIntervalSince1970)
            bind(item.symbolName, at: 6, to: stmt)
            bind(item.colorName, at: 7, to: stmt)
            if let archived = item.archivedAt { sqlite3_bind_double(stmt, 8, archived.timeIntervalSince1970) }
            else { sqlite3_bind_null(stmt, 8) }
            sqlite3_bind_int64(stmt, 9, item.revision)
            bind(item.nativeCurrency, at: 10, to: stmt)
            let saved = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
            guard saved == SQLITE_DONE else { throw error() }
            let action = existing == nil ? "account-create" :
                (existing?.archivedAt == nil && item.archivedAt != nil ? "account-archive" :
                 (existing?.archivedAt != nil && item.archivedAt == nil ? "account-restore" : "account-update"))
            try appendDailyOperation(entityID: item.id, action: action, revision: item.revision, value: item)
            try execute("COMMIT")
            return item
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func ledgerCategories() throws -> [LedgerCategory] {
        let stmt = try statement("""
            SELECT id,name,symbol_name,color_name,sort_index,created_at,updated_at,archived_at,revision
            FROM ledger_categories ORDER BY archived_at IS NOT NULL,sort_index,name COLLATE NOCASE
            """)
        defer { sqlite3_finalize(stmt) }
        var items: [LedgerCategory] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(stmt, 0)) else { continue }
            items.append(LedgerCategory(id: id, name: string(stmt, 1), symbolName: string(stmt, 2),
                                        colorName: string(stmt, 3), sortIndex: Int(sqlite3_column_int(stmt, 4)),
                                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5)),
                                        updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6)),
                                        archivedAt: sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil :
                                            Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7)),
                                        revision: sqlite3_column_int64(stmt, 8)))
        }
        return items
    }

    @discardableResult func saveLedgerCategory(_ input: LedgerCategory) throws -> LedgerCategory {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 100 else { throw DailyValidationError.emptyName }
        guard LedgerAppearance.symbols.contains(input.symbolName),
              LedgerAppearance.colors.contains(input.colorName) else { throw DailyValidationError.invalidAppearance }
        let normalized = NotificationParser.normalize(name)
        try execute("BEGIN IMMEDIATE")
        do {
            let duplicate = try statement("SELECT id FROM ledger_categories WHERE normalized_name=? AND id!=? LIMIT 1")
            bind(normalized, at: 1, to: duplicate)
            bind(input.id.uuidString, at: 2, to: duplicate)
            let nameTaken = sqlite3_step(duplicate) == SQLITE_ROW
            sqlite3_finalize(duplicate)
            guard !nameTaken else { throw DailyValidationError.duplicateName }
            let existing = try ledgerCategories().first { $0.id == input.id }
            guard existing?.revision == input.revision || (existing == nil && input.revision == 0) else {
                throw DailyValidationError.staleRecord
            }
            var item = input
            item.name = name
            item.updatedAt = .now
            item.revision = (existing?.revision ?? 0) + 1
            let stmt = try statement("""
                INSERT INTO ledger_categories
                (id,name,normalized_name,symbol_name,color_name,sort_index,created_at,updated_at,archived_at,revision)
                VALUES(?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET name=excluded.name,
                    normalized_name=excluded.normalized_name,symbol_name=excluded.symbol_name,
                    color_name=excluded.color_name,sort_index=excluded.sort_index,
                    updated_at=excluded.updated_at,archived_at=excluded.archived_at,
                    revision=excluded.revision
                """)
            bind(item.id.uuidString, at: 1, to: stmt)
            bind(name, at: 2, to: stmt)
            bind(normalized, at: 3, to: stmt)
            bind(item.symbolName, at: 4, to: stmt)
            bind(item.colorName, at: 5, to: stmt)
            sqlite3_bind_int(stmt, 6, Int32(item.sortIndex))
            sqlite3_bind_double(stmt, 7, item.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 8, item.updatedAt.timeIntervalSince1970)
            if let archived = item.archivedAt { sqlite3_bind_double(stmt, 9, archived.timeIntervalSince1970) }
            else { sqlite3_bind_null(stmt, 9) }
            sqlite3_bind_int64(stmt, 10, item.revision)
            let saved = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
            guard saved == SQLITE_DONE else { throw error() }
            let action = existing == nil ? "category-create" :
                (existing?.archivedAt == nil && item.archivedAt != nil ? "category-archive" :
                 (existing?.archivedAt != nil && item.archivedAt == nil ? "category-restore" : "category-update"))
            try appendDailyOperation(entityID: item.id, action: action, revision: item.revision, value: item)
            try execute("COMMIT")
            return item
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func swapCategoryOrder(_ first: LedgerCategory, _ second: LedgerCategory) throws {
        guard first.id != second.id, first.archivedAt == nil, second.archivedAt == nil else {
            throw DailyValidationError.invalidCategory
        }
        try execute("BEGIN IMMEDIATE")
        do {
            for (category, index) in [(first, second.sortIndex), (second, first.sortIndex)] {
                let stmt = try statement("""
                    UPDATE ledger_categories SET sort_index=?,updated_at=?,revision=revision+1
                    WHERE id=? AND revision=? AND archived_at IS NULL
                    """)
                sqlite3_bind_int(stmt, 1, Int32(index))
                sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
                bind(category.id.uuidString, at: 3, to: stmt)
                sqlite3_bind_int64(stmt, 4, category.revision)
                guard sqlite3_step(stmt) == SQLITE_DONE else { sqlite3_finalize(stmt); throw error() }
                sqlite3_finalize(stmt)
                guard sqlite3_changes(handle) == 1 else { throw DailyValidationError.staleRecord }
                guard let updated = try ledgerCategories().first(where: { $0.id == category.id }) else {
                    throw DailyValidationError.staleRecord
                }
                try appendDailyOperation(entityID: category.id, action: "category-reorder",
                                         revision: updated.revision, value: updated)
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func recurringRules(includeArchived: Bool = false) throws -> [RecurringRule] {
        let sql = """
            SELECT id,name,kind,amount_minor,account_id,category_id,start_day,frequency,
                   next_index,end_day,timezone_id,is_active,note,created_at,updated_at,
                   archived_at,revision,historical_source_id,review_window_days
            FROM recurring_rules_local
            """ + (includeArchived ? "" : " WHERE archived_at IS NULL") + " ORDER BY name COLLATE NOCASE"
        let stmt = try statement(sql)
        defer { sqlite3_finalize(stmt) }
        var rules: [RecurringRule] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(stmt, 0)),
                  let type = RecurringType(rawValue: string(stmt, 2)),
                  let accountID = UUID(uuidString: string(stmt, 4)),
                  let startDay = LocalDay(isoString: string(stmt, 6)),
                  let frequency = RecurringFrequency(rawValue: string(stmt, 7)) else { continue }
            var rule = RecurringRule(id: id, name: string(stmt, 1), type: type,
                                     amountMinor: sqlite3_column_int64(stmt, 3), accountID: accountID,
                                     categoryID: UUID(uuidString: string(stmt, 5)), startDay: startDay,
                                     frequency: frequency, nextIndex: Int(sqlite3_column_int64(stmt, 8)),
                                     endDay: optionalString(stmt, 9).flatMap(LocalDay.init(isoString:)),
                                     timeZoneIdentifier: string(stmt, 10),
                                     isActive: sqlite3_column_int(stmt, 11) != 0, note: string(stmt, 12),
                                     createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 13)),
                                     updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 14)),
                                     archivedAt: sqlite3_column_type(stmt, 15) == SQLITE_NULL ? nil :
                                        Date(timeIntervalSince1970: sqlite3_column_double(stmt, 15)),
                                     revision: sqlite3_column_int64(stmt, 16))
            rule.historicalSourceID = optionalString(stmt, 17)
            rule.reviewWindowDays = Int(sqlite3_column_int(stmt, 18))
            rules.append(rule)
        }
        return rules
    }

    func recurringOccurrences(ruleID: UUID? = nil) throws -> [RecurringOccurrence] {
        let sql = """
            SELECT id,rule_id,scheduled_day,status,transaction_id,created_at,
                   provisional_transaction_id,updated_at,revision,review_reason
            FROM recurring_occurrences_local
            """ + (ruleID == nil ? "" : " WHERE rule_id=?") + " ORDER BY scheduled_day DESC"
        let stmt = try statement(sql)
        defer { sqlite3_finalize(stmt) }
        if let ruleID { bind(ruleID.uuidString, at: 1, to: stmt) }
        var occurrences: [RecurringOccurrence] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let sourceID = UUID(uuidString: string(stmt, 1)),
                  let day = LocalDay(isoString: string(stmt, 2)),
                  let status = RecurringOccurrenceStatus(rawValue: string(stmt, 3)) else { continue }
            var occurrence = RecurringOccurrence(id: string(stmt, 0), ruleID: sourceID,
                                                   scheduledDay: day, status: status,
                                                   transactionID: UUID(uuidString: string(stmt, 4)),
                                                   createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5)))
            occurrence.provisionalTransactionID = UUID(uuidString: string(stmt, 6))
            occurrence.updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
            occurrence.revision = sqlite3_column_int64(stmt, 8)
            occurrence.reviewReason = optionalString(stmt, 9)
            occurrences.append(occurrence)
        }
        return occurrences
    }

    @discardableResult func saveRecurringRule(_ input: RecurringRule) throws -> RecurringRule {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 120 else { throw DailyValidationError.emptyName }
        guard input.amountMinor > 0 else { throw DailyValidationError.invalidAmount }
        guard input.nextIndex >= 0, (0...14).contains(input.reviewWindowDays),
              input.endDay == nil || input.endDay! >= input.startDay,
              TimeZone(identifier: input.timeZoneIdentifier) != nil else { throw DailyValidationError.invalidRule }
        try execute("BEGIN IMMEDIATE")
        do {
            let account = try localAccounts().first { $0.id == input.accountID }
            guard let account else { throw DailyValidationError.missingAccount }
            let existing = try recurringRules(includeArchived: true).first { $0.id == input.id }
            if account.archivedAt != nil && existing?.accountID != account.id {
                throw DailyValidationError.archivedAccount
            }
            if let categoryID = input.categoryID {
                guard let category = try ledgerCategories().first(where: { $0.id == categoryID }),
                      category.archivedAt == nil || existing?.categoryID == categoryID else {
                    throw DailyValidationError.invalidCategory
                }
            }
            guard existing?.revision == input.revision || (existing == nil && input.revision == 0) else {
                throw DailyValidationError.staleRecord
            }
            var item = input
            item.name = name
            item.updatedAt = .now
            item.revision = (existing?.revision ?? 0) + 1
            if let existing {
                let scheduleChanged = item.startDay != existing.startDay || item.frequency != existing.frequency ||
                    item.timeZoneIdentifier != existing.timeZoneIdentifier
                if scheduleChanged {
                    let oldOccurrences = try recurringOccurrences(ruleID: item.id)
                    let today = LocalDay(date: .now, timeZone: try RecurringSchedule.timeZone(for: existing))
                    let protected = oldOccurrences.filter { $0.status != .cancelled &&
                        ($0.status != .expected || $0.scheduledDay <= today) }
                    let lastDay = protected.map(\.scheduledDay).max()
                    guard lastDay == nil || item.startDay > lastDay! else { throw DailyValidationError.invalidRule }
                    for occurrence in oldOccurrences where occurrence.status == .expected && occurrence.scheduledDay > today {
                        try setOccurrence(occurrence, status: .cancelled, transactionID: nil)
                        try appendReconciliationAudit(occurrenceID: occurrence.id, action: "cancel-future",
                                                      actor: "user", oldStatus: .expected,
                                                      newStatus: .cancelled, oldTransactionID: nil,
                                                      newTransactionID: nil, ruleRevision: existing.revision)
                    }
                    item.nextIndex = 0
                } else {
                    item.nextIndex = existing.nextIndex
                }
            } else { item.nextIndex = 0 }
            let stmt = try statement("""
                INSERT INTO recurring_rules_local
                (id,name,kind,amount_minor,account_id,category_id,start_day,frequency,next_index,
                 end_day,timezone_id,is_active,note,created_at,updated_at,archived_at,revision,historical_source_id,review_window_days)
                VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET name=excluded.name,kind=excluded.kind,
                    amount_minor=excluded.amount_minor,account_id=excluded.account_id,
                    category_id=excluded.category_id,start_day=excluded.start_day,
                    frequency=excluded.frequency,next_index=excluded.next_index,
                    end_day=excluded.end_day,timezone_id=excluded.timezone_id,
                    is_active=excluded.is_active,note=excluded.note,
                    updated_at=excluded.updated_at,archived_at=excluded.archived_at,
                    revision=excluded.revision,review_window_days=excluded.review_window_days
                """)
            bind(item.id.uuidString, at: 1, to: stmt)
            bind(item.name, at: 2, to: stmt)
            bind(item.type.rawValue, at: 3, to: stmt)
            sqlite3_bind_int64(stmt, 4, item.amountMinor)
            bind(item.accountID.uuidString, at: 5, to: stmt)
            bindOptional(item.categoryID?.uuidString, at: 6, to: stmt)
            bind(item.startDay.isoString, at: 7, to: stmt)
            bind(item.frequency.rawValue, at: 8, to: stmt)
            sqlite3_bind_int64(stmt, 9, Int64(item.nextIndex))
            bindOptional(item.endDay?.isoString, at: 10, to: stmt)
            bind(item.timeZoneIdentifier, at: 11, to: stmt)
            sqlite3_bind_int(stmt, 12, item.isActive ? 1 : 0)
            bind(item.note, at: 13, to: stmt)
            sqlite3_bind_double(stmt, 14, item.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 15, item.updatedAt.timeIntervalSince1970)
            if let archived = item.archivedAt { sqlite3_bind_double(stmt, 16, archived.timeIntervalSince1970) }
            else { sqlite3_bind_null(stmt, 16) }
            sqlite3_bind_int64(stmt, 17, item.revision)
            bindOptional(item.historicalSourceID, at: 18, to: stmt)
            sqlite3_bind_int(stmt, 19, Int32(item.reviewWindowDays))
            let saved = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
            guard saved == SQLITE_DONE else { throw error() }
            let action = existing == nil ? "recurring-create" :
                (existing?.archivedAt == nil && item.archivedAt != nil ? "recurring-archive" :
                 (existing?.archivedAt != nil && item.archivedAt == nil ? "recurring-restore" :
                  (existing?.isActive == true && !item.isActive ? "recurring-pause" :
                   (existing?.isActive == false && item.isActive ? "recurring-resume" : "recurring-update"))))
            try appendDailyOperation(entityID: item.id, action: action,
                                     revision: item.revision, value: item)
            try execute("COMMIT")
            return item
        } catch { try? execute("ROLLBACK"); throw error }
    }

    private func occurrenceExists(_ id: String) throws -> Bool {
        let stmt = try statement("SELECT 1 FROM recurring_occurrences_local WHERE id=? LIMIT 1")
        defer { sqlite3_finalize(stmt) }
        bind(id, at: 1, to: stmt)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    @discardableResult func ensureExpected(_ rule: RecurringRule, day: LocalDay) throws -> Bool {
        let occurrenceID = RecurringSchedule.occurrenceID(ruleID: rule.id, day: day)
        if let old = try recurringOccurrences(ruleID: rule.id).first(where: { $0.id == occurrenceID }) {
            guard old.status == .cancelled && old.provisionalTransactionID == nil else { return false }
            try setOccurrence(old, status: .expected, transactionID: nil)
            try appendReconciliationAudit(occurrenceID: occurrenceID, action: "reschedule-same-day",
                                          actor: "schedule", oldStatus: .cancelled,
                                          newStatus: .expected, oldTransactionID: nil,
                                          newTransactionID: nil, ruleRevision: rule.revision)
            return true
        }
        let now = Date().timeIntervalSince1970
        let stmt = try statement("""
            INSERT INTO recurring_occurrences_local
            (id,rule_id,scheduled_day,status,transaction_id,created_at,updated_at,revision)
            VALUES(?,?,?,'expected',NULL,?,?,1)
            """)
        defer { sqlite3_finalize(stmt) }
        bind(occurrenceID, at: 1, to: stmt)
        bind(rule.id.uuidString, at: 2, to: stmt)
        bind(day.isoString, at: 3, to: stmt)
        sqlite3_bind_double(stmt, 4, now)
        sqlite3_bind_double(stmt, 5, now)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
        try appendReconciliationAudit(occurrenceID: occurrenceID, action: "expect", actor: "schedule",
                                      oldStatus: nil, newStatus: .expected, oldTransactionID: nil,
                                      newTransactionID: nil, ruleRevision: rule.revision)
        return true
    }

    func recordPayment(_ rule: RecurringRule, day: LocalDay,
                               occurredAt: Date) throws -> Transaction {
        let occurrenceID = RecurringSchedule.occurrenceID(ruleID: rule.id, day: day)
        guard let occurrence = try recurringOccurrences(ruleID: rule.id).first(where: { $0.id == occurrenceID }),
              occurrence.status == .expected else { throw RecurringError.occurrenceChanged }
        guard let account = try localAccounts().first(where: { $0.id == rule.accountID }) else {
            throw DailyValidationError.missingAccount
        }
        let category = try rule.categoryID.flatMap { id in try ledgerCategories().first { $0.id == id } }
        let values = TransactionEditPolicy.values(original: nil, kind: rule.type.transactionKind,
                                                  newEURMinor: rule.amountMinor)
        var item = Transaction(id: UUID(), kind: rule.type.transactionKind,
                               amountMinor: rule.amountMinor, currency: "EUR",
                               merchant: rule.name, account: account.name,
                               category: category?.name ?? "", note: rule.note,
                               occurredAt: occurredAt, updatedAt: .now,
                               deletedAt: nil, isDemo: false, revision: 0, sourceEventID: nil)
        item.eurMinor = rule.amountMinor
        item.personalExpenseEURMinor = values.personal
        item.recoverableEURMinor = values.recoverable
        item.accountID = account.id
        item.categoryID = category?.id
        item.recurringOccurrenceID = occurrenceID
        let saved = try save(item, manageTransaction: false)
        let stmt = try statement("""
            UPDATE recurring_occurrences_local
            SET status='recorded_manual',transaction_id=?,updated_at=?,revision=revision+1,
                review_reason=NULL WHERE id=? AND status='expected' AND revision=?
            """)
        defer { sqlite3_finalize(stmt) }
        bind(saved.id.uuidString, at: 1, to: stmt)
        sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
        bind(occurrenceID, at: 3, to: stmt)
        sqlite3_bind_int64(stmt, 4, occurrence.revision)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
        guard sqlite3_changes(handle) == 1 else { throw RecurringError.occurrenceChanged }
        try appendReconciliationAudit(occurrenceID: occurrenceID, action: "record-manually", actor: "user",
                                      oldStatus: .expected, newStatus: .recordedManual,
                                      oldTransactionID: nil, newTransactionID: saved.id,
                                      ruleRevision: rule.revision)
        return saved
    }

    private func skipOccurrence(_ rule: RecurringRule, day: LocalDay) throws {
        let id = RecurringSchedule.occurrenceID(ruleID: rule.id, day: day)
        guard try !occurrenceExists(id) else { throw RecurringError.occurrenceChanged }
        let stmt = try statement("""
            INSERT INTO recurring_occurrences_local
            (id,rule_id,scheduled_day,status,transaction_id,created_at,updated_at,revision)
            VALUES(?,?,?,'skipped',NULL,?,?,1)
            """)
        defer { sqlite3_finalize(stmt) }
        bind(id, at: 1, to: stmt)
        bind(rule.id.uuidString, at: 2, to: stmt)
        bind(day.isoString, at: 3, to: stmt)
        sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
        sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
        try appendReconciliationAudit(occurrenceID: id, action: "skip", actor: "user",
                                      oldStatus: nil, newStatus: .skipped, oldTransactionID: nil,
                                      newTransactionID: nil, ruleRevision: rule.revision)
    }

    private func advance(_ rule: RecurringRule, to index: Int, action: String) throws {
        var updated = rule
        updated.nextIndex = index
        updated.revision += 1
        updated.updatedAt = .now
        let stmt = try statement("""
            UPDATE recurring_rules_local SET next_index=?,revision=?,updated_at=?
            WHERE id=? AND revision=?
            """)
        sqlite3_bind_int64(stmt, 1, Int64(index))
        sqlite3_bind_int64(stmt, 2, updated.revision)
        sqlite3_bind_double(stmt, 3, updated.updatedAt.timeIntervalSince1970)
        bind(rule.id.uuidString, at: 4, to: stmt)
        sqlite3_bind_int64(stmt, 5, rule.revision)
        guard sqlite3_step(stmt) == SQLITE_DONE else { sqlite3_finalize(stmt); throw error() }
        sqlite3_finalize(stmt)
        guard sqlite3_changes(handle) == 1 else { throw DailyValidationError.staleRecord }
        try appendDailyOperation(entityID: updated.id, action: action,
                                 revision: updated.revision, value: updated)
    }

    @discardableResult func materializeDueRecurring(now: Date = .now) throws -> Int {
        let rules = try recurringRules().filter(\.isActive)
        let unlinked = try transactions().filter { !$0.isDemo && $0.recurringOccurrenceID == nil }
        var total = 0
        for rule in rules {
            let due = try RecurringSchedule.due(for: rule, now: now)
            guard !due.isEmpty else { continue }
            try execute("BEGIN IMMEDIATE")
            do {
                for occurrence in due {
                    if try ensureExpected(rule, day: occurrence.day) { total += 1 }
                    try suggestExistingRecurringPayments(rule: rule, day: occurrence.day,
                                                         transactions: unlinked)
                }
                try advance(rule, to: due.last!.index + 1, action: "recurring-catch-up")
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
        return total
    }

    @discardableResult func createNextRecurringNow(_ ruleID: UUID, now: Date = .now) throws -> Transaction {
        try execute("BEGIN IMMEDIATE")
        do {
            guard let rule = try recurringRules().first(where: { $0.id == ruleID }),
                  rule.isActive else { throw RecurringError.inactive }
            guard let day = try RecurringSchedule.nextDay(for: rule) else { throw RecurringError.invalidSchedule }
            guard try ensureExpected(rule, day: day) else { throw RecurringError.occurrenceChanged }
            let transaction = try recordPayment(rule, day: day, occurredAt: now)
            try advance(rule, to: rule.nextIndex + 1, action: "recurring-create-now")
            try execute("COMMIT")
            return transaction
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func skipNextRecurring(_ ruleID: UUID) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            guard let rule = try recurringRules().first(where: { $0.id == ruleID }),
                  rule.isActive else { throw RecurringError.inactive }
            guard let day = try RecurringSchedule.nextDay(for: rule) else { throw RecurringError.invalidSchedule }
            try skipOccurrence(rule, day: day)
            try advance(rule, to: rule.nextIndex + 1, action: "recurring-skip")
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }


}
