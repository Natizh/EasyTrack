import Foundation
import SQLite3

extension SQLiteDatabase {
    @discardableResult
    func applyTransactionCategoryChanges(_ changes: [TransactionCategoryChange]) throws -> [Transaction] {
        guard !changes.isEmpty, Set(changes.map(\.transactionID)).count == changes.count else {
            throw DatabaseError.sqlite("Choose at least one unique transaction.")
        }
        let categories = try ledgerCategories()
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        for change in changes {
            if let id = change.categoryID {
                guard let category = categoryByID[id], category.archivedAt == nil else {
                    throw DailyValidationError.invalidCategory
                }
            }
        }
        try execute("BEGIN IMMEDIATE")
        do {
            let current = try transactions()
            let byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
            var saved: [Transaction] = []
            for change in changes {
                guard var item = byID[change.transactionID], item.kind == .expense,
                      item.revision == change.expectedRevision else {
                    throw DailyValidationError.staleRecord
                }
                item.categoryID = change.categoryID
                item.category = change.categoryID.flatMap { categoryByID[$0]?.name } ?? ""
                saved.append(try save(item, manageTransaction: false))
            }
            try execute("COMMIT")
            return saved
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func migrateToSchemaTen() throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("""
                CREATE TABLE IF NOT EXISTS category_suggestion_settings (
                    id INTEGER PRIMARY KEY CHECK(id=1),
                    is_enabled INTEGER NOT NULL CHECK(is_enabled IN (0,1)),
                    updated_at REAL NOT NULL
                )
                """)
            try execute("""
                INSERT OR IGNORE INTO category_suggestion_settings(id,is_enabled,updated_at)
                VALUES(1,1,strftime('%s','now'))
                """)
            try execute("""
                CREATE TABLE IF NOT EXISTS category_keyword_rules (
                    id TEXT PRIMARY KEY, pattern TEXT NOT NULL,
                    normalized_pattern TEXT NOT NULL, category_id TEXT NOT NULL,
                    is_enabled INTEGER NOT NULL CHECK(is_enabled IN (0,1)),
                    created_at REAL NOT NULL, updated_at REAL NOT NULL,
                    revision INTEGER NOT NULL CHECK(revision>0),
                    UNIQUE(normalized_pattern,category_id)
                )
                """)
            try execute("CREATE INDEX IF NOT EXISTS category_rules_enabled ON category_keyword_rules(is_enabled,normalized_pattern)")
            try execute("PRAGMA user_version=10")
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func categorySuggestionsEnabled() throws -> Bool {
        let stmt = try statement("SELECT is_enabled FROM category_suggestion_settings WHERE id=1")
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_int(stmt, 0) != 0
    }

    func setCategorySuggestionsEnabled(_ enabled: Bool) throws {
        let stmt = try statement("""
            INSERT INTO category_suggestion_settings(id,is_enabled,updated_at) VALUES(1,?,?)
            ON CONFLICT(id) DO UPDATE SET is_enabled=excluded.is_enabled,updated_at=excluded.updated_at
            """)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, enabled ? 1 : 0)
        sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
    }

    func categoryKeywordRules() throws -> [CategoryKeywordRule] {
        let stmt = try statement("""
            SELECT id,pattern,category_id,is_enabled,created_at,updated_at,revision
            FROM category_keyword_rules ORDER BY updated_at DESC,id
            """)
        defer { sqlite3_finalize(stmt) }
        var result: [CategoryKeywordRule] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(stmt, 0)),
                  let categoryID = UUID(uuidString: string(stmt, 2)) else { continue }
            result.append(CategoryKeywordRule(id: id, pattern: string(stmt, 1),
                categoryID: categoryID, isEnabled: sqlite3_column_int(stmt, 3) != 0,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5)),
                revision: sqlite3_column_int64(stmt, 6)))
        }
        return result
    }

    @discardableResult
    func saveCategoryKeywordRule(_ input: CategoryKeywordRule) throws -> CategoryKeywordRule {
        let pattern = input.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = CategorySuggestionEngine.normalized(pattern)
        guard !normalized.isEmpty, normalized.utf8.count <= 120 else {
            throw DatabaseError.sqlite("invalid category keyword")
        }
        let existing = try categoryKeywordRules().first { $0.id == input.id }
        guard existing?.revision == input.revision || (existing == nil && input.revision == 0) else {
            throw DailyValidationError.staleRecord
        }
        var item = input
        item.pattern = pattern
        item.updatedAt = .now
        item.revision = (existing?.revision ?? 0) + 1
        let stmt = try statement("""
            INSERT INTO category_keyword_rules
                (id,pattern,normalized_pattern,category_id,is_enabled,created_at,updated_at,revision)
            VALUES(?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET pattern=excluded.pattern,
                normalized_pattern=excluded.normalized_pattern,category_id=excluded.category_id,
                is_enabled=excluded.is_enabled,updated_at=excluded.updated_at,revision=excluded.revision
            """)
        defer { sqlite3_finalize(stmt) }
        bind(item.id.uuidString, at: 1, to: stmt)
        bind(item.pattern, at: 2, to: stmt)
        bind(normalized, at: 3, to: stmt)
        bind(item.categoryID.uuidString, at: 4, to: stmt)
        sqlite3_bind_int(stmt, 5, item.isEnabled ? 1 : 0)
        sqlite3_bind_double(stmt, 6, item.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 7, item.updatedAt.timeIntervalSince1970)
        sqlite3_bind_int64(stmt, 8, item.revision)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
        return item
    }

    func deleteCategoryKeywordRule(_ id: UUID) throws {
        let stmt = try statement("DELETE FROM category_keyword_rules WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        bind(id.uuidString, at: 1, to: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
    }
}
