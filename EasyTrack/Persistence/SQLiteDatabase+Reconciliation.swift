import Foundation
import SQLite3

extension SQLiteDatabase {
    func migrateToSchemaSix() throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try ensureColumn("review_window_days", type: "INTEGER NOT NULL DEFAULT 3 CHECK(review_window_days BETWEEN 0 AND 14)", in: "recurring_rules_local")
            try execute("""
                CREATE TABLE recurring_occurrences_v6 (
                    id TEXT PRIMARY KEY, rule_id TEXT NOT NULL,
                    scheduled_day TEXT NOT NULL,
                    status TEXT NOT NULL CHECK(status IN
                        ('expected','legacy_counted','recorded_manual','confirmed','skipped','missed','cancelled')),
                    transaction_id TEXT UNIQUE, provisional_transaction_id TEXT,
                    created_at REAL NOT NULL, updated_at REAL NOT NULL,
                    revision INTEGER NOT NULL CHECK(revision>0),
                    review_reason TEXT,
                    UNIQUE(rule_id,scheduled_day),
                    FOREIGN KEY(rule_id) REFERENCES recurring_rules_local(id),
                    FOREIGN KEY(transaction_id) REFERENCES transactions(id),
                    FOREIGN KEY(provisional_transaction_id) REFERENCES transactions(id),
                    CHECK((status IN ('legacy_counted','recorded_manual','confirmed')) =
                          (transaction_id IS NOT NULL))
                )
                """)
            try execute("""
                INSERT INTO recurring_occurrences_v6
                    (id,rule_id,scheduled_day,status,transaction_id,provisional_transaction_id,
                     created_at,updated_at,revision,review_reason)
                SELECT o.id,o.rule_id,o.scheduled_day,
                    CASE WHEN o.status='skipped' THEN 'skipped'
                         WHEN t.deleted_at IS NULL THEN 'legacy_counted' ELSE 'expected' END,
                    CASE WHEN o.status='materialized' AND t.deleted_at IS NULL THEN o.transaction_id END,
                    CASE WHEN o.status='materialized' THEN o.transaction_id END,
                    o.created_at,o.created_at,1,
                    CASE WHEN o.status='materialized' AND t.deleted_at IS NOT NULL
                         THEN 'Previous transaction was deleted; review before recording.' END
                FROM recurring_occurrences_local o
                LEFT JOIN transactions t ON t.id=o.transaction_id
                """)
            try execute("DROP TABLE recurring_occurrences_local")
            try execute("ALTER TABLE recurring_occurrences_v6 RENAME TO recurring_occurrences_local")
            try execute("CREATE INDEX recurring_occurrences_by_rule ON recurring_occurrences_local(rule_id,scheduled_day DESC)")
            try execute("DROP INDEX unique_transaction_recurring_occurrence")
            try execute("""
                CREATE UNIQUE INDEX unique_transaction_recurring_occurrence
                ON transactions(recurring_occurrence_id)
                WHERE recurring_occurrence_id IS NOT NULL AND deleted_at IS NULL
                """)
            try execute("""
                CREATE TABLE recurring_candidates (
                    id TEXT PRIMARY KEY, occurrence_id TEXT NOT NULL,
                    event_id TEXT, transaction_id TEXT,
                    status TEXT NOT NULL CHECK(status IN ('pending','rejected','confirmed')),
                    reason TEXT NOT NULL, created_at REAL NOT NULL,
                    updated_at REAL NOT NULL, revision INTEGER NOT NULL,
                    FOREIGN KEY(occurrence_id) REFERENCES recurring_occurrences_local(id),
                    FOREIGN KEY(event_id) REFERENCES notification_events(id),
                    FOREIGN KEY(transaction_id) REFERENCES transactions(id),
                    CHECK(event_id IS NOT NULL OR transaction_id IS NOT NULL),
                    CHECK(status!='confirmed' OR transaction_id IS NOT NULL)
                )
                """)
            try execute("CREATE UNIQUE INDEX recurring_candidate_event ON recurring_candidates(occurrence_id,event_id) WHERE event_id IS NOT NULL")
            try execute("CREATE UNIQUE INDEX recurring_candidate_transaction ON recurring_candidates(occurrence_id,transaction_id) WHERE transaction_id IS NOT NULL")
            try execute("CREATE INDEX recurring_candidates_pending ON recurring_candidates(status,occurrence_id)")
            try execute("""
                CREATE TABLE recurring_payee_aliases (
                    id TEXT PRIMARY KEY, rule_id TEXT NOT NULL,
                    normalized_payee TEXT NOT NULL, created_at REAL NOT NULL,
                    FOREIGN KEY(rule_id) REFERENCES recurring_rules_local(id),
                    UNIQUE(rule_id,normalized_payee)
                )
                """)
            try execute("""
                CREATE TABLE recurring_reconciliation_audit (
                    id TEXT PRIMARY KEY, occurrence_id TEXT NOT NULL,
                    action TEXT NOT NULL, actor TEXT NOT NULL,
                    old_status TEXT, new_status TEXT,
                    old_transaction_id TEXT, new_transaction_id TEXT,
                    rule_revision INTEGER NOT NULL, created_at REAL NOT NULL,
                    FOREIGN KEY(occurrence_id) REFERENCES recurring_occurrences_local(id)
                )
                """)
            let check = try statement("PRAGMA foreign_key_check")
            let broken = sqlite3_step(check) == SQLITE_ROW
            sqlite3_finalize(check)
            guard !broken else { throw DatabaseError.sqlite("Recurring migration found a broken reference") }
            try checkDatabase()
            try execute("PRAGMA user_version=6")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func appendReconciliationAudit(occurrenceID: String, action: String, actor: String,
                                   oldStatus: RecurringOccurrenceStatus?, newStatus: RecurringOccurrenceStatus?,
                                   oldTransactionID: UUID?, newTransactionID: UUID?,
                                   ruleRevision: Int64) throws {
        let stmt = try statement("""
            INSERT INTO recurring_reconciliation_audit
            (id,occurrence_id,action,actor,old_status,new_status,old_transaction_id,
             new_transaction_id,rule_revision,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)
            """)
        defer { sqlite3_finalize(stmt) }
        bind(UUID().uuidString, at: 1, to: stmt)
        bind(occurrenceID, at: 2, to: stmt)
        bind(action, at: 3, to: stmt)
        bind(actor, at: 4, to: stmt)
        bindOptional(oldStatus?.rawValue, at: 5, to: stmt)
        bindOptional(newStatus?.rawValue, at: 6, to: stmt)
        bindOptional(oldTransactionID?.uuidString, at: 7, to: stmt)
        bindOptional(newTransactionID?.uuidString, at: 8, to: stmt)
        sqlite3_bind_int64(stmt, 9, ruleRevision)
        sqlite3_bind_double(stmt, 10, Date().timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
    }

    func recurringCandidates(occurrenceID: String? = nil) throws -> [RecurringCandidate] {
        let sql = """
            SELECT id,occurrence_id,event_id,transaction_id,status,reason,created_at,updated_at,revision
            FROM recurring_candidates
            """ + (occurrenceID == nil ? "" : " WHERE occurrence_id=?") + " ORDER BY created_at ASC,id"
        let stmt = try statement(sql)
        defer { sqlite3_finalize(stmt) }
        if let occurrenceID { bind(occurrenceID, at: 1, to: stmt) }
        var result: [RecurringCandidate] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = UUID(uuidString: string(stmt, 0)),
                  let status = RecurringCandidateStatus(rawValue: string(stmt, 4)) else { continue }
            result.append(RecurringCandidate(id: id, occurrenceID: string(stmt, 1),
                                             eventID: UUID(uuidString: string(stmt, 2)),
                                             transactionID: UUID(uuidString: string(stmt, 3)),
                                             status: status, reason: string(stmt, 5),
                                             createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6)),
                                             updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7)),
                                             revision: sqlite3_column_int64(stmt, 8)))
        }
        return result
    }

    func approveRecurringPayee(_ payee: String, for ruleID: UUID) throws {
        let normalized = NotificationParser.normalize(payee)
        guard !normalized.isEmpty, normalized.utf8.count <= 160 else { throw DailyValidationError.invalidRule }
        try execute("BEGIN IMMEDIATE")
        do {
            guard try recurringRules(includeArchived: true).contains(where: { $0.id == ruleID }) else {
                throw RecurringError.occurrenceChanged
            }
            let stmt = try statement("""
                INSERT OR IGNORE INTO recurring_payee_aliases
                (id,rule_id,normalized_payee,created_at) VALUES(?,?,?,?)
                """)
            bind(UUID().uuidString, at: 1, to: stmt)
            bind(ruleID.uuidString, at: 2, to: stmt)
            bind(normalized, at: 3, to: stmt)
            sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else { sqlite3_finalize(stmt); throw error() }
            sqlite3_finalize(stmt)
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func recurringPayeeAliases(ruleID: UUID) throws -> [String] {
        let stmt = try statement("SELECT normalized_payee FROM recurring_payee_aliases WHERE rule_id=? ORDER BY normalized_payee")
        defer { sqlite3_finalize(stmt) }
        bind(ruleID.uuidString, at: 1, to: stmt)
        var aliases: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW { aliases.append(string(stmt, 0)) }
        return aliases
    }

    @discardableResult func recordExpectedRecurringNow(_ occurrenceID: String, now: Date = .now) throws -> Transaction {
        try execute("BEGIN IMMEDIATE")
        do {
            guard let occurrence = try recurringOccurrences().first(where: { $0.id == occurrenceID }),
                  let rule = try recurringRules(includeArchived: true).first(where: { $0.id == occurrence.ruleID }) else {
                throw RecurringError.occurrenceChanged
            }
            let saved = try recordPayment(rule, day: occurrence.scheduledDay, occurredAt: now)
            try execute("COMMIT")
            return saved
        } catch { try? execute("ROLLBACK"); throw error }
    }

    private func localDayDistance(_ date: Date, from day: LocalDay, in zone: TimeZone) throws -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let start = day.noon(in: zone),
              let actual = LocalDay(date: date, timeZone: zone).noon(in: zone),
              let distance = calendar.dateComponents([.day], from: start, to: actual).day else {
            throw RecurringError.invalidDate
        }
        return distance
    }

    // A due date may have a manually entered or previously parsed real movement already in
    // Activity. Suggest that row once; a schedule scan never creates another financial row.
    func suggestExistingRecurringPayments(rule: RecurringRule, day: LocalDay,
                                          transactions: [Transaction]) throws {
        let occurrenceID = RecurringSchedule.occurrenceID(ruleID: rule.id, day: day)
        guard let occurrence = try recurringOccurrences(ruleID: rule.id).first(where: { $0.id == occurrenceID }),
              occurrence.status == .expected else { return }
        let zone = try RecurringSchedule.timeZone(for: rule)
        let aliases = Set(try recurringPayeeAliases(ruleID: rule.id))
        var possible: [(transaction: Transaction, approved: Bool, distance: Int, difference: Int64)] = []
        for item in transactions where item.accountID == rule.accountID &&
            item.kind == rule.type.transactionKind && item.recurringOccurrenceID == nil {
            let distance = try localDayDistance(item.occurredAt, from: day, in: zone)
            guard abs(distance) <= rule.reviewWindowDays else { continue }
            let payee = NotificationParser.normalize(item.merchant)
            let approved = aliases.contains(payee)
            let named = payee == NotificationParser.normalize(rule.name)
            let amount = item.eurMinor ?? (item.currency == "EUR" ? item.amountMinor : 0)
            let difference = abs(amount - rule.amountMinor)
            guard approved || named || difference == 0 else { continue }
            possible.append((item, approved, distance, difference))
        }
        possible.sort { left, right in
            if left.approved != right.approved { return left.approved }
            if abs(left.distance) != abs(right.distance) {
                return abs(left.distance) < abs(right.distance)
            }
            if (left.difference == 0) != (right.difference == 0) {
                return left.difference == 0
            }
            if left.difference != right.difference { return left.difference < right.difference }
            return left.transaction.id.uuidString < right.transaction.id.uuidString
        }
        for match in possible.prefix(12) {
            let reason = match.distance != 0 ? "An existing Activity payment has a different date." :
                (match.difference != 0 ? "An existing Activity payment has a different amount." :
                 (match.approved ? "An existing Activity payment may settle this date." :
                  "An existing Activity payment has an unapproved payee."))
            _ = try saveRecurringCandidate(occurrenceID: occurrenceID,
                                           eventID: match.transaction.sourceEventID,
                                           transactionID: match.transaction.id, reason: reason)
        }
    }

    // Called inside the parser's write transaction. Only account/kind eligible occurrences enter
    // the candidate set. A future occurrence is persisted early when a payment may precede its day.
    func recurringMatchOptions(accountID: UUID?, kind: TransactionKind, amountMinor: Int64,
                               merchant: String, at date: Date, eventID: UUID) throws -> [RecurringMatchOption] {
        guard let accountID else { return [] }
        let rules = try recurringRules().filter { $0.isActive && $0.accountID == accountID &&
            $0.type.transactionKind == kind }
        let payee = NotificationParser.normalize(merchant)
        var options: [RecurringMatchOption] = []
        for rule in rules {
            let zone = try RecurringSchedule.timeZone(for: rule)
            let approved = Set(try recurringPayeeAliases(ruleID: rule.id))
            let aliasMatch = approved.contains(payee)
            let nameMatch = payee == NotificationParser.normalize(rule.name)
            guard aliasMatch || nameMatch || amountMinor == rule.amountMinor else { continue }
            for offset in 0..<3 {
                let index = rule.nextIndex + offset
                guard index < 1_000_000 else { break }
                let day = try RecurringSchedule.day(for: rule, index: index)
                if let end = rule.endDay, day > end { break }
                let distance = try localDayDistance(date, from: day, in: zone)
                if distance < -rule.reviewWindowDays { break }
                if abs(distance) <= rule.reviewWindowDays { _ = try ensureExpected(rule, day: day) }
            }
            for occurrence in try recurringOccurrences(ruleID: rule.id) {
                guard occurrence.status == .expected || occurrence.status == .legacyCounted ||
                      occurrence.status == .recordedManual else { continue }
                let distance = try localDayDistance(date, from: occurrence.scheduledDay, in: zone)
                guard abs(distance) <= rule.reviewWindowDays else { continue }
                let amountExact = amountMinor == rule.amountMinor
                guard aliasMatch || nameMatch || amountExact else { continue }
                let prior = try recurringCandidates(occurrenceID: occurrence.id)
                guard !prior.contains(where: { $0.eventID == eventID && $0.status == .rejected }) else { continue }
                let counted = occurrence.transactionID != nil
                let existing = counted ? try transactions().first(where: { $0.id == occurrence.transactionID }) : nil
                let unedited = (!counted && occurrence.reviewReason == nil &&
                    occurrence.provisionalTransactionID == nil) ||
                    (counted && existing?.revision == 1 && existing?.kind == kind &&
                    existing?.accountID == accountID && existing?.amountMinor == amountMinor &&
                    existing?.sourceEventID == nil &&
                    existing.map { LocalDay(date: $0.occurredAt, timeZone: zone) == occurrence.scheduledDay } == true)
                let strict = distance == 0 && amountExact && aliasMatch && unedited
                let reason = distance != 0 ? "Payment date differs by \(abs(distance)) day(s)." :
                    (!amountExact ? "Actual amount differs from the expected amount." :
                     (!aliasMatch ? "Payee has not been approved for automatic matching." :
                      (!unedited ? "The recorded payment was edited." : "Exact approved match.")))
                options.append(RecurringMatchOption(occurrence: occurrence, rule: rule,
                                                    reason: reason, strict: strict, counted: counted,
                                                    approvedPayee: aliasMatch, dayDistance: distance,
                                                    amountDifference: abs(amountMinor - rule.amountMinor)))
            }
        }
        return options.sorted { left, right in
            if left.approvedPayee != right.approvedPayee { return left.approvedPayee }
            if abs(left.dayDistance) != abs(right.dayDistance) {
                return abs(left.dayDistance) < abs(right.dayDistance)
            }
            if (left.amountDifference == 0) != (right.amountDifference == 0) {
                return left.amountDifference == 0
            }
            if left.amountDifference != right.amountDifference {
                return left.amountDifference < right.amountDifference
            }
            return left.occurrence.id < right.occurrence.id
        }
    }

    @discardableResult func saveRecurringCandidate(occurrenceID: String, eventID: UUID?,
                                                    transactionID: UUID?, reason: String,
                                                    status: RecurringCandidateStatus = .pending) throws -> RecurringCandidate {
        guard eventID != nil || transactionID != nil else { throw RecurringError.occurrenceChanged }
        if let old = try recurringCandidates(occurrenceID: occurrenceID).first(where: {
            eventID != nil ? $0.eventID == eventID : $0.transactionID == transactionID
        }) { return old }
        let id = UUID(), now = Date()
        let stmt = try statement("""
            INSERT INTO recurring_candidates
            (id,occurrence_id,event_id,transaction_id,status,reason,created_at,updated_at,revision)
            VALUES(?,?,?,?,?,?,?,?,1)
            """)
        defer { sqlite3_finalize(stmt) }
        bind(id.uuidString, at: 1, to: stmt)
        bind(occurrenceID, at: 2, to: stmt)
        bindOptional(eventID?.uuidString, at: 3, to: stmt)
        bindOptional(transactionID?.uuidString, at: 4, to: stmt)
        bind(status.rawValue, at: 5, to: stmt)
        bind(reason, at: 6, to: stmt)
        sqlite3_bind_double(stmt, 7, now.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 8, now.timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
        return RecurringCandidate(id: id, occurrenceID: occurrenceID, eventID: eventID,
                                  transactionID: transactionID, status: status, reason: reason,
                                  createdAt: now, updatedAt: now, revision: 1)
    }

    func confirmExpectedOccurrence(_ occurrenceID: String, transactionID: UUID,
                                   actor: String) throws {
        guard let occurrence = try recurringOccurrences().first(where: { $0.id == occurrenceID }),
              occurrence.status == .expected,
              let rule = try recurringRules(includeArchived: true).first(where: { $0.id == occurrence.ruleID }) else {
            throw RecurringError.occurrenceChanged
        }
        let stmt = try statement("""
            UPDATE recurring_occurrences_local SET status='confirmed',transaction_id=?,
                updated_at=?,revision=revision+1,review_reason=NULL
            WHERE id=? AND status='expected' AND revision=?
            """)
        bind(transactionID.uuidString, at: 1, to: stmt)
        sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
        bind(occurrenceID, at: 3, to: stmt)
        sqlite3_bind_int64(stmt, 4, occurrence.revision)
        guard sqlite3_step(stmt) == SQLITE_DONE else { sqlite3_finalize(stmt); throw error() }
        sqlite3_finalize(stmt)
        guard sqlite3_changes(handle) == 1 else { throw RecurringError.occurrenceChanged }
        try appendReconciliationAudit(occurrenceID: occurrenceID, action: "confirm", actor: actor,
                                      oldStatus: .expected, newStatus: .confirmed,
                                      oldTransactionID: nil, newTransactionID: transactionID,
                                      ruleRevision: rule.revision)
    }

    func confirmCountedOccurrence(_ occurrenceID: String, transactionID: UUID,
                                  actor: String) throws {
        guard let occurrence = try recurringOccurrences().first(where: { $0.id == occurrenceID }),
              occurrence.transactionID == transactionID,
              occurrence.status == .legacyCounted || occurrence.status == .recordedManual,
              let rule = try recurringRules(includeArchived: true).first(where: { $0.id == occurrence.ruleID }) else {
            throw RecurringError.occurrenceChanged
        }
        let stmt = try statement("""
            UPDATE recurring_occurrences_local SET status='confirmed',updated_at=?,
                revision=revision+1,review_reason=NULL
            WHERE id=? AND revision=? AND transaction_id=?
            """)
        sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
        bind(occurrenceID, at: 2, to: stmt)
        sqlite3_bind_int64(stmt, 3, occurrence.revision)
        bind(transactionID.uuidString, at: 4, to: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { sqlite3_finalize(stmt); throw error() }
        sqlite3_finalize(stmt)
        guard sqlite3_changes(handle) == 1 else { throw RecurringError.occurrenceChanged }
        try appendReconciliationAudit(occurrenceID: occurrenceID, action: "confirm-existing", actor: actor,
                                      oldStatus: occurrence.status, newStatus: .confirmed,
                                      oldTransactionID: transactionID, newTransactionID: transactionID,
                                      ruleRevision: rule.revision)
    }

    func setRecurringCandidateStatus(_ id: UUID, to status: RecurringCandidateStatus,
                                     transactionID: UUID? = nil) throws {
        let stmt = try statement("""
            UPDATE recurring_candidates SET status=?,transaction_id=COALESCE(?,transaction_id),
                updated_at=?,revision=revision+1 WHERE id=?
            """)
        bind(status.rawValue, at: 1, to: stmt)
        bindOptional(transactionID?.uuidString, at: 2, to: stmt)
        sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
        bind(id.uuidString, at: 4, to: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { sqlite3_finalize(stmt); throw error() }
        sqlite3_finalize(stmt)
        guard sqlite3_changes(handle) == 1 else { throw RecurringError.occurrenceChanged }
    }

    func rejectConfirmedCandidates(for occurrenceID: String) throws {
        let stmt = try statement("""
            UPDATE recurring_candidates SET status='rejected',revision=revision+1,updated_at=?
            WHERE occurrence_id=? AND status='confirmed'
            """)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
        bind(occurrenceID, at: 2, to: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
    }

    func setOccurrence(_ occurrence: RecurringOccurrence, status: RecurringOccurrenceStatus,
                               transactionID: UUID?, provisionalID: UUID? = nil,
                               reviewReason: String? = nil) throws {
        let stmt = try statement("""
            UPDATE recurring_occurrences_local
            SET status=?,transaction_id=?,provisional_transaction_id=COALESCE(?,provisional_transaction_id),
                updated_at=?,revision=revision+1,review_reason=?
            WHERE id=? AND revision=?
            """)
        bind(status.rawValue, at: 1, to: stmt)
        bindOptional(transactionID?.uuidString, at: 2, to: stmt)
        bindOptional(provisionalID?.uuidString, at: 3, to: stmt)
        sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
        bindOptional(reviewReason, at: 5, to: stmt)
        bind(occurrence.id, at: 6, to: stmt)
        sqlite3_bind_int64(stmt, 7, occurrence.revision)
        guard sqlite3_step(stmt) == SQLITE_DONE else { sqlite3_finalize(stmt); throw error() }
        sqlite3_finalize(stmt)
        guard sqlite3_changes(handle) == 1 else { throw RecurringError.occurrenceChanged }
    }

    func changeExpectedOccurrence(_ occurrenceID: String, to status: RecurringOccurrenceStatus) throws {
        guard status == .skipped || status == .missed else { throw RecurringError.occurrenceChanged }
        try execute("BEGIN IMMEDIATE")
        do {
            guard let occurrence = try recurringOccurrences().first(where: { $0.id == occurrenceID }),
                  occurrence.status == .expected,
                  let rule = try recurringRules(includeArchived: true).first(where: { $0.id == occurrence.ruleID }) else {
                throw RecurringError.occurrenceChanged
            }
            if status == .missed {
                let today = LocalDay(date: .now, timeZone: try RecurringSchedule.timeZone(for: rule))
                guard occurrence.scheduledDay < today else { throw RecurringError.occurrenceChanged }
            }
            try setOccurrence(occurrence, status: status, transactionID: nil)
            try appendReconciliationAudit(occurrenceID: occurrenceID, action: status.rawValue,
                                          actor: "user", oldStatus: .expected, newStatus: status,
                                          oldTransactionID: nil, newTransactionID: nil,
                                          ruleRevision: rule.revision)
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func markCountedOccurrenceMissed(_ occurrenceID: String) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            guard let occurrence = try recurringOccurrences().first(where: { $0.id == occurrenceID }),
                  occurrence.status == .legacyCounted || occurrence.status == .recordedManual,
                  let transactionID = occurrence.transactionID,
                  var provisional = try transactions().first(where: { $0.id == transactionID }),
                  provisional.sourceMovementID == nil,
                  let rule = try recurringRules(includeArchived: true).first(where: { $0.id == occurrence.ruleID }),
                  occurrence.scheduledDay < LocalDay(date: .now,
                      timeZone: try RecurringSchedule.timeZone(for: rule)) else {
                throw RecurringError.occurrenceChanged
            }
            try setOccurrence(occurrence, status: .missed, transactionID: nil,
                              provisionalID: transactionID)
            provisional.deletedAt = .now
            _ = try save(provisional, manageTransaction: false)
            try appendReconciliationAudit(occurrenceID: occurrenceID, action: "mark-counted-missed",
                                          actor: "user", oldStatus: occurrence.status,
                                          newStatus: .missed, oldTransactionID: transactionID,
                                          newTransactionID: nil, ruleRevision: rule.revision)
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func linkRecurringTransaction(_ transactionID: UUID, to occurrenceID: String,
                                  actor: String = "user",
                                  expectedOccurrenceRevision: Int64? = nil,
                                  expectedTransactionRevision: Int64? = nil) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            if let expectedOccurrenceRevision {
                guard try recurringOccurrences().first(where: { $0.id == occurrenceID })?.revision ==
                    expectedOccurrenceRevision else { throw DailyValidationError.staleRecord }
            }
            if let expectedTransactionRevision {
                guard try transactions().first(where: { $0.id == transactionID })?.revision ==
                    expectedTransactionRevision else { throw DailyValidationError.staleRecord }
            }
            try linkRecurringTransactionInTransaction(transactionID, to: occurrenceID, actor: actor)
            try checkDatabase()
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func linkRecurringTransactionInTransaction(_ transactionID: UUID, to occurrenceID: String,
                                               actor: String) throws {
        guard let occurrence = try recurringOccurrences().first(where: { $0.id == occurrenceID }),
              occurrence.status != .confirmed && occurrence.status != .cancelled,
              let rule = try recurringRules(includeArchived: true).first(where: { $0.id == occurrence.ruleID }),
              var actual = try transactions().first(where: { $0.id == transactionID }),
              !actual.isDemo, actual.accountID == rule.accountID,
              actual.kind == rule.type.transactionKind,
              actual.recurringOccurrenceID == nil || actual.recurringOccurrenceID == occurrenceID else {
            throw RecurringError.occurrenceChanged
        }
        if occurrence.transactionID == transactionID {
            try confirmCountedOccurrence(occurrenceID, transactionID: transactionID, actor: actor)
            return
        }
        if let oldID = occurrence.transactionID {
            guard var provisional = try transactions().first(where: { $0.id == oldID }),
                  provisional.sourceMovementID == nil else { throw RecurringError.occurrenceChanged }
            // The provisional row is no longer effective before a distinct real row is linked.
            try setOccurrence(occurrence, status: .expected, transactionID: nil,
                              provisionalID: oldID)
            provisional.deletedAt = .now
            _ = try save(provisional, manageTransaction: false)
        }
        actual.recurringOccurrenceID = occurrenceID
        _ = try save(actual, manageTransaction: false)
        let current = try recurringOccurrences().first(where: { $0.id == occurrenceID })!
        try setOccurrence(current, status: .confirmed, transactionID: transactionID)
        try appendReconciliationAudit(occurrenceID: occurrenceID, action: "link", actor: actor,
                                      oldStatus: occurrence.status, newStatus: .confirmed,
                                      oldTransactionID: occurrence.transactionID,
                                      newTransactionID: transactionID, ruleRevision: rule.revision)
    }

    func unlinkRecurringTransaction(_ occurrenceID: String,
                                    expectedOccurrenceRevision: Int64? = nil,
                                    expectedTransactionRevision: Int64? = nil) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            guard let occurrence = try recurringOccurrences().first(where: { $0.id == occurrenceID }),
                  occurrence.status == .confirmed, let id = occurrence.transactionID,
                  var actual = try transactions().first(where: { $0.id == id }),
                  let rule = try recurringRules(includeArchived: true).first(where: { $0.id == occurrence.ruleID }) else {
                throw RecurringError.occurrenceChanged
            }
            if let expectedOccurrenceRevision, occurrence.revision != expectedOccurrenceRevision {
                throw DailyValidationError.staleRecord
            }
            if let expectedTransactionRevision, actual.revision != expectedTransactionRevision {
                throw DailyValidationError.staleRecord
            }
            actual.recurringOccurrenceID = nil
            _ = try save(actual, manageTransaction: false)
            try setOccurrence(occurrence, status: .expected, transactionID: nil,
                              reviewReason: "Payment was unlinked; choose a transaction or record it manually.")
            try rejectConfirmedCandidates(for: occurrenceID)
            try appendReconciliationAudit(occurrenceID: occurrenceID, action: "unlink", actor: "user",
                                          oldStatus: .confirmed, newStatus: .expected,
                                          oldTransactionID: id, newTransactionID: nil,
                                          ruleRevision: rule.revision)
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func rejectRecurringCandidate(_ candidateID: UUID) throws -> UUID? {
        try execute("BEGIN IMMEDIATE")
        do {
            guard let candidate = try recurringCandidates().first(where: { $0.id == candidateID }),
                  candidate.status == .pending,
                  let occurrence = try recurringOccurrences().first(where: { $0.id == candidate.occurrenceID }),
                  let rule = try recurringRules(includeArchived: true).first(where: { $0.id == occurrence.ruleID }) else {
                throw RecurringError.occurrenceChanged
            }
            try setRecurringCandidateStatus(candidateID, to: .rejected)
            try appendReconciliationAudit(occurrenceID: occurrence.id, action: "reject", actor: "user",
                                          oldStatus: occurrence.status, newStatus: occurrence.status,
                                          oldTransactionID: occurrence.transactionID,
                                          newTransactionID: occurrence.transactionID,
                                          ruleRevision: rule.revision)
            try execute("COMMIT")
            return candidate.eventID
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func confirmRecurringCandidate(_ candidateID: UUID,
                                   expectedCandidateRevision: Int64? = nil,
                                   expectedOccurrenceRevision: Int64? = nil,
                                   expectedRuleRevision: Int64? = nil,
                                   expectedTransactionRevision: Int64? = nil) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            guard let candidate = try recurringCandidates().first(where: { $0.id == candidateID }),
                  candidate.status == .pending else {
                throw RecurringError.occurrenceChanged
            }
            if let expectedCandidateRevision, candidate.revision != expectedCandidateRevision {
                throw DailyValidationError.staleRecord
            }
            guard let occurrence = try recurringOccurrences().first(where: { $0.id == candidate.occurrenceID }),
                  let rule = try recurringRules(includeArchived: true).first(where: { $0.id == occurrence.ruleID }) else {
                throw RecurringError.occurrenceChanged
            }
            if let expectedOccurrenceRevision, occurrence.revision != expectedOccurrenceRevision {
                throw DailyValidationError.staleRecord
            }
            if let expectedRuleRevision, rule.revision != expectedRuleRevision {
                throw DailyValidationError.staleRecord
            }
            let transactionID: UUID
            if let existing = candidate.transactionID {
                transactionID = existing
                if let expectedTransactionRevision {
                    guard try transactions().first(where: { $0.id == existing })?.revision ==
                        expectedTransactionRevision else { throw DailyValidationError.staleRecord }
                }
                try linkRecurringTransactionInTransaction(transactionID, to: candidate.occurrenceID,
                                                          actor: "user")
            } else {
                transactionID = try confirmHeldRecurringNotification(candidate)
            }
            try setRecurringCandidateStatus(candidateID, to: .confirmed,
                                            transactionID: transactionID)
            let competing = try recurringCandidates().filter { $0.id != candidateID && $0.status == .pending &&
                ($0.transactionID == transactionID || ($0.eventID != nil && $0.eventID == candidate.eventID)) }
            for other in competing { try setRecurringCandidateStatus(other.id, to: .rejected) }
            try checkDatabase()
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    @discardableResult func separateRecurringEvent(_ eventID: UUID) throws -> ParserAttempt? {
        try execute("BEGIN IMMEDIATE")
        do {
            let pending = try recurringCandidates().filter { $0.eventID == eventID && $0.status == .pending }
            guard !pending.isEmpty else { throw RecurringError.occurrenceChanged }
            for candidate in pending {
                try setRecurringCandidateStatus(candidate.id, to: .rejected)
                if let occurrence = try recurringOccurrences().first(where: { $0.id == candidate.occurrenceID }),
                   let rule = try recurringRules(includeArchived: true).first(where: { $0.id == occurrence.ruleID }) {
                    try appendReconciliationAudit(occurrenceID: occurrence.id, action: "separate", actor: "user",
                                                  oldStatus: occurrence.status, newStatus: occurrence.status,
                                                  oldTransactionID: occurrence.transactionID,
                                                  newTransactionID: occurrence.transactionID,
                                                  ruleRevision: rule.revision)
                }
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
        guard let attempt = try parserAttempts().first(where: { $0.event.id == eventID && $0.status == .recurringReview && $0.transactionID == nil }) else {
            return nil // A separate actual transaction was already saved; its total does not change.
        }
        return try processNotificationAttempt(attempt.id)
    }
}
