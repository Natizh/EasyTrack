import Foundation
import SQLite3

extension SQLiteDatabase {
    func migrateToSchemaSeven() throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("""
                CREATE TABLE IF NOT EXISTS dashboard_widget_preferences (
                    widget_id TEXT PRIMARY KEY,
                    position INTEGER NOT NULL CHECK(position>=0),
                    is_visible INTEGER NOT NULL CHECK(is_visible IN (0,1)),
                    updated_at REAL NOT NULL
                )
                """)
            try execute("CREATE UNIQUE INDEX IF NOT EXISTS dashboard_widgets_by_position ON dashboard_widget_preferences(position)")
            try execute("PRAGMA user_version=7")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func dashboardWidgetPreferences() throws -> [DashboardWidgetPreference] {
        let stmt = try statement("""
            SELECT widget_id,position,is_visible,updated_at
            FROM dashboard_widget_preferences ORDER BY position,widget_id
            """)
        defer { sqlite3_finalize(stmt) }
        var result: [DashboardWidgetPreference] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(DashboardWidgetPreference(widgetID: string(stmt, 0),
                position: Int(sqlite3_column_int64(stmt, 1)),
                isVisible: sqlite3_column_int(stmt, 2) != 0,
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))))
        }
        return result
    }

    func saveDashboardWidgetPreferences(_ preferences: [DashboardWidgetPreference]) throws {
        guard Set(preferences.map(\.widgetID)).count == preferences.count,
              preferences.allSatisfy({ !$0.widgetID.isEmpty && $0.position >= 0 }),
              Set(preferences.map(\.position)).count == preferences.count else {
            throw DatabaseError.sqlite("invalid dashboard widget preferences")
        }
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("DELETE FROM dashboard_widget_preferences")
            let stmt = try statement("""
                INSERT INTO dashboard_widget_preferences(widget_id,position,is_visible,updated_at)
                VALUES(?,?,?,?)
                """)
            defer { sqlite3_finalize(stmt) }
            for preference in preferences.sorted(by: { $0.position < $1.position }) {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                bind(preference.widgetID, at: 1, to: stmt)
                sqlite3_bind_int64(stmt, 2, Int64(preference.position))
                sqlite3_bind_int(stmt, 3, preference.isVisible ? 1 : 0)
                sqlite3_bind_double(stmt, 4, preference.updatedAt.timeIntervalSince1970)
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func resetDashboardWidgetPreferences() throws {
        try execute("DELETE FROM dashboard_widget_preferences")
    }
}
