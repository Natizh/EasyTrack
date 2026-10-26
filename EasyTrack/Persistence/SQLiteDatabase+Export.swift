import Foundation
import SQLite3

extension SQLiteDatabase {
    func transactionExportSnapshot() throws -> TransactionExportSnapshot {
        guard sqlite3_db_readonly(handle, "main") == 1 else {
            throw DatabaseError.sqlite("Transaction export requires a read-only database connection")
        }
        try execute("BEGIN DEFERRED")
        do {
            let items = try transactions(includeDeleted: true)
            let count = try statement("SELECT COUNT(*) FROM transactions")
            let storedCount = sqlite3_step(count) == SQLITE_ROW ? Int(sqlite3_column_int64(count, 0)) : -1
            sqlite3_finalize(count)
            guard items.count == storedCount else { throw DatabaseError.sqlite("A transaction cannot be read for export") }
            let accounts = Dictionary(uniqueKeysWithValues: try localAccounts().map { ($0.id, $0.name) })
            let categories = Dictionary(uniqueKeysWithValues: try ledgerCategories().map { ($0.id, $0.name) })
            let reimbursements = Dictionary(uniqueKeysWithValues: try reimbursementStatuses().map { ($0.expenseID, $0) })
            let trips = Dictionary(uniqueKeysWithValues: try historicalTrips().map { ($0.id, $0.name) })
            let stmt = try statement("SELECT transaction_id,source_payload_json FROM historical_imported_movements")
            var originals: [UUID: HistoricalOriginalValues] = [:]
            var result = sqlite3_step(stmt)
            while result == SQLITE_ROW {
                guard let id = UUID(uuidString: string(stmt, 0)),
                      let source = try? JSONDecoder().decode(HistoricalOriginalValues.self,
                                                             from: Data(string(stmt, 1).utf8)) else {
                    sqlite3_finalize(stmt)
                    throw DatabaseError.sqlite("Historical provenance cannot be read for export")
                }
                originals[id] = source
                result = sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            guard result == SQLITE_DONE else { throw error() }
            try execute("COMMIT")
            return TransactionExportSnapshot(transactions: items, accountNames: accounts,
                                             categoryNames: categories, tripNames: trips,
                                             historicalOriginals: originals,
                                             reimbursementStatuses: reimbursements)
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
}

actor TransactionExportService {
    static let shared = TransactionExportService()

    func snapshot() throws -> TransactionExportSnapshot {
        try SQLiteDatabase.openReadOnly().transactionExportSnapshot()
    }

    func render(_ selection: TransactionExportSelection, options: TransactionExportOptions) throws -> Data {
        try Task.checkCancellation()
        switch options.format {
        case .csv: return try TransactionCSVWriter.encode(selection, options: options)
        case .xlsx: return try TransactionXLSXWriter.encode(selection, options: options)
        }
    }
}
