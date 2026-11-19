import SQLite3
import XCTest
@testable import EasyTrackCore

final class RecurringReconciliationTests: XCTestCase {
    private let zone = TimeZone(identifier: "Europe/Rome")!

    private func withDatabase(_ body: (SQLiteDatabase, URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-reconciliation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("fictional.sqlite")
        try body(SQLiteDatabase(url: url), url)
    }

    private func date(_ day: String) -> Date { LocalDay(isoString: day)!.noon(in: zone)! }

    private func account(_ db: SQLiteDatabase, name: String = "Fictional checking") throws -> LocalAccount {
        try db.saveLocalAccount(LocalAccount(id: UUID(), name: name, createdAt: .now))
    }

    private func rule(_ db: SQLiteDatabase, account: LocalAccount, name: String = "Fictional Plan",
                      amount: Int64 = 1_250, start: String = "2026-10-15",
                      kind: RecurringType = .subscription) throws -> RecurringRule {
        try db.saveRecurringRule(RecurringRule(id: UUID(), name: name, type: kind,
            amountMinor: amount, accountID: account.id, categoryID: nil,
            startDay: LocalDay(isoString: start)!, frequency: .monthly, nextIndex: 0,
            endDay: nil, timeZoneIdentifier: zone.identifier, isActive: true,
            note: "Synthetic rule", createdAt: .now, updatedAt: .now,
            archivedAt: nil, revision: 0))
    }

    private func event(_ amount: String = "12,50", merchant: String = "Fictional Plan",
                       day: String = "2026-10-15") -> NotificationEvent {
        let instant = date(day)
        return NotificationEvent.make(sourceApp: "Northstar Pay (fictional)",
            title: "Card purchase", subtitle: "", message: "Paid €\(amount) at \(merchant)",
            receivedAt: instant, capturedAt: instant)!
    }

    private func parser(_ db: SQLiteDatabase, account: LocalAccount,
                        sample: NotificationEvent, kind: TransactionKind = .expense) throws -> UUID {
        let captured = try db.captureNotification(sample)
        XCTAssertEqual(captured.status, .setupRequired)
        let source = try XCTUnwrap(db.parserSources().first)
        _ = try db.mapParserSource(source.id, to: account.name)
        var config = NotificationParser.suggest(for: sample)
        config.kind = kind
        let rule = ParserRule(id: UUID(), sourceID: source.id, name: "Fictional card format",
                              enabled: true, priority: 1, version: 0, config: config,
                              createdAt: .now, updatedAt: .now, deletedAt: nil)
        _ = try db.saveParserRule(rule)
        XCTAssertEqual(NotificationParser.preview(sample, config: config,
            mappedAccount: account.name).merchant, "Fictional Plan")
        return captured.id
    }

    private func oldCounted(_ db: SQLiteDatabase, account: LocalAccount,
                            name: String = "Fictional Plan", start: String = "2026-10-15") throws -> (RecurringRule, Transaction, RecurringOccurrence) {
        let recurring = try rule(db, account: account, name: name, start: start)
        let transaction = try db.createNextRecurringNow(recurring.id, now: date(start))
        let occurrence = try XCTUnwrap(db.recurringOccurrences(ruleID: recurring.id).first)
        try db.execute("UPDATE recurring_occurrences_local SET status='legacy_counted' WHERE id='\(occurrence.id)'")
        return (recurring, transaction, try XCTUnwrap(db.recurringOccurrences(ruleID: recurring.id).first))
    }

    private func imported(_ sourceID: String, day: String, merchant: String,
                          row: Int, amount: Int64 = 1_250) -> ImportedMovement {
        var transaction = Transaction(id: UUID(), kind: .expense, amountMinor: amount,
            currency: "EUR", merchant: merchant, account: "Unverified historical label",
            category: "", note: "Historical fictional note", occurredAt: date(day),
            updatedAt: .now, deletedAt: nil, isDemo: false, revision: 0,
            sourceEventID: nil)
        transaction.eurMinor = amount
        transaction.personalExpenseEURMinor = amount
        transaction.sourceMovementID = sourceID
        transaction.sourceSheet = "Fictional movements"
        transaction.sourceRow = row
        transaction.sourceOccurredAt = day
        return ImportedMovement(transaction: transaction,
                                sourceFingerprint: "fingerprint-\(sourceID)",
                                sourcePayloadJSON: "{}")
    }

    private func seed(_ movements: [ImportedMovement]) -> ValidatedSeed {
        ValidatedSeed(schemaVersion: 1, digest: "fictional-bulk-digest",
                      movements: movements, accounts: [], trips: [], rules: [], rates: [],
                      sourceRows: [], warnings: [], reimbursements: [], unmatchedAccountLabels: 0,
                      missingAccountLabels: 0)
    }

    private func writeFixtureIfRequested(_ db: SQLiteDatabase, key: String) throws {
        guard let path = ProcessInfo.processInfo.environment[key] else { return }
        guard !FileManager.default.fileExists(atPath: path) else {
            throw NSError(domain: "Fictional UI fixture already exists", code: 1)
        }
        var destination: OpaquePointer?
        guard sqlite3_open_v2(path, &destination,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                              nil) == SQLITE_OK else {
            sqlite3_close(destination)
            throw NSError(domain: "Fictional UI fixture could not be opened", code: 2)
        }
        defer { sqlite3_close(destination) }
        guard let backup = sqlite3_backup_init(destination, "main", db.handle, "main") else {
            throw NSError(domain: "Fictional UI fixture backup could not start", code: 3)
        }
        let stepped = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard stepped == SQLITE_DONE, finished == SQLITE_OK else {
            throw NSError(domain: "Fictional UI fixture backup could not finish", code: 4)
        }
    }

    func testExpectedDatesNeverChangeTotalsAndManualActionsAreIdempotent() throws {
        try withDatabase { db, url in
            let wallet = try account(db)
            var recurring = try rule(db, account: wallet, start: "2026-01-31")
            XCTAssertEqual(try db.materializeDueRecurring(now: date("2026-03-01")), 2)
            XCTAssertEqual(try db.materializeDueRecurring(now: date("2026-03-01")), 0)
            let expected = try db.recurringOccurrences(ruleID: recurring.id)
            XCTAssertEqual(expected.map(\.scheduledDay.isoString).sorted(), ["2026-01-31", "2026-02-28"])
            XCTAssertTrue(expected.allSatisfy { $0.status == .expected && $0.transactionID == nil })
            XCTAssertEqual(LedgerTotals(transactions: try db.transactions()).totalExpensesEURMinor, 0)
            if ProcessInfo.processInfo.environment["EASYTRACK_RECONCILIATION_MANUAL_UI_FIXTURE_PATH"] != nil {
                recurring = try XCTUnwrap(db.recurringRules().first { $0.id == recurring.id })
                recurring.endDay = LocalDay(isoString: "2026-02-28")!
                recurring = try db.saveRecurringRule(recurring)
                var actual = Transaction(id: UUID(), kind: .expense, amountMinor: 1_375,
                    currency: "EUR", merchant: "Fictional Manual Charge", account: wallet.name,
                    category: "", note: "Fictional manual link", occurredAt: date("2026-01-31"),
                    updatedAt: .now, deletedAt: nil, isDemo: false, revision: 0,
                    sourceEventID: nil)
                actual.accountID = wallet.id
                actual.eurMinor = 1_375
                actual.personalExpenseEURMinor = 1_375
                actual = try db.save(actual)
                try writeFixtureIfRequested(db, key: "EASYTRACK_RECONCILIATION_MANUAL_UI_FIXTURE_PATH")
                actual.deletedAt = .now
                _ = try db.save(actual)
            }
            let recorded = try db.recordExpectedRecurringNow(expected[0].id, now: date("2026-03-02"))
            XCTAssertEqual(try db.transactions().count, 1)
            XCTAssertEqual(try db.recurringOccurrences().first { $0.id == expected[0].id }?.status, .recordedManual)
            XCTAssertThrowsError(try db.recordExpectedRecurringNow(expected[0].id))
            try db.changeExpectedOccurrence(expected[1].id, to: .missed)
            XCTAssertThrowsError(try db.changeExpectedOccurrence(expected[1].id, to: .missed))
            let reopened = try SQLiteDatabase(url: url)
            XCTAssertEqual(try reopened.transactions().first?.id, recorded.id)
            XCTAssertEqual(try reopened.materializeDueRecurring(now: date("2026-03-01")), 0)
            XCTAssertEqual(try reopened.recurringOccurrences().count, 2)
            try reopened.checkDatabase()
        }
    }

    func testExplicitMissedCorrectionSoftDeletesManualPaymentWithoutResurrection() throws {
        try withDatabase { db, _ in
            let account = try account(db)
            let recurring = try rule(db, account: account, start: "2026-01-15")
            let recorded = try db.createNextRecurringNow(recurring.id, now: date("2026-01-15"))
            let occurrence = try XCTUnwrap(db.recurringOccurrences().first)
            XCTAssertEqual(occurrence.status, .recordedManual)
            XCTAssertEqual(try db.transactions().count, 1)
            try db.markCountedOccurrenceMissed(occurrence.id)
            XCTAssertTrue(try db.transactions().isEmpty)
            XCTAssertNotNil(try db.transactions(includeDeleted: true).first { $0.id == recorded.id }?.deletedAt)
            XCTAssertEqual(try db.recurringOccurrences().first?.status, .missed)
            XCTAssertEqual(try db.recurringOccurrences().first?.provisionalTransactionID, recorded.id)
            XCTAssertThrowsError(try db.markCountedOccurrenceMissed(occurrence.id))
            XCTAssertEqual(LedgerTotals(transactions: try db.transactions()).totalExpensesEURMinor, 0)
            try db.checkDatabase()
        }
    }

    func testExactApprovedNotificationConfirmsExpectedOnceAndReplayIsIgnored() throws {
        try withDatabase { db, url in
            let account = try account(db)
            let recurring = try rule(db, account: account)
            let sample = event()
            let attemptID = try parser(db, account: account, sample: sample)
            try db.approveRecurringPayee("Fictional Plan", for: recurring.id)
            XCTAssertEqual(try db.materializeDueRecurring(now: date("2026-10-15")), 1)
            let matched = try db.processNotificationAttempt(attemptID)
            XCTAssertEqual(matched.status, .created)
            XCTAssertEqual(try db.transactions().count, 1)
            let occurrence = try XCTUnwrap(db.recurringOccurrences(ruleID: recurring.id).first)
            XCTAssertEqual(occurrence.status, .confirmed)
            XCTAssertEqual(occurrence.transactionID, matched.transactionID)
            XCTAssertEqual(try db.recurringCandidates().first?.status, .confirmed)
            try writeFixtureIfRequested(db, key: "EASYTRACK_RECONCILIATION_EXACT_UI_FIXTURE_PATH")
            XCTAssertEqual(try db.captureNotification(sample).status, .duplicateIgnored)
            let reopened = try SQLiteDatabase(url: url)
            XCTAssertEqual(try reopened.transactions().count, 1)
            XCTAssertEqual(try reopened.materializeDueRecurring(now: date("2026-10-16")), 0)
            try reopened.checkDatabase()
        }
    }

    func testUnapprovedPayeeNeedsReviewAndLinkKeepsActualAmount() throws {
        try withDatabase { db, _ in
            let account = try account(db)
            let recurring = try rule(db, account: account)
            let sample = event("14,75")
            let attemptID = try parser(db, account: account, sample: sample)
            _ = try db.materializeDueRecurring(now: date("2026-10-15"))
            let reviewed = try db.processNotificationAttempt(attemptID)
            XCTAssertEqual(reviewed.status, .recurringReview)
            XCTAssertEqual(try db.transactions().count, 1)
            let candidate = try XCTUnwrap(db.recurringCandidates().first)
            XCTAssertEqual(candidate.status, .pending)
            let before = LedgerTotals(transactions: try db.transactions())
            try db.confirmRecurringCandidate(candidate.id)
            XCTAssertEqual(try db.recurringOccurrences(ruleID: recurring.id).first?.status, .confirmed)
            XCTAssertEqual(LedgerTotals(transactions: try db.transactions()), before)
            XCTAssertEqual(try db.transactions().first?.amountMinor, 1_475)
            try db.unlinkRecurringTransaction(candidate.occurrenceID)
            XCTAssertEqual(try db.recurringOccurrences().first?.status, .expected)
            XCTAssertEqual(try db.transactions().count, 1)
            XCTAssertEqual(LedgerTotals(transactions: try db.transactions()), before)
            try db.checkDatabase()
        }
    }

    func testLegacyCountedNotificationIsHeldThenCorrectedWithoutSecondMovement() throws {
        try withDatabase { db, _ in
            let account = try account(db)
            let (recurring, old, occurrence) = try oldCounted(db, account: account)
            let sample = event("14,75")
            let attemptID = try parser(db, account: account, sample: sample)
            try db.approveRecurringPayee("Fictional Plan", for: recurring.id)
            let reviewed = try db.processNotificationAttempt(attemptID)
            XCTAssertEqual(reviewed.status, .recurringReview)
            XCTAssertNil(reviewed.transactionID)
            XCTAssertEqual(try db.transactions().count, 1)
            XCTAssertEqual(try db.transactions().first?.id, old.id)
            try writeFixtureIfRequested(db, key: "EASYTRACK_RECONCILIATION_UI_FIXTURE_PATH")
            let candidate = try XCTUnwrap(db.recurringCandidates(occurrenceID: occurrence.id).first)
            try db.confirmRecurringCandidate(candidate.id)
            XCTAssertEqual(try db.transactions().count, 1)
            XCTAssertEqual(try db.transactions().first?.amountMinor, 1_475)
            XCTAssertEqual(try db.transactions().first?.id, old.id)
            XCTAssertEqual(try db.recurringOccurrences().first?.status, .confirmed)
            XCTAssertEqual(try db.parserAttempts().first { $0.id == attemptID }?.status, .matchedExisting)
            XCTAssertEqual(try db.captureNotification(sample).status, .duplicateIgnored)
            try db.checkDatabase()
        }
    }

    func testExactApprovedLegacyNotificationKeepsUUIDAndUsesCapturedTime() throws {
        try withDatabase { db, _ in
            let account = try account(db)
            let (recurring, old, _) = try oldCounted(db, account: account)
            let received = date("2026-10-15").addingTimeInterval(3_600)
            let sample = NotificationEvent.make(sourceApp: "Northstar Pay (fictional)",
                title: "Card purchase", subtitle: "",
                message: "Paid €12,50 at Fictional Plan",
                receivedAt: received, capturedAt: received)!
            let attemptID = try parser(db, account: account, sample: sample)
            try db.approveRecurringPayee("Fictional Plan", for: recurring.id)
            let result = try db.processNotificationAttempt(attemptID)
            XCTAssertEqual(result.status, .matchedExisting)
            XCTAssertEqual(result.transactionID, old.id)
            let active = try db.transactions()
            XCTAssertEqual(active.count, 1)
            XCTAssertEqual(active.first?.id, old.id)
            XCTAssertEqual(active.first?.occurredAt, received)
            XCTAssertEqual(active.first?.sourceEventID, sample.id)
            XCTAssertEqual(try db.recurringOccurrences().first?.status, .confirmed)
            try db.checkDatabase()
        }
    }

    func testRejectedLegacyMatchCreatesSeparatePaymentOnlyAfterUserChoice() throws {
        try withDatabase { db, _ in
            let account = try account(db)
            let (_, old, _) = try oldCounted(db, account: account)
            let sample = event()
            let attemptID = try parser(db, account: account, sample: sample)
            XCTAssertEqual(try db.processNotificationAttempt(attemptID).status, .recurringReview)
            XCTAssertEqual(try db.transactions().count, 1)
            try writeFixtureIfRequested(db, key: "EASYTRACK_RECONCILIATION_SEPARATE_UI_FIXTURE_PATH")
            _ = try db.separateRecurringEvent(sample.id)
            XCTAssertEqual(try db.transactions().count, 2)
            XCTAssertEqual(try db.recurringCandidates().first?.status, .rejected)
            XCTAssertEqual(try db.recurringOccurrences().first?.transactionID, old.id)
            XCTAssertEqual(try db.captureNotification(sample).status, .duplicateIgnored)
            try db.checkDatabase()
        }
    }

    func testDifferentAccountAndKindCannotAutoMatch() throws {
        try withDatabase { db, _ in
            let first = try account(db)
            let second = try account(db, name: "Fictional savings")
            let recurring = try rule(db, account: first)
            try db.approveRecurringPayee("Fictional Plan", for: recurring.id)
            let sample = event()
            let attemptID = try parser(db, account: second, sample: sample)
            _ = try db.materializeDueRecurring(now: date("2026-10-15"))
            XCTAssertEqual(try db.processNotificationAttempt(attemptID).status, .created)
            XCTAssertEqual(try db.recurringCandidates().count, 0)
            XCTAssertEqual(try db.recurringOccurrences().first?.status, .expected)
            XCTAssertEqual(try db.transactions().count, 1)
            try db.checkDatabase()
        }
    }

    func testSchemaFiveMigrationPreservesEditedActiveAndDeletedLegacyRows() throws {
        try withDatabase { db, url in
            let account = try account(db)
            let recurring = try rule(db, account: account, start: "2026-01-15")
            var first = try db.createNextRecurringNow(recurring.id, now: date("2026-01-15"))
            let second = try db.createNextRecurringNow(recurring.id, now: date("2026-02-15"))
            try db.skipNextRecurring(recurring.id)
            first.note = "Edited fictional note"
            first.amountMinor = 1_375
            first.eurMinor = 1_375
            first.personalExpenseEURMinor = 1_375
            _ = try db.save(first)
            var deleted = second
            deleted.deletedAt = date("2026-02-16")
            _ = try db.save(deleted)
            let beforeTotals = LedgerTotals(transactions: try db.transactions())
            let beforeIDs = Set(try db.transactions(includeDeleted: true).map(\.id))
            let beforeOccurrences = Set(try db.recurringOccurrences().map(\.id))
            let beforeOperations = try db.operations().count
            try db.execute("PRAGMA foreign_keys=OFF")
            try db.execute("DROP TABLE recurring_reconciliation_audit")
            try db.execute("DROP TABLE recurring_payee_aliases")
            try db.execute("DROP TABLE recurring_candidates")
            try db.execute("""
                CREATE TABLE recurring_occurrences_v5 (
                    id TEXT PRIMARY KEY,rule_id TEXT NOT NULL,scheduled_day TEXT NOT NULL,
                    status TEXT NOT NULL CHECK(status IN ('materialized','skipped')),
                    transaction_id TEXT UNIQUE,created_at REAL NOT NULL,
                    UNIQUE(rule_id,scheduled_day),
                    FOREIGN KEY(rule_id) REFERENCES recurring_rules_local(id),
                    FOREIGN KEY(transaction_id) REFERENCES transactions(id),
                    CHECK((status='materialized')=(transaction_id IS NOT NULL))
                )
                """)
            try db.execute("""
                INSERT INTO recurring_occurrences_v5
                SELECT id,rule_id,scheduled_day,
                    CASE WHEN status='skipped' THEN 'skipped' ELSE 'materialized' END,
                    COALESCE(transaction_id,provisional_transaction_id),created_at
                FROM recurring_occurrences_local
                """)
            try db.execute("DROP TABLE recurring_occurrences_local")
            try db.execute("ALTER TABLE recurring_occurrences_v5 RENAME TO recurring_occurrences_local")
            try db.execute("ALTER TABLE recurring_rules_local DROP COLUMN review_window_days")
            try db.execute("DROP INDEX unique_transaction_recurring_occurrence")
            try db.execute("CREATE UNIQUE INDEX unique_transaction_recurring_occurrence ON transactions(recurring_occurrence_id) WHERE recurring_occurrence_id IS NOT NULL")
            try db.execute("PRAGMA user_version=5")
            let migrated = try SQLiteDatabase(url: url)
            XCTAssertEqual(Set(try migrated.transactions(includeDeleted: true).map(\.id)), beforeIDs)
            XCTAssertEqual(Set(try migrated.recurringOccurrences().map(\.id)), beforeOccurrences)
            XCTAssertEqual(try migrated.operations().count, beforeOperations)
            XCTAssertEqual(LedgerTotals(transactions: try migrated.transactions()), beforeTotals)
            XCTAssertEqual(try migrated.transactions(includeDeleted: true).first { $0.id == first.id }?.note,
                           "Edited fictional note")
            XCTAssertNotNil(try migrated.transactions(includeDeleted: true).first { $0.id == second.id }?.deletedAt)
            let rows = try migrated.recurringOccurrences()
            XCTAssertEqual(rows.first { $0.transactionID == first.id }?.status, .legacyCounted)
            XCTAssertEqual(rows.first { $0.provisionalTransactionID == second.id }?.status, .expected)
            XCTAssertNotNil(rows.first { $0.provisionalTransactionID == second.id }?.reviewReason)
            XCTAssertEqual(rows.filter { $0.status == .skipped }.count, 1)
            try migrated.checkDatabase()
        }
    }

    func testCollectiveImportBlocksUntilEveryConflictIsResolvedAndPreservesProvenance() throws {
        try withDatabase { db, _ in
            let account = try account(db)
            let first = try oldCounted(db, account: account, name: "Fictional Plan", start: "2026-10-15")
            let second = try oldCounted(db, account: account, name: "Fictional Other", start: "2026-11-15")
            let a = imported("fictional-import-a", day: "2026-10-15", merchant: "Fictional Plan", row: 2)
            let b = imported("fictional-import-b", day: "2026-11-15", merchant: "Fictional Other", row: 3)
            let historical = seed([a, b])
            let beforeTotals = LedgerTotals(transactions: try db.transactions())
            let beforeIDs = Set(try db.transactions().map(\.id))
            let preview = try db.historicalImportPreview(historical)
            XCTAssertEqual(preview.recurringConflicts.count, 2)
            XCTAssertEqual(Set(try db.transactions().map(\.id)), beforeIDs) // preview and cancellation are read-only
            XCTAssertThrowsError(try db.importHistoricalSeed(historical))
            XCTAssertEqual(Set(try db.transactions().map(\.id)), beforeIDs)
            var decisions = [String: HistoricalImportDecision]()
            decisions[preview.recurringConflicts[0].id] = .samePayment
            XCTAssertThrowsError(try db.importHistoricalSeed(historical, decisions: decisions))
            XCTAssertEqual(Set(try db.transactions().map(\.id)), beforeIDs)
            decisions[preview.recurringConflicts[1].id] = .samePayment
            _ = try db.importHistoricalSeed(historical, decisions: decisions)
            let active = try db.transactions()
            XCTAssertEqual(Set(active.map(\.id)), Set([a.transaction.id, b.transaction.id]))
            XCTAssertEqual(LedgerTotals(transactions: active), beforeTotals)
            XCTAssertEqual(Set(try db.transactions(includeDeleted: true).map(\.id)),
                           Set([first.1.id, second.1.id, a.transaction.id, b.transaction.id]))
            XCTAssertEqual(active.first { $0.id == a.transaction.id }?.sourceMovementID,
                           "fictional-import-a")
            XCTAssertEqual(active.first { $0.id == a.transaction.id }?.account,
                           "Unverified historical label")
            XCTAssertEqual(active.first { $0.id == a.transaction.id }?.accountID, account.id)
            XCTAssertTrue(try db.recurringOccurrences().allSatisfy { $0.status == .confirmed })
            XCTAssertEqual(try db.historicalImportPreview(historical).newMovements, 0)
            _ = try db.importHistoricalSeed(historical)
            XCTAssertEqual(try db.transactions().count, 2)
            try db.checkDatabase()
        }
    }

    func testManyToOneImportRequiresOnePreciseSamePaymentChoice() throws {
        try withDatabase { db, _ in
            let account = try account(db)
            _ = try oldCounted(db, account: account, name: "Fictional Plan", start: "2026-10-15")
            _ = try oldCounted(db, account: account, name: "Fictional Plan", start: "2026-10-15")
            let movement = imported("fictional-shared", day: "2026-10-15",
                                    merchant: "Fictional Plan", row: 2)
            let historical = seed([movement])
            let conflicts = try db.historicalImportPreview(historical).recurringConflicts
            XCTAssertEqual(conflicts.count, 2)
            XCTAssertThrowsError(try db.importHistoricalSeed(historical,
                decisions: Dictionary(uniqueKeysWithValues: conflicts.map { ($0.id, .samePayment) })))
            XCTAssertEqual(try db.transactions().count, 2)
            _ = try db.importHistoricalSeed(historical, decisions: [
                conflicts[0].id: .samePayment, conflicts[1].id: .separatePayment
            ])
            XCTAssertEqual(try db.transactions().count, 2)
            XCTAssertEqual(try db.recurringOccurrences().filter { $0.status == .confirmed }.count, 1)
            try db.checkDatabase()
        }
    }

    func testImportFailureRollsBackAllFinancialAndProvenanceWrites() throws {
        try withDatabase { db, _ in
            let account = try account(db)
            let (_, original, _) = try oldCounted(db, account: account)
            let historical = seed([imported("fictional-failure", day: "2026-10-15",
                                            merchant: "Fictional Plan", row: 2)])
            let conflict = try XCTUnwrap(db.historicalImportPreview(historical).recurringConflicts.first)
            let beforeOperations = try db.operations().count
            try db.execute("CREATE TRIGGER fictional_import_failure BEFORE INSERT ON historical_imported_movements BEGIN SELECT RAISE(ABORT, 'synthetic import failure'); END")
            XCTAssertThrowsError(try db.importHistoricalSeed(historical,
                decisions: [conflict.id: .samePayment]))
            XCTAssertEqual(try db.transactions().map(\.id), [original.id])
            XCTAssertEqual(try db.operations().count, beforeOperations)
            XCTAssertEqual(try db.historicalCounts()["historical_imported_movements"], 0)
            XCTAssertEqual(try db.recurringOccurrences().first?.status, .legacyCounted)
            try db.execute("DROP TRIGGER fictional_import_failure")
            try db.checkDatabase()
        }
    }

    func testCurrentFormatRoundTripPreservesPendingCandidateAliasAndAudit() throws {
        try withDatabase { source, _ in
            try source.execute("INSERT INTO metadata(key,value) VALUES('demo_seeded','1')")
            let account = try account(source)
            let (recurring, _, _) = try oldCounted(source, account: account)
            let sample = event("14,75")
            let attemptID = try parser(source, account: account, sample: sample)
            try source.approveRecurringPayee("Fictional Plan", for: recurring.id)
            XCTAssertEqual(try source.processNotificationAttempt(attemptID).status, .recurringReview)
            let original = try source.exportBackup()
            XCTAssertEqual(original.schemaVersion, 15)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-round-trip-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let targetURL = folder.appendingPathComponent("restored.sqlite")
            let target = try SQLiteDatabase(url: targetURL)
            let decoded = try BackupArchive.decode(JSONEncoder().encode(original))
            _ = try target.restoreBackup(decoded, preview: target.previewBackup(decoded), mode: .replace)
            let reopened = try SQLiteDatabase(url: targetURL)
            XCTAssertEqual(try reopened.exportBackup().tables, original.tables)
            XCTAssertEqual(try reopened.recurringCandidates().first?.status, .pending)
            XCTAssertEqual(try reopened.recurringPayeeAliases(ruleID: recurring.id), ["fictional plan"])
            try reopened.confirmRecurringCandidate(XCTUnwrap(reopened.recurringCandidates().first?.id))
            XCTAssertEqual(try reopened.transactions().count, 1)
            try reopened.checkDatabase()
        }
    }

    func testEarlyNotificationCreatesReviewOnlyAndDueCatchUpDoesNotDuplicate() throws {
        try withDatabase { db, url in
            let account = try account(db)
            let recurring = try rule(db, account: account)
            try db.approveRecurringPayee("Fictional Plan", for: recurring.id)
            let sample = event(day: "2026-10-14")
            let attemptID = try parser(db, account: account, sample: sample)
            XCTAssertEqual(try db.processNotificationAttempt(attemptID).status, .recurringReview)
            XCTAssertEqual(try db.transactions().count, 1)
            XCTAssertEqual(try db.recurringOccurrences(ruleID: recurring.id).first?.status, .expected)
            XCTAssertEqual(try db.materializeDueRecurring(now: date("2026-10-15")), 0)
            XCTAssertEqual(try db.recurringRules().first?.nextIndex, 1)
            let candidate = try XCTUnwrap(db.recurringCandidates().first)
            try db.confirmRecurringCandidate(candidate.id)
            let reopened = try SQLiteDatabase(url: url)
            XCTAssertEqual(try reopened.transactions().count, 1)
            XCTAssertEqual(try reopened.recurringOccurrences().first?.status, .confirmed)
            try reopened.checkDatabase()
        }
    }

    func testDueDateSuggestsAnExistingActivityPaymentWithoutAddingMovement() throws {
        try withDatabase { db, _ in
            let account = try account(db)
            let recurring = try rule(db, account: account)
            var actual = Transaction(id: UUID(), kind: .expense, amountMinor: 1_375,
                currency: "EUR", merchant: "Fictional Plan", account: account.name,
                category: "", note: "Existing fictional payment",
                occurredAt: date("2026-10-14"), updatedAt: .now,
                deletedAt: nil, isDemo: false, revision: 0, sourceEventID: nil)
            actual.accountID = account.id
            actual.eurMinor = 1_375
            actual.personalExpenseEURMinor = 1_375
            _ = try db.save(actual)
            let before = LedgerTotals(transactions: try db.transactions())
            XCTAssertEqual(try db.materializeDueRecurring(now: date("2026-10-15")), 1)
            let occurrence = try XCTUnwrap(db.recurringOccurrences(ruleID: recurring.id).first)
            XCTAssertEqual(occurrence.status, .expected)
            let candidate = try XCTUnwrap(db.recurringCandidates(occurrenceID: occurrence.id).first)
            XCTAssertEqual(candidate.transactionID, actual.id)
            XCTAssertEqual(candidate.status, .pending)
            XCTAssertEqual(try db.transactions().count, 1)
            XCTAssertEqual(LedgerTotals(transactions: try db.transactions()), before)
            XCTAssertEqual(try db.materializeDueRecurring(now: date("2026-10-15")), 0)
            XCTAssertEqual(try db.recurringCandidates(occurrenceID: occurrence.id).count, 1)
            try db.confirmRecurringCandidate(candidate.id)
            XCTAssertEqual(try db.recurringOccurrences().first?.transactionID, actual.id)
            XCTAssertEqual(LedgerTotals(transactions: try db.transactions()), before)
            try db.checkDatabase()
        }
    }

    func testStaleCandidateRuleAndTransactionPreviewCannotConfirm() throws {
        try withDatabase { db, _ in
            let account = try account(db)
            let recurring = try rule(db, account: account)
            let sample = event("14,75")
            let attemptID = try parser(db, account: account, sample: sample)
            _ = try db.materializeDueRecurring(now: date("2026-10-15"))
            XCTAssertEqual(try db.processNotificationAttempt(attemptID).status, .recurringReview)
            let originalCandidate = try XCTUnwrap(db.recurringCandidates().first)
            let occurrence = try XCTUnwrap(db.recurringOccurrences().first)
            let actualID = try XCTUnwrap(originalCandidate.transactionID)
            var actual = try XCTUnwrap(db.transactions().first { $0.id == actualID })
            try db.setRecurringCandidateStatus(originalCandidate.id, to: .pending)
            XCTAssertThrowsError(try db.confirmRecurringCandidate(originalCandidate.id,
                expectedCandidateRevision: originalCandidate.revision,
                expectedOccurrenceRevision: occurrence.revision,
                expectedRuleRevision: recurring.revision,
                expectedTransactionRevision: actual.revision))
            let currentCandidate = try XCTUnwrap(db.recurringCandidates().first)
            let oldTransactionRevision = actual.revision
            actual.note = "Edited after preview"
            actual = try db.save(actual)
            XCTAssertThrowsError(try db.confirmRecurringCandidate(currentCandidate.id,
                expectedCandidateRevision: currentCandidate.revision,
                expectedOccurrenceRevision: occurrence.revision,
                expectedRuleRevision: recurring.revision,
                expectedTransactionRevision: oldTransactionRevision))
            var changedRule = try XCTUnwrap(db.recurringRules().first)
            let oldRuleRevision = changedRule.revision
            changedRule.note = "Changed rule after preview"
            changedRule = try db.saveRecurringRule(changedRule)
            XCTAssertThrowsError(try db.confirmRecurringCandidate(currentCandidate.id,
                expectedCandidateRevision: currentCandidate.revision,
                expectedOccurrenceRevision: occurrence.revision,
                expectedRuleRevision: oldRuleRevision,
                expectedTransactionRevision: actual.revision))
            XCTAssertEqual(try db.recurringOccurrences().first?.status, .expected)
            XCTAssertEqual(try db.transactions().count, 1)
            try db.confirmRecurringCandidate(currentCandidate.id,
                expectedCandidateRevision: currentCandidate.revision,
                expectedOccurrenceRevision: occurrence.revision,
                expectedRuleRevision: changedRule.revision,
                expectedTransactionRevision: actual.revision)
            XCTAssertEqual(try db.recurringOccurrences().first?.status, .confirmed)
            XCTAssertEqual(try db.transactions().first?.note, "Edited after preview")
            try db.checkDatabase()
        }
    }

    func testCompetingConfirmationsSettleOneOccurrenceOnce() throws {
        try withDatabase { db, url in
            let account = try account(db)
            _ = try rule(db, account: account)
            let sample = event("14,75")
            let attemptID = try parser(db, account: account, sample: sample)
            _ = try db.materializeDueRecurring(now: date("2026-10-15"))
            XCTAssertEqual(try db.processNotificationAttempt(attemptID).status, .recurringReview)
            let candidateID = try XCTUnwrap(db.recurringCandidates().first?.id)
            let lock = NSLock()
            var successes = 0
            var failures = 0
            DispatchQueue.concurrentPerform(iterations: 2) { _ in
                do {
                    try SQLiteDatabase(url: url).confirmRecurringCandidate(candidateID)
                    lock.lock(); successes += 1; lock.unlock()
                } catch {
                    lock.lock(); failures += 1; lock.unlock()
                }
            }
            XCTAssertEqual(successes, 1)
            XCTAssertEqual(failures, 1)
            XCTAssertEqual(try db.transactions().count, 1)
            XCTAssertEqual(try db.recurringOccurrences().first?.status, .confirmed)
            XCTAssertEqual(try db.recurringCandidates().first?.status, .confirmed)
            try db.checkDatabase()
        }
    }

    func testMultipleEligibleOccurrencesRemainAmbiguousAndOneWins() throws {
        try withDatabase { db, _ in
            let account = try account(db)
            let first = try rule(db, account: account)
            _ = try rule(db, account: account, start: "2026-10-16")
            try db.approveRecurringPayee("Fictional Plan", for: first.id)
            let secondRule = try XCTUnwrap(db.recurringRules().first { $0.id != first.id })
            try db.approveRecurringPayee("Fictional Plan", for: secondRule.id)
            let sample = event()
            let attemptID = try parser(db, account: account, sample: sample)
            _ = try db.materializeDueRecurring(now: date("2026-10-15"))
            XCTAssertEqual(try db.processNotificationAttempt(attemptID).status, .recurringReview)
            XCTAssertEqual(try db.recurringCandidates().filter { $0.status == .pending }.count, 2)
            XCTAssertEqual(try db.transactions().count, 1)
            try writeFixtureIfRequested(db, key: "EASYTRACK_RECONCILIATION_MULTIPLE_UI_FIXTURE_PATH")
            let chosen = try XCTUnwrap(db.recurringCandidates().first)
            try db.confirmRecurringCandidate(chosen.id)
            XCTAssertEqual(try db.recurringCandidates().filter { $0.status == .confirmed }.count, 1)
            XCTAssertEqual(try db.recurringCandidates().filter { $0.status == .rejected }.count, 1)
            XCTAssertThrowsError(try db.confirmRecurringCandidate(
                XCTUnwrap(db.recurringCandidates().first { $0.status == .rejected }).id))
            XCTAssertEqual(try db.transactions().count, 1)
            try db.checkDatabase()
        }
    }

    func testParserFailureRollsBackEarlyExpectedCandidateAndFinancialWrites() throws {
        try withDatabase { db, _ in
            let account = try account(db)
            let recurring = try rule(db, account: account)
            let sample = event(day: "2026-10-14")
            let attemptID = try parser(db, account: account, sample: sample)
            try db.execute("CREATE TRIGGER fictional_parser_failure BEFORE INSERT ON transactions BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END")
            XCTAssertEqual(try db.processNotificationAttempt(attemptID).status, .failed)
            XCTAssertEqual(try db.transactions().count, 0)
            XCTAssertTrue(try db.recurringOccurrences(ruleID: recurring.id).isEmpty)
            XCTAssertTrue(try db.recurringCandidates().isEmpty)
            XCTAssertEqual(try db.recurringRules().first?.nextIndex, 0)
            XCTAssertEqual(try db.notificationEvents().count, 1)
            try db.execute("DROP TRIGGER fictional_parser_failure")
            XCTAssertEqual(try db.processNotificationAttempt(attemptID).status, .recurringReview)
            XCTAssertEqual(try db.transactions().count, 1)
            try db.checkDatabase()
        }
    }

    func testPACMatchingNeverEntersExpenseOrPersonalSpendingTotals() throws {
        try withDatabase { db, _ in
            let account = try account(db)
            let recurring = try rule(db, account: account, kind: .pacInvestment)
            try db.approveRecurringPayee("Fictional Plan", for: recurring.id)
            let sample = event()
            let attemptID = try parser(db, account: account, sample: sample,
                                       kind: .pacInvestment)
            _ = try db.materializeDueRecurring(now: date("2026-10-15"))
            XCTAssertEqual(try db.processNotificationAttempt(attemptID).status, .created)
            let totals = LedgerTotals(transactions: try db.transactions())
            XCTAssertEqual(totals.pacInvestedEURMinor, 1_250)
            XCTAssertEqual(totals.totalExpensesEURMinor, 0)
            XCTAssertEqual(totals.personalSpendingEURMinor, 0)
            try db.checkDatabase()
        }
    }

    func testLinkingImportedActualPreservesItsPersonalShareAndSourceIdentity() throws {
        try withDatabase { db, _ in
            let account = try account(db)
            let (_, estimate, occurrence) = try oldCounted(db, account: account)
            var actual = imported("fictional-personal-share", day: "2026-10-15",
                                  merchant: "Fictional Plan", row: 9).transaction
            actual.accountID = account.id // explicit managed-account confirmation
            actual.personalExpenseEURMinor = 400
            _ = try db.save(actual)
            XCTAssertEqual(try db.transactions().count, 2)
            try db.linkRecurringTransaction(actual.id, to: occurrence.id)
            XCTAssertEqual(try db.transactions().map(\.id), [actual.id])
            XCTAssertNotNil(try db.transactions(includeDeleted: true).first { $0.id == estimate.id }?.deletedAt)
            XCTAssertEqual(try db.transactions().first?.sourceMovementID, "fictional-personal-share")
            XCTAssertEqual(try db.transactions().first?.sourceRow, 9)
            XCTAssertEqual(LedgerTotals(transactions: try db.transactions()).personalSpendingEURMinor, 400)
            try db.unlinkRecurringTransaction(occurrence.id)
            XCTAssertEqual(try db.transactions().count, 1)
            XCTAssertEqual(LedgerTotals(transactions: try db.transactions()).personalSpendingEURMinor, 400)
            XCTAssertEqual(try db.recurringOccurrences().first?.status, .expected)
            try db.checkDatabase()
        }
    }

    func testDeletingConfirmedActualDoesNotResurrectOldEstimate() throws {
        try withDatabase { db, _ in
            let account = try account(db)
            let (recurring, estimate, occurrence) = try oldCounted(db, account: account)
            let sample = event()
            let attemptID = try parser(db, account: account, sample: sample)
            try db.approveRecurringPayee("Fictional Plan", for: recurring.id)
            XCTAssertEqual(try db.processNotificationAttempt(attemptID).status, .matchedExisting)
            var transaction = try XCTUnwrap(db.transactions().first)
            transaction.deletedAt = .now
            _ = try db.save(transaction)
            XCTAssertTrue(try db.transactions().isEmpty)
            XCTAssertNotNil(try db.transactions(includeDeleted: true).first { $0.id == estimate.id }?.deletedAt)
            XCTAssertEqual(try db.recurringOccurrences().first?.status, .expected)
            XCTAssertEqual(try db.recurringOccurrences().first?.provisionalTransactionID, estimate.id)
            XCTAssertEqual(try db.recurringCandidates().first?.status, .rejected)
            XCTAssertEqual(LedgerTotals(transactions: try db.transactions()).totalExpensesEURMinor, 0)
            XCTAssertThrowsError(try db.confirmRecurringCandidate(
                XCTUnwrap(db.recurringCandidates(occurrenceID: occurrence.id).first?.id)))
            try db.checkDatabase()
        }
    }

    func testIncomeRuleLinksOnlyIncomeAndDoesNotAffectSpending() throws {
        try withDatabase { db, _ in
            let account = try account(db)
            let recurring = try rule(db, account: account, kind: .income)
            let sample = event()
            let attemptID = try parser(db, account: account, sample: sample, kind: .income)
            try db.approveRecurringPayee("Fictional Plan", for: recurring.id)
            _ = try db.materializeDueRecurring(now: date("2026-10-15"))
            XCTAssertEqual(try db.processNotificationAttempt(attemptID).status, .created)
            let totals = LedgerTotals(transactions: try db.transactions())
            XCTAssertEqual(totals.incomeEURMinor, 1_250)
            XCTAssertEqual(totals.totalExpensesEURMinor, 0)
            XCTAssertEqual(totals.personalSpendingEURMinor, 0)
            try db.checkDatabase()
        }
    }
}
