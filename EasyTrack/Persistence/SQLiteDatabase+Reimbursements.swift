import Foundation
import SQLite3

extension SQLiteDatabase {
    func migrateToSchemaNine() throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("""
                CREATE TABLE IF NOT EXISTS expense_reimbursement_plans (
                    expense_id TEXT PRIMARY KEY,
                    expected_eur_minor INTEGER NOT NULL CHECK(expected_eur_minor>0),
                    written_off_eur_minor INTEGER NOT NULL DEFAULT 0 CHECK(written_off_eur_minor>=0),
                    created_at REAL NOT NULL, updated_at REAL NOT NULL,
                    revision INTEGER NOT NULL CHECK(revision>0),
                    FOREIGN KEY(expense_id) REFERENCES transactions(id),
                    CHECK(written_off_eur_minor<=expected_eur_minor)
                )
                """)
            try execute("""
                CREATE TABLE IF NOT EXISTS expense_reimbursement_links (
                    expense_id TEXT NOT NULL, reimbursement_id TEXT NOT NULL UNIQUE,
                    amount_eur_minor INTEGER NOT NULL CHECK(amount_eur_minor>0),
                    created_at REAL NOT NULL,
                    PRIMARY KEY(expense_id,reimbursement_id),
                    FOREIGN KEY(expense_id) REFERENCES expense_reimbursement_plans(expense_id),
                    FOREIGN KEY(reimbursement_id) REFERENCES transactions(id),
                    CHECK(expense_id!=reimbursement_id)
                )
                """)
            try execute("PRAGMA user_version=9")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func reimbursementStatuses() throws -> [ExpenseReimbursementStatus] {
        let stmt = try statement("""
            SELECT p.expense_id,p.expected_eur_minor,p.written_off_eur_minor,p.updated_at,
                   l.reimbursement_id,l.amount_eur_minor,
                   e.kind,e.currency,e.amount_minor,e.eur_minor
            FROM expense_reimbursement_plans p
            LEFT JOIN expense_reimbursement_links l ON l.expense_id=p.expense_id
            JOIN transactions e ON e.id=p.expense_id
            WHERE e.deleted_at IS NULL
            ORDER BY p.expense_id,l.created_at,l.reimbursement_id
            """)
        defer { sqlite3_finalize(stmt) }
        struct Mutable {
            var expected: Int64
            var received: Int64
            var writtenOff: Int64
            var gross: Int64
            var ids: [UUID]
            var updated: Date
        }
        var values: [UUID: Mutable] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let expenseID = UUID(uuidString: string(stmt, 0)) else { continue }
            let currency = string(stmt, 7)
            let gross = currency == "EUR" ? sqlite3_column_int64(stmt, 8) :
                (sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 9))
            guard ["expense", "advanceForOthers"].contains(string(stmt, 6)),
                  let gross, gross > 0 else { throw ReimbursementError.invalidExpectedAmount }
            var value = values[expenseID] ?? Mutable(expected: sqlite3_column_int64(stmt, 1),
                received: 0, writtenOff: sqlite3_column_int64(stmt, 2), gross: gross, ids: [],
                updated: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)))
            if let reimbursementID = UUID(uuidString: string(stmt, 4)) {
                let (received, overflow) = value.received.addingReportingOverflow(sqlite3_column_int64(stmt, 5))
                guard !overflow else { throw FinancialAnalyticsError.amountOverflow }
                value.received = received
                value.ids.append(reimbursementID)
            }
            values[expenseID] = value
        }
        return try values.map { expenseID, value in
            guard value.expected > 0, value.received >= 0,
                  value.writtenOff >= 0, value.writtenOff <= value.expected else {
                throw ReimbursementError.invalidExpectedAmount
            }
            let afterReceipt = value.received >= value.expected ? 0 : value.expected - value.received
            let outstanding = value.writtenOff >= afterReceipt ? 0 : afterReceipt - value.writtenOff
            return ExpenseReimbursementStatus(expenseID: expenseID, expectedEURMinor: value.expected,
                receivedEURMinor: value.received, writtenOffEURMinor: value.writtenOff,
                outstandingEURMinor: outstanding,
                linkedTransactionIDs: value.ids, updatedAt: value.updated,
                attributedPrincipalEURMinor: min(value.gross, value.received))
        }.sorted { $0.expenseID.uuidString < $1.expenseID.uuidString }
    }

    func reimbursementLinks() throws -> [ExpenseReimbursementLink] {
        let stmt = try statement("""
            SELECT expense_id,reimbursement_id,amount_eur_minor,created_at
            FROM expense_reimbursement_links ORDER BY expense_id,created_at,reimbursement_id
            """)
        defer { sqlite3_finalize(stmt) }
        var result: [ExpenseReimbursementLink] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let expenseID = UUID(uuidString: string(stmt, 0)),
                  let reimbursementID = UUID(uuidString: string(stmt, 1)) else { continue }
            result.append(ExpenseReimbursementLink(expenseID: expenseID,
                reimbursementID: reimbursementID, amountEURMinor: sqlite3_column_int64(stmt, 2),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))))
        }
        return result
    }

    // Personal cost is attributed to the original expense date. This repairs the old
    // exclusion-at-creation value without changing a cash movement, revision or audit entry.
    func reconcileReimbursementAccounting(manageTransaction: Bool = true) throws {
        if manageTransaction { try execute("BEGIN IMMEDIATE") }
        do {
        let query = try statement("""
            SELECT e.id,e.kind,e.currency,e.amount_minor,e.eur_minor,
                   e.personal_expense_eur_minor,p.expected_eur_minor,p.written_off_eur_minor,
                   COALESCE(s.received,0),e.recoverable_eur_minor
            FROM expense_reimbursement_plans p
            JOIN transactions e ON e.id=p.expense_id
            LEFT JOIN (SELECT expense_id,SUM(amount_eur_minor) received
                       FROM expense_reimbursement_links GROUP BY expense_id) s ON s.expense_id=p.expense_id
            WHERE e.deleted_at IS NULL
            """)
        var changes: [(String, Int64, Int64)] = []
        var step = sqlite3_step(query)
        while step == SQLITE_ROW {
            let id = string(query, 0)
            let kind = string(query, 1)
            let currency = string(query, 2)
            let gross: Int64? = currency == "EUR" ? sqlite3_column_int64(query, 3) :
                (sqlite3_column_type(query, 4) == SQLITE_NULL ? nil : sqlite3_column_int64(query, 4))
            let expected = sqlite3_column_int64(query, 6)
            let writtenOff = sqlite3_column_int64(query, 7)
            let received = sqlite3_column_int64(query, 8)
            guard let gross, gross > 0, expected > 0,
                  writtenOff >= 0, writtenOff <= expected, received >= 0,
                  kind == "expense" || kind == "advanceForOthers" else {
                sqlite3_finalize(query)
                throw ReimbursementError.invalidExpectedAmount
            }
            let principal = min(gross, received)
            let remainingPrincipal = gross - principal
            let personal = kind == "expense" ? remainingPrincipal : min(writtenOff, remainingPrincipal)
            let afterReceipt = received >= expected ? 0 : expected - received
            let outstanding = writtenOff >= afterReceipt ? 0 : afterReceipt - writtenOff
            if sqlite3_column_type(query, 5) == SQLITE_NULL || sqlite3_column_int64(query, 5) != personal ||
               sqlite3_column_type(query, 9) == SQLITE_NULL || sqlite3_column_int64(query, 9) != outstanding {
                changes.append((id, personal, outstanding))
            }
            step = sqlite3_step(query)
        }
        sqlite3_finalize(query)
        guard step == SQLITE_DONE else { throw error() }
        if !changes.isEmpty {
            let update = try statement("""
                UPDATE transactions SET personal_expense_eur_minor=?,recoverable_eur_minor=? WHERE id=?
                """)
            defer { sqlite3_finalize(update) }
            for (id, personal, outstanding) in changes {
                sqlite3_reset(update)
                sqlite3_clear_bindings(update)
                sqlite3_bind_int64(update, 1, personal)
                sqlite3_bind_int64(update, 2, outstanding)
                bind(id, at: 3, to: update)
                guard sqlite3_step(update) == SQLITE_DONE else { throw error() }
            }
        }
        if manageTransaction { try execute("COMMIT") }
        } catch {
            if manageTransaction { try? execute("ROLLBACK") }
            throw error
        }
    }

    @discardableResult
    func save(_ input: Transaction, expectedReimbursementEURMinor: Int64?) throws -> Transaction {
        try execute("BEGIN IMMEDIATE")
        do {
            let saved = try save(input, manageTransaction: false)
            if let expectedReimbursementEURMinor {
                try configureExpectedReimbursement(expenseID: saved.id,
                    expectedEURMinor: expectedReimbursementEURMinor, manageTransaction: false)
            }
            try execute("COMMIT")
            return try transaction(saved.id) ?? saved
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func configureExpectedReimbursement(expenseID: UUID, expectedEURMinor: Int64,
                                        manageTransaction: Bool = true) throws {
        if manageTransaction { try execute("BEGIN IMMEDIATE") }
        do {
            guard let expense = try transaction(expenseID),
                  expense.kind == .expense || expense.kind == .advanceForOthers else {
                throw ReimbursementError.expenseRequired
            }
            guard verifiedEUR(expense) != nil, expectedEURMinor > 0 else {
                throw ReimbursementError.invalidExpectedAmount
            }
            let existing = try reimbursementStatuses().first { $0.expenseID == expenseID }
            guard (existing?.writtenOffEURMinor ?? 0) <= expectedEURMinor else {
                throw ReimbursementError.invalidExpectedAmount
            }
            let now = Date().timeIntervalSince1970
            let stmt = try statement("""
                INSERT INTO expense_reimbursement_plans
                    (expense_id,expected_eur_minor,written_off_eur_minor,created_at,updated_at,revision)
                VALUES(?,?,0,?,?,1)
                ON CONFLICT(expense_id) DO UPDATE SET expected_eur_minor=excluded.expected_eur_minor,
                    updated_at=excluded.updated_at,revision=expense_reimbursement_plans.revision+1
                """)
            defer { sqlite3_finalize(stmt) }
            bind(expenseID.uuidString, at: 1, to: stmt)
            sqlite3_bind_int64(stmt, 2, expectedEURMinor)
            sqlite3_bind_double(stmt, 3, now)
            sqlite3_bind_double(stmt, 4, now)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
            try syncReimbursementExpense(expenseID)
            if manageTransaction { try execute("COMMIT") }
        } catch {
            if manageTransaction { try? execute("ROLLBACK") }
            throw error
        }
    }

    func linkReimbursement(expenseID: UUID, reimbursementID: UUID,
                           manageTransaction: Bool = true) throws {
        if manageTransaction { try execute("BEGIN IMMEDIATE") }
        do {
            guard try reimbursementStatuses().contains(where: { $0.expenseID == expenseID }),
                  let expense = try transaction(expenseID) else { throw ReimbursementError.missingPlan }
            guard let reimbursement = try transaction(reimbursementID), reimbursement.kind == .reimbursement else {
                throw ReimbursementError.reimbursementRequired
            }
            guard !(try reimbursementLinks().contains { $0.reimbursementID == reimbursementID }) else {
                throw ReimbursementError.alreadyLinked
            }
            guard verifiedCurrency(expense), verifiedCurrency(reimbursement),
                  let amount = verifiedEUR(reimbursement) else { throw ReimbursementError.conversionRequired }
            let stmt = try statement("""
                INSERT INTO expense_reimbursement_links
                    (expense_id,reimbursement_id,amount_eur_minor,created_at) VALUES(?,?,?,?)
                """)
            bind(expenseID.uuidString, at: 1, to: stmt)
            bind(reimbursementID.uuidString, at: 2, to: stmt)
            sqlite3_bind_int64(stmt, 3, amount)
            sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
            let result = sqlite3_step(stmt)
            sqlite3_finalize(stmt)
            guard result == SQLITE_DONE else { throw error() }
            var linked = reimbursement
            linked.personalExpenseEURMinor = 0
            linked.recoverableEURMinor = 0
            _ = try save(linked, manageTransaction: false)
            try syncReimbursementExpense(expenseID)
            if manageTransaction { try execute("COMMIT") }
        } catch {
            if manageTransaction { try? execute("ROLLBACK") }
            throw error
        }
    }

    @discardableResult
    func createAndLinkReimbursement(expenseID: UUID, reimbursement: Transaction) throws -> Transaction {
        try execute("BEGIN IMMEDIATE")
        do {
            let saved = try save(reimbursement, manageTransaction: false)
            try linkReimbursement(expenseID: expenseID, reimbursementID: saved.id,
                                  manageTransaction: false)
            try execute("COMMIT")
            return try transaction(saved.id) ?? saved
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func unlinkReimbursement(_ reimbursementID: UUID) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try unlinkReimbursement(reimbursementID, restorePersonalAdjustment: true)
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func writeOffOutstandingReimbursement(_ expenseID: UUID) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            guard let status = try reimbursementStatuses().first(where: { $0.expenseID == expenseID }) else {
                throw ReimbursementError.missingPlan
            }
            let writtenOff = try Self.checkedAdd(status.writtenOffEURMinor, status.outstandingEURMinor)
            try updateWrittenOff(expenseID, amount: writtenOff)
            try syncReimbursementExpense(expenseID)
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func undoReimbursementWriteOff(_ expenseID: UUID) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            guard try reimbursementStatuses().contains(where: { $0.expenseID == expenseID }) else {
                throw ReimbursementError.missingPlan
            }
            try updateWrittenOff(expenseID, amount: 0)
            try syncReimbursementExpense(expenseID)
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func prepareReimbursementDeletion(_ item: Transaction) throws {
        guard item.deletedAt != nil else { return }
        if try reimbursementLinks().contains(where: { $0.reimbursementID == item.id }) {
            try unlinkReimbursement(item.id, restorePersonalAdjustment: false)
        }
        if try reimbursementStatuses().contains(where: { $0.expenseID == item.id }) {
            let receiptIDs = try reimbursementLinks().filter { $0.expenseID == item.id }.map(\.reimbursementID)
            try execute("DELETE FROM expense_reimbursement_links WHERE expense_id='\(item.id.uuidString)'")
            try execute("DELETE FROM expense_reimbursement_plans WHERE expense_id='\(item.id.uuidString)'")
            for id in receiptIDs {
                if var receipt = try transaction(id) {
                    receipt.personalExpenseEURMinor = verifiedEUR(receipt).map { -$0 }
                    _ = try save(receipt, manageTransaction: false)
                }
            }
        }
    }

    func reimbursementAdjusted(_ input: Transaction) throws -> Transaction {
        guard input.deletedAt == nil else { return input }
        var item = input
        if let status = try reimbursementStatuses().first(where: { $0.expenseID == input.id }) {
            guard (input.kind == .expense || input.kind == .advanceForOthers),
                  let gross = verifiedEUR(input), gross > 0 else {
                throw ReimbursementError.invalidExpectedAmount
            }
            let attributedPrincipal = min(gross, status.receivedEURMinor)
            let remainingPrincipal = gross - attributedPrincipal
            item.personalExpenseEURMinor = input.kind == .expense
                ? remainingPrincipal
                : min(status.writtenOffEURMinor, remainingPrincipal)
            item.recoverableEURMinor = status.outstandingEURMinor
        }
        if let link = try reimbursementLinks().first(where: { $0.reimbursementID == input.id }) {
            guard input.kind == .reimbursement, let existing = try transaction(input.id),
                  existing.kind == input.kind, existing.currency == input.currency,
                  existing.amountMinor == input.amountMinor, existing.eurMinor == input.eurMinor,
                  existing.accountID == input.accountID, existing.account == input.account else {
                throw ReimbursementError.linkedReceiptRequiresUnlink
            }
            guard link.amountEURMinor == verifiedEUR(input) else {
                throw ReimbursementError.linkedReceiptRequiresUnlink
            }
            item.personalExpenseEURMinor = 0
            item.recoverableEURMinor = 0
        }
        return item
    }

    private func transaction(_ id: UUID) throws -> Transaction? {
        try transactions(includeDeleted: true).first { $0.id == id && $0.deletedAt == nil }
    }

    private func syncReimbursementExpense(_ expenseID: UUID) throws {
        guard let expense = try transaction(expenseID) else { return }
        _ = try save(expense, manageTransaction: false)
    }

    private func unlinkReimbursement(_ reimbursementID: UUID,
                                     restorePersonalAdjustment: Bool) throws {
        guard let link = try reimbursementLinks().first(where: { $0.reimbursementID == reimbursementID }) else {
            throw ReimbursementError.alreadyLinked
        }
        let stmt = try statement("DELETE FROM expense_reimbursement_links WHERE reimbursement_id=?")
        bind(reimbursementID.uuidString, at: 1, to: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { sqlite3_finalize(stmt); throw error() }
        sqlite3_finalize(stmt)
        if restorePersonalAdjustment, var reimbursement = try transaction(reimbursementID) {
            reimbursement.personalExpenseEURMinor = verifiedEUR(reimbursement).map { -$0 }
            _ = try save(reimbursement, manageTransaction: false)
        }
        try syncReimbursementExpense(link.expenseID)
    }

    private func updateWrittenOff(_ expenseID: UUID, amount: Int64) throws {
        let stmt = try statement("""
            UPDATE expense_reimbursement_plans
            SET written_off_eur_minor=?,updated_at=?,revision=revision+1 WHERE expense_id=?
            """)
        sqlite3_bind_int64(stmt, 1, amount)
        sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
        bind(expenseID.uuidString, at: 3, to: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { sqlite3_finalize(stmt); throw error() }
        sqlite3_finalize(stmt)
    }

    private func verifiedEUR(_ item: Transaction) -> Int64? {
        item.eurMinor ?? (item.currency == "EUR" ? item.amountMinor : nil)
    }

    private func verifiedCurrency(_ item: Transaction) -> Bool {
        item.currency == "EUR" || (item.eurMinor != nil && item.exchangeRateEUR?.isEmpty == false)
    }

    private static func checkedAdd(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw FinancialAnalyticsError.amountOverflow }
        return value
    }
}
