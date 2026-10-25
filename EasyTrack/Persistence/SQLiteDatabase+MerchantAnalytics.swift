import Foundation
import SQLite3

extension SQLiteDatabase {
    func migrateToSchemaEight() throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("""
                CREATE TABLE IF NOT EXISTS merchant_alias_groups (
                    group_id TEXT NOT NULL,
                    normalized_merchant TEXT NOT NULL UNIQUE,
                    canonical_name TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    PRIMARY KEY(group_id,normalized_merchant)
                )
                """)
            try execute("PRAGMA user_version=8")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func merchantAliasGroups() throws -> [MerchantAliasGroup] {
        let stmt = try statement("""
            SELECT group_id,normalized_merchant,canonical_name,created_at,updated_at
            FROM merchant_alias_groups ORDER BY group_id,normalized_merchant
            """)
        defer { sqlite3_finalize(stmt) }
        var groups: [UUID: MerchantAliasGroup] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(stmt, 0)) else { continue }
            let key = string(stmt, 1)
            if var group = groups[id] {
                group.memberKeys.append(key)
                groups[id] = group
            } else {
                groups[id] = MerchantAliasGroup(id: id, canonicalName: string(stmt, 2),
                    memberKeys: [key], createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)))
            }
        }
        return groups.values.sorted {
            $0.canonicalName.localizedCaseInsensitiveCompare($1.canonicalName) == .orderedAscending
        }
    }

    func saveMerchantAliasGroup(_ group: MerchantAliasGroup) throws {
        let keys = Array(Set(group.memberKeys)).sorted()
        guard keys.count > 1, !group.canonicalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              keys.allSatisfy({ !$0.isEmpty }) else {
            throw DatabaseError.sqlite("invalid merchant grouping")
        }
        try execute("BEGIN IMMEDIATE")
        do {
            let remove = try statement("DELETE FROM merchant_alias_groups WHERE group_id=?")
            bind(group.id.uuidString, at: 1, to: remove)
            guard sqlite3_step(remove) == SQLITE_DONE else { sqlite3_finalize(remove); throw error() }
            sqlite3_finalize(remove)
            let insert = try statement("""
                INSERT INTO merchant_alias_groups
                (group_id,normalized_merchant,canonical_name,created_at,updated_at)
                VALUES(?,?,?,?,?)
                """)
            defer { sqlite3_finalize(insert) }
            for key in keys {
                sqlite3_reset(insert)
                sqlite3_clear_bindings(insert)
                bind(group.id.uuidString, at: 1, to: insert)
                bind(key, at: 2, to: insert)
                bind(group.canonicalName, at: 3, to: insert)
                sqlite3_bind_double(insert, 4, group.createdAt.timeIntervalSince1970)
                sqlite3_bind_double(insert, 5, group.updatedAt.timeIntervalSince1970)
                guard sqlite3_step(insert) == SQLITE_DONE else { throw error() }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func deleteMerchantAliasGroup(_ id: UUID) throws {
        let stmt = try statement("DELETE FROM merchant_alias_groups WHERE group_id=?")
        defer { sqlite3_finalize(stmt) }
        bind(id.uuidString, at: 1, to: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
    }
}
