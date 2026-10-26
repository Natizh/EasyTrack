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
                   l.reimbursement_id,l.amount_eur_minor
            FROM expense_reimbursement_plans p
            LEFT JOIN expense_reimbursement_links l ON l.expense_id=p.expense_id
            JOIN transactions e ON e.id=p.expense_id
            WHERE e.deleted_at IS NULL
            ORDER BY p.expense_id,l.created_at,l.reimbursement_id
            """)
        defer { sqlite3_finalize(stmt) }
        struct Mutable { var expected: Int64; var received: Int64; var writtenOff: Int64; var ids: [UUID]; var updated: Date }
        var values: [UUID: Mutable] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let expenseID = UUID(uuidString: string(stmt, 0)) else { continue }
            var value = values[expenseID] ?? Mutable(expected: sqlite3_column_int64(stmt, 1),
                received: 0, writtenOff: sqlite3_column_int64(stmt, 2), ids: [],
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
            let settled = try Self.checkedAdd(value.received, value.writtenOff)
            guard settled <= value.expected else { throw ReimbursementError.overpayment }
            return ExpenseReimbursementStatus(expenseID: expenseID, expectedEURMinor: value.expected,
                receivedEURMinor: value.received, writtenOffEURMinor: value.writtenOff,
                outstandingEURMinor: value.expected - settled,
                linkedTransactionIDs: value.ids, updatedAt: value.updated)
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

    @discardableResult
    func save(_ input: Transaction, expectedReimbursementEURMinor: Int64?) throws -> Transaction {
        try execute("BEGIN IMMEDIATE")
        do {
            let currentGross = try transaction(input.id).flatMap(verifiedEUR)
            let configureFirst = expectedReimbursementEURMinor.map { expected in
                currentGross.map { expected <= $0 } == true
            } ?? false
            if configureFirst, let expectedReimbursementEURMinor {
                try configureExpectedReimbursement(expenseID: input.id,
                    expectedEURMinor: expectedReimbursementEURMinor, manageTransaction: false)
            }
            let saved = try save(input, manageTransaction: false)
            if !configureFirst, let expectedReimbursementEURMinor {
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
            guard let expense = try transaction(expenseID), expense.kind == .expense else {
                throw ReimbursementError.expenseRequired
            }
            guard let gross = verifiedEUR(expense), expectedEURMinor > 0, expectedEURMinor <= gross else {
                throw ReimbursementError.invalidExpectedAmount
            }
            let existing = try reimbursementStatuses().first { $0.expenseID == expenseID }
            let settled = try Self.checkedAdd(existing?.receivedEURMinor ?? 0, existing?.writtenOffEURMinor ?? 0)
            guard settled <= expectedEURMinor else { throw ReimbursementError.overpayment }
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
            guard let status = try reimbursementStatuses().first(where: { $0.expenseID == expenseID }),
                  let expense = try transaction(expenseID) else { throw ReimbursementError.missingPlan }
            guard let reimbursement = try transaction(reimbursementID), reimbursement.kind == .reimbursement else {
                throw ReimbursementError.reimbursementRequired
            }
            guard !(try reimbursementLinks().contains { $0.reimbursementID == reimbursementID }) else {
                throw ReimbursementError.alreadyLinked
            }
            guard sameAccount(expense, reimbursement) else { throw ReimbursementError.accountMismatch }
            guard verifiedCurrency(expense), verifiedCurrency(reimbursement),
                  let amount = verifiedEUR(reimbursement) else { throw ReimbursementError.conversionRequired }
            guard amount <= status.outstandingEURMinor else { throw ReimbursementError.overpayment }
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
            guard input.kind == .expense, let gross = verifiedEUR(input), status.expectedEURMinor <= gross else {
                throw ReimbursementError.invalidExpectedAmount
            }
            item.personalExpenseEURMinor = gross - status.expectedEURMinor + status.writtenOffEURMinor
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

    private func sameAccount(_ lhs: Transaction, _ rhs: Transaction) -> Bool {
        if let left = lhs.accountID, let right = rhs.accountID { return left == right }
        return NotificationParser.normalize(lhs.account) == NotificationParser.normalize(rhs.account)
    }

    private static func checkedAdd(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw FinancialAnalyticsError.amountOverflow }
        return value
    }
}
