import Foundation
import SQLite3

extension SQLiteDatabase {
    func migrateToSchemaEleven() throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("""
                CREATE TABLE IF NOT EXISTS monthly_budgets (
                    id TEXT PRIMARY KEY, scope TEXT NOT NULL CHECK(scope IN ('overall','category')),
                    category_id TEXT, limit_eur_minor INTEGER NOT NULL CHECK(limit_eur_minor>0),
                    created_at REAL NOT NULL, updated_at REAL NOT NULL, archived_at REAL,
                    revision INTEGER NOT NULL CHECK(revision>0),
                    CHECK((scope='overall' AND category_id IS NULL) OR
                          (scope='category' AND category_id IS NOT NULL))
                )
                """)
            try execute("CREATE UNIQUE INDEX IF NOT EXISTS one_active_overall_budget ON monthly_budgets(scope) WHERE scope='overall' AND archived_at IS NULL")
            try execute("CREATE UNIQUE INDEX IF NOT EXISTS one_active_category_budget ON monthly_budgets(category_id) WHERE scope='category' AND archived_at IS NULL")
            try execute("""
                CREATE TABLE IF NOT EXISTS savings_goals (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL,
                    target_eur_minor INTEGER NOT NULL CHECK(target_eur_minor>0),
                    progress_eur_minor INTEGER NOT NULL CHECK(progress_eur_minor>=0),
                    due_day TEXT, created_at REAL NOT NULL, updated_at REAL NOT NULL,
                    archived_at REAL, revision INTEGER NOT NULL CHECK(revision>0)
                )
                """)
            try execute("PRAGMA user_version=11")
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func monthlyBudgets(includeArchived: Bool = true) throws -> [MonthlyBudget] {
        let sql = """
            SELECT id,scope,category_id,limit_eur_minor,created_at,updated_at,archived_at,revision
            FROM monthly_budgets
            """ + (includeArchived ? "" : " WHERE archived_at IS NULL") +
            " ORDER BY archived_at IS NOT NULL,scope,category_id,id"
        let stmt = try statement(sql)
        defer { sqlite3_finalize(stmt) }
        var result: [MonthlyBudget] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(stmt, 0)),
                  let scope = MonthlyBudgetScope(rawValue: string(stmt, 1)) else { continue }
            result.append(MonthlyBudget(id: id, scope: scope,
                categoryID: UUID(uuidString: string(stmt, 2)), limitEURMinor: sqlite3_column_int64(stmt, 3),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5)),
                archivedAt: sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil :
                    Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6)),
                revision: sqlite3_column_int64(stmt, 7)))
        }
        return result
    }

    @discardableResult
    func saveMonthlyBudget(_ input: MonthlyBudget) throws -> MonthlyBudget {
        guard input.limitEURMinor > 0,
              (input.scope == .overall) == (input.categoryID == nil) else {
            throw DatabaseError.sqlite("invalid monthly budget")
        }
        let existing = try monthlyBudgets().first { $0.id == input.id }
        guard existing?.revision == input.revision || (existing == nil && input.revision == 0) else {
            throw DailyValidationError.staleRecord
        }
        var item = input
        item.updatedAt = .now
        item.revision = (existing?.revision ?? 0) + 1
        let stmt = try statement("""
            INSERT INTO monthly_budgets
                (id,scope,category_id,limit_eur_minor,created_at,updated_at,archived_at,revision)
            VALUES(?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET scope=excluded.scope,category_id=excluded.category_id,
                limit_eur_minor=excluded.limit_eur_minor,updated_at=excluded.updated_at,
                archived_at=excluded.archived_at,revision=excluded.revision
            """)
        defer { sqlite3_finalize(stmt) }
        bind(item.id.uuidString, at: 1, to: stmt)
        bind(item.scope.rawValue, at: 2, to: stmt)
        bindOptional(item.categoryID?.uuidString, at: 3, to: stmt)
        sqlite3_bind_int64(stmt, 4, item.limitEURMinor)
        sqlite3_bind_double(stmt, 5, item.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 6, item.updatedAt.timeIntervalSince1970)
        if let archivedAt = item.archivedAt { sqlite3_bind_double(stmt, 7, archivedAt.timeIntervalSince1970) }
        else { sqlite3_bind_null(stmt, 7) }
        sqlite3_bind_int64(stmt, 8, item.revision)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
        return item
    }

    func savingsGoals(includeArchived: Bool = true) throws -> [SavingsGoal] {
        let sql = """
            SELECT id,name,target_eur_minor,progress_eur_minor,due_day,
                   created_at,updated_at,archived_at,revision FROM savings_goals
            """ + (includeArchived ? "" : " WHERE archived_at IS NULL") +
            " ORDER BY archived_at IS NOT NULL,due_day IS NULL,due_day,name COLLATE NOCASE"
        let stmt = try statement(sql)
        defer { sqlite3_finalize(stmt) }
        var result: [SavingsGoal] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(stmt, 0)) else { continue }
            result.append(SavingsGoal(id: id, name: string(stmt, 1),
                targetEURMinor: sqlite3_column_int64(stmt, 2), progressEURMinor: sqlite3_column_int64(stmt, 3),
                dueDate: optionalString(stmt, 4).flatMap(LocalDay.init(isoString:)),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6)),
                archivedAt: sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil :
                    Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7)),
                revision: sqlite3_column_int64(stmt, 8)))
        }
        return result
    }

    @discardableResult
    func saveSavingsGoal(_ input: SavingsGoal) throws -> SavingsGoal {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, input.targetEURMinor > 0, input.progressEURMinor >= 0 else {
            throw DatabaseError.sqlite("invalid savings goal")
        }
        let existing = try savingsGoals().first { $0.id == input.id }
        guard existing?.revision == input.revision || (existing == nil && input.revision == 0) else {
            throw DailyValidationError.staleRecord
        }
        var item = input
        item.name = name
        item.updatedAt = .now
        item.revision = (existing?.revision ?? 0) + 1
        let stmt = try statement("""
            INSERT INTO savings_goals
                (id,name,target_eur_minor,progress_eur_minor,due_day,created_at,updated_at,archived_at,revision)
            VALUES(?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET name=excluded.name,target_eur_minor=excluded.target_eur_minor,
                progress_eur_minor=excluded.progress_eur_minor,due_day=excluded.due_day,
                updated_at=excluded.updated_at,archived_at=excluded.archived_at,revision=excluded.revision
            """)
        defer { sqlite3_finalize(stmt) }
        bind(item.id.uuidString, at: 1, to: stmt)
        bind(item.name, at: 2, to: stmt)
        sqlite3_bind_int64(stmt, 3, item.targetEURMinor)
        sqlite3_bind_int64(stmt, 4, item.progressEURMinor)
        bindOptional(item.dueDate?.isoString, at: 5, to: stmt)
        sqlite3_bind_double(stmt, 6, item.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 7, item.updatedAt.timeIntervalSince1970)
        if let archivedAt = item.archivedAt { sqlite3_bind_double(stmt, 8, archivedAt.timeIntervalSince1970) }
        else { sqlite3_bind_null(stmt, 8) }
        sqlite3_bind_int64(stmt, 9, item.revision)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
        return item
    }
}
