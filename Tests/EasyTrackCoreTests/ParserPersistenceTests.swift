import SQLite3
import XCTest
@testable import EasyTrackCore

final class ParserPersistenceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_100_000)

    private func temporaryDatabase(_ body: (URL, SQLiteDatabase) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-parser-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("local.sqlite")
        try body(url, SQLiteDatabase(url: url))
    }

    private func event(_ text: String, title: String = "Card purchase", at date: Date,
                       source: String = "Northstar Pay (fictional)") -> NotificationEvent {
        NotificationEvent.make(sourceApp: source, title: title, subtitle: "",
                               message: text, receivedAt: date, capturedAt: date)!
    }

    private func rule(source: ParserSource, sample: NotificationEvent,
                      name: String = "Fictional purchases", priority: Int = 1,
                      kind: TransactionKind = .expense) -> ParserRule {
        var config = NotificationParser.suggest(for: sample)
        config.kind = kind
        return ParserRule(id: UUID(), sourceID: source.id, name: name, enabled: true,
                          priority: priority, version: 0, config: config, createdAt: .now,
                          updatedAt: .now, deletedAt: nil)
    }

    private func scalar(_ sql: String, at url: URL) throws -> Int {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw NSError(domain: "SQLite", code: 1)
        }
        defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "SQLite", code: 2)
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw NSError(domain: "SQLite", code: 3) }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func execute(_ sql: String, at url: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else { throw NSError(domain: "SQLite", code: 4) }
        defer { sqlite3_close(handle) }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw NSError(domain: "SQLite", code: 5) }
    }

    func testFirstSampleDuplicatesWindowRelaunchAndRuleVersion() throws {
        try temporaryDatabase { url, database in
            let first = event("Paid €12,34 at Cedar Books", at: start)
            let capture = try database.captureNotification(first)
            XCTAssertEqual(capture.status, .setupRequired)
            XCTAssertEqual(try database.transactions().count, 0)
            let source = try database.mapParserSource(XCTUnwrap(database.parserSources().first).id,
                                                      to: "Fictional checking")
            var saved = try database.saveParserRule(rule(source: source, sample: first))
            XCTAssertEqual(saved.version, 1)
            XCTAssertTrue(NotificationParser.preview(first, config: saved.config,
                                                     mappedAccount: source.accountName).ready)
            let created = try database.processNotificationAttempt(capture.id, preferredRuleID: saved.id)
            XCTAssertEqual(created.status, .created)
            XCTAssertNotNil(created.transactionID)
            XCTAssertEqual(created.ruleVersion, 1)
            XCTAssertEqual(try database.transactions().count, 1)
            XCTAssertEqual(try database.operations().count, 1)

            let exact = try database.captureNotification(event("Paid €12,34 at Cedar Books", at: start))
            XCTAssertEqual(exact.status, .duplicateIgnored)
            XCTAssertEqual(exact.transactionID, created.transactionID)
            let semantic = try database.captureNotification(event("Paid 12,34 € at Cedar Books",
                                                                at: start.addingTimeInterval(120)))
            XCTAssertEqual(semantic.status, .duplicateIgnored)
            XCTAssertEqual(semantic.transactionID, created.transactionID)
            let different = try database.captureNotification(event("Paid €13,34 at Cedar Books",
                                                                 at: start.addingTimeInterval(150)))
            XCTAssertEqual(different.status, .created)
            let later = try database.captureNotification(event("Paid €12,34 at Cedar Books",
                                                             at: start.addingTimeInterval(1_200)))
            XCTAssertEqual(later.status, .created)
            XCTAssertEqual(try database.transactions().count, 3)

            saved.name = "Updated outgoing format"
            saved = try database.saveParserRule(saved)
            XCTAssertEqual(saved.version, 2)
            XCTAssertEqual(try database.parserRuleHistory(saved.id).map(\.version), [2, 1])
            XCTAssertEqual(try database.captureNotification(event("Paid €12,34 at Cedar Books", at: start)).status,
                           .duplicateIgnored)
            XCTAssertEqual(try database.transactions().count, 3)
            let reopened = try SQLiteDatabase(url: url)
            XCTAssertEqual(try reopened.parserRules().first?.version, 2)
            XCTAssertEqual(try reopened.transactions().count, 3)
            XCTAssertEqual(try reopened.parserAttempts().count, 6)
            XCTAssertEqual(try reopened.transactions().first { $0.id == created.transactionID }?.category, "")
            XCTAssertEqual(try scalar("SELECT COUNT(*) FROM transactions WHERE category IS NULL", at: url), 3)
            XCTAssertEqual(try scalar("SELECT COUNT(*) FROM exact_dedup", at: url), 3)
            XCTAssertEqual(try scalar("SELECT COUNT(*) FROM semantic_dedup", at: url), 3)
        }
    }

    func testMultipleFormatsAndPriority() throws {
        try temporaryDatabase { _, database in
            let first = event("Paid €12,34 at Cedar Books", at: start)
            let captured = try database.captureNotification(first)
            let source = try database.mapParserSource(XCTUnwrap(database.parserSources().first).id,
                                                      to: "Fictional checking")
            let low = try database.saveParserRule(rule(source: source, sample: first,
                                                       name: "Later expense rule", priority: 2))
            let high = try database.saveParserRule(rule(source: source, sample: first,
                                                        name: "First income rule", priority: 1, kind: .income))
            let firstResult = try database.processNotificationAttempt(captured.id)
            XCTAssertEqual(firstResult.ruleID, high.id)
            XCTAssertEqual(try database.transactions().first?.kind, .income)
            XCTAssertNotEqual(firstResult.ruleID, low.id)

            try database.swapParserRulePriorities(low, high)
            let reordered = try database.parserRules(sourceID: source.id)
            XCTAssertEqual(reordered.map(\.id), [low.id, high.id])
            XCTAssertEqual(reordered.map(\.version), [2, 2])
            XCTAssertThrowsError(try database.swapParserRulePriorities(low, high))
            XCTAssertEqual(try database.parserRules(sourceID: source.id).map(\.id), [low.id, high.id])
            let secondPurchase = try database.captureNotification(event("Paid €6,00 at Cedar Books",
                                                                         at: start.addingTimeInterval(120)))
            XCTAssertEqual(secondPurchase.ruleID, low.id)

            let refund = event("Refund €5,00 from Cedar Books", title: "Refund posted",
                               at: start.addingTimeInterval(360))
            let refundRule = rule(source: source, sample: refund, name: "Refund format", priority: 3,
                                  kind: .reimbursement)
            _ = try database.saveParserRule(refundRule)
            let result = try database.captureNotification(refund)
            XCTAssertEqual(result.status, .created)
            XCTAssertEqual(result.ruleID, refundRule.id)
            XCTAssertEqual(try database.transactions().first { $0.id == result.transactionID }?.kind,
                           .reimbursement)
        }
    }

    func testMissingPayloadDateUsesReceiptTimeAndAllowsLaterIdenticalPayment() throws {
        try temporaryDatabase { _, database in
            func undated(_ date: Date) -> NotificationEvent {
                NotificationEvent.make(sourceApp: "Northstar Pay (fictional)", title: "Card purchase",
                                       subtitle: "", message: "Paid €4,20 at Cedar Books",
                                       receivedAt: nil, capturedAt: date)!
            }
            let first = undated(start)
            let captured = try database.captureNotification(first)
            let source = try database.mapParserSource(XCTUnwrap(database.parserSources().first).id,
                                                      to: "Fictional checking")
            let saved = try database.saveParserRule(rule(source: source, sample: first))
            let created = try database.processNotificationAttempt(captured.id, preferredRuleID: saved.id)
            XCTAssertEqual(created.status, .created)
            XCTAssertEqual(try database.transactions().first?.occurredAt, start)
            XCTAssertEqual(try database.captureNotification(undated(start.addingTimeInterval(120))).status,
                           .duplicateIgnored)
            XCTAssertEqual(try database.captureNotification(undated(start.addingTimeInterval(1_200))).status,
                           .created)
            XCTAssertEqual(try database.transactions().count, 2)
        }
    }

    func testOneSourceFormatCapturesDifferentMerchantsWithoutCategories() throws {
        try temporaryDatabase { url, database in
            let sourceName = "Revolut-like wallet (fictional)"
            let alpha = event("You paid €12,34 to Merchant Alpha", title: "Outgoing card payment",
                              at: start, source: sourceName)
            let first = try database.captureNotification(alpha)
            let source = try database.mapParserSource(XCTUnwrap(database.parserSources().first).id,
                                                      to: "Fictional wallet account")
            let format = try database.saveParserRule(rule(source: source, sample: alpha,
                                                          name: "Outgoing card payment"))
            XCTAssertFalse(format.config.conditionText.localizedCaseInsensitiveContains("Merchant Alpha"))
            XCTAssertEqual(try database.processNotificationAttempt(first.id, preferredRuleID: format.id).status,
                           .created)
            let beta = event("You paid €7,89 to Merchant Beta", title: "Outgoing card payment",
                             at: start.addingTimeInterval(180), source: sourceName)
            let second = try database.captureNotification(beta)
            XCTAssertEqual(second.status, .created)
            XCTAssertEqual(second.ruleID, format.id)
            XCTAssertEqual(try database.parserRules(sourceID: source.id).count, 1)
            let transactions = try database.transactions().sorted { $0.amountMinor > $1.amountMinor }
            XCTAssertEqual(transactions.map(\.merchant), ["Merchant Alpha", "Merchant Beta"])
            XCTAssertEqual(transactions.map(\.amountMinor), [1_234, 789])
            XCTAssertEqual(transactions.map(\.account), ["Fictional wallet account", "Fictional wallet account"])
            XCTAssertTrue(transactions.allSatisfy { $0.category.isEmpty })
            XCTAssertEqual(try scalar("SELECT COUNT(*) FROM transactions WHERE category IS NULL", at: url), 2)
            XCTAssertEqual(try database.captureNotification(beta).status, .duplicateIgnored)
            XCTAssertEqual(try database.transactions().count, 2)
        }
    }

    func testKnownSourceNameUsesExistingAccountAutomatically() throws {
        try temporaryDatabase { _, database in
            let existing = Transaction(id: UUID(), kind: .expense, amountMinor: 100,
                                       currency: "EUR", merchant: "Synthetic prior entry", account: "Revolut",
                                       category: "Books", note: "", occurredAt: start.addingTimeInterval(-86_400),
                                       updatedAt: start, deletedAt: nil, isDemo: false, revision: 0,
                                       sourceEventID: nil)
            try database.save(existing)
            let sample = event("You paid €12,34 to Merchant Alpha", title: "Outgoing card payment",
                               at: start, source: " revolut ")
            let captured = try database.captureNotification(sample)
            let source = try XCTUnwrap(database.parserSources().first)
            XCTAssertEqual(source.accountName, "Revolut")
            let format = try database.saveParserRule(rule(source: source, sample: sample))
            let result = try database.processNotificationAttempt(captured.id, preferredRuleID: format.id)
            XCTAssertEqual(result.status, .created)
            XCTAssertEqual(try database.transactions().first { $0.id == result.transactionID }?.account, "Revolut")
        }
    }

    func testOutgoingAndIncomingFormatsShareSourceAccountAndMappingChangesOnlyFutureRows() throws {
        try temporaryDatabase { _, database in
            let sourceName = "Revolut-like wallet (fictional)"
            let outgoing = event("You paid €12,34 to Merchant Alpha", title: "Outgoing card payment",
                                 at: start, source: sourceName)
            let first = try database.captureNotification(outgoing)
            let source = try database.mapParserSource(XCTUnwrap(database.parserSources().first).id,
                                                      to: "Fictional wallet account")
            let outgoingRule = try database.saveParserRule(rule(source: source, sample: outgoing,
                                                                  name: "Outgoing card payment"))
            let firstResult = try database.processNotificationAttempt(first.id, preferredRuleID: outgoingRule.id)
            XCTAssertEqual(firstResult.status, .created)
            let incoming = event("You received €5,00 from Sender Beta", title: "Incoming transfer",
                                 at: start.addingTimeInterval(120), source: sourceName)
            var incomingRule = rule(source: source, sample: incoming, name: "Incoming transfer",
                                    priority: 2, kind: .income)
            incomingRule.config.conditionText = "Incoming transfer"
            _ = try database.saveParserRule(incomingRule)
            let received = try database.captureNotification(incoming)
            XCTAssertEqual(received.status, .created)
            XCTAssertEqual(received.ruleID, incomingRule.id)
            let original = try XCTUnwrap(database.transactions().first { $0.id == firstResult.transactionID })
            let incomingTransaction = try XCTUnwrap(database.transactions().first { $0.id == received.transactionID })
            XCTAssertEqual(original.account, incomingTransaction.account)
            XCTAssertEqual(incomingTransaction.kind, .income)
            XCTAssertEqual(incomingTransaction.merchant, "Sender Beta")

            let remapped = try database.mapParserSource(source.id, to: "Updated fictional account")
            XCTAssertEqual(remapped.accountName, "Updated fictional account")
            let later = try database.captureNotification(event("You paid €9,50 to Merchant Gamma",
                                                               title: "Outgoing card payment",
                                                               at: start.addingTimeInterval(240), source: sourceName))
            XCTAssertEqual(later.status, .created)
            XCTAssertEqual(try database.transactions().first { $0.id == later.transactionID }?.account,
                           "Updated fictional account")
            XCTAssertEqual(try database.transactions().first { $0.id == firstResult.transactionID }?.account,
                           "Fictional wallet account")
            XCTAssertEqual(try database.parserRules(sourceID: source.id).count, 2)

            let otherSourceName = "PayPal-like wallet (fictional)"
            let other = event("You paid €12,34 to Merchant Alpha", title: "Outgoing card payment",
                              at: start.addingTimeInterval(260), source: otherSourceName)
            let otherCapture = try database.captureNotification(other)
            let otherSource = try database.mapParserSource(XCTUnwrap(database.parserSources().first {
                $0.name == otherSourceName
            }).id, to: "Second fictional account")
            let otherRule = try database.saveParserRule(rule(source: otherSource, sample: other,
                                                               name: "Outgoing card payment"))
            let otherResult = try database.processNotificationAttempt(otherCapture.id,
                                                                       preferredRuleID: otherRule.id)
            XCTAssertEqual(otherResult.status, .created)
            XCTAssertEqual(try database.transactions().first { $0.id == otherResult.transactionID }?.account,
                           "Second fictional account")
        }
    }

    func testProcessingFailureRollsBackTransactionAndRetainsRawDiagnostic() throws {
        try temporaryDatabase { url, database in
            let sample = event("Paid €12,34 at Cedar Books", at: start)
            let captured = try database.captureNotification(sample)
            let source = try database.mapParserSource(XCTUnwrap(database.parserSources().first).id,
                                                      to: "Fictional checking")
            let savedRule = try database.saveParserRule(rule(source: source, sample: sample))
            try database.leaveSampleReady(captured.id)
            try execute("CREATE TRIGGER synthetic_parser_failure BEFORE INSERT ON transactions BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END", at: url)
            let failed = try database.captureNotification(event("Paid €9,50 at Cedar Books",
                                                                 at: start.addingTimeInterval(60)))
            XCTAssertEqual(failed.status, .failed)
            XCTAssertEqual(failed.ruleID, savedRule.id)
            XCTAssertEqual(failed.ruleVersion, 1)
            XCTAssertTrue(failed.event.message.contains("Cedar Books"))
            XCTAssertEqual(try database.transactions().count, 0)
            XCTAssertEqual(try database.operations().count, 0)
            XCTAssertEqual(try scalar("SELECT COUNT(*) FROM exact_dedup", at: url), 0)
            XCTAssertEqual(try scalar("SELECT COUNT(*) FROM semantic_dedup", at: url), 0)
            XCTAssertEqual(try database.parserAttempts().count, 2)
            try execute("DROP TRIGGER synthetic_parser_failure", at: url)
            let retried = try database.processNotificationAttempt(failed.id)
            XCTAssertEqual(retried.status, .created)
            XCTAssertEqual(try database.transactions().count, 1)
            XCTAssertEqual(try database.parserRules(sourceID: source.id).count, 1)
            XCTAssertEqual(try database.operations().count, 1)
        }
    }

    func testDeletingFormatKeepsItsTransactionsAndAudit() throws {
        try temporaryDatabase { _, database in
            let sample = event("Paid €12,34 at Cedar Books", at: start)
            let captured = try database.captureNotification(sample)
            let source = try database.mapParserSource(XCTUnwrap(database.parserSources().first).id,
                                                      to: "Fictional checking")
            var saved = try database.saveParserRule(rule(source: source, sample: sample))
            let created = try database.processNotificationAttempt(captured.id, preferredRuleID: saved.id)
            XCTAssertEqual(created.status, .created)
            saved.deletedAt = .now
            saved = try database.saveParserRule(saved)
            XCTAssertEqual(saved.version, 2)
            XCTAssertTrue(try database.parserRules(sourceID: source.id).isEmpty)
            XCTAssertEqual(try database.parserRuleHistory(saved.id).count, 2)
            XCTAssertEqual(try database.transactions().count, 1)
            XCTAssertEqual(try database.transactions().first?.id, created.transactionID)
            XCTAssertEqual(try database.captureNotification(event("Paid €8,00 at Another Merchant",
                                                                at: start.addingTimeInterval(60))).status,
                           .setupRequired)
            XCTAssertEqual(try database.transactions().count, 1)
        }
    }

    func testVersionTwoDatabaseUpgradesWithoutLosingNotification() throws {
        try temporaryDatabase { url, database in
            let old = event("Paid €2,00 at Old Sample", at: start)
            XCTAssertEqual(try database.captureNotification(old).status, .setupRequired)
            try execute("""
                PRAGMA foreign_keys=OFF;
                DROP TABLE recurring_reconciliation_audit;
                DROP TABLE recurring_payee_aliases;
                DROP TABLE recurring_candidates;
                DROP TABLE recurring_occurrences_local;
                DROP TABLE semantic_dedup;
                DROP TABLE exact_dedup;
                DROP TABLE notification_attempts;
                DROP TABLE parser_rule_versions;
                DROP TABLE parser_rules;
                DROP TABLE parser_sources;
                PRAGMA user_version=2;
                """, at: url)
            let upgraded = try SQLiteDatabase(url: url)
            XCTAssertEqual(try scalar("PRAGMA user_version", at: url), 11)
            XCTAssertEqual(try upgraded.notificationEvents().count, 1)
            XCTAssertEqual(try upgraded.parserSources().count, 1)
            XCTAssertEqual(try upgraded.parserAttempts().first?.status, .setupRequired)
        }
    }

    func testSecurityAndPromotionCapturesAreRejectedWithoutTransactions() throws {
        try temporaryDatabase { _, database in
            let account = try database.saveLocalAccount(LocalAccount(id: UUID(), name: "Fictional checking",
                                                                      createdAt: start))
            let source = try database.configureParserSource(named: "Northstar Pay (fictional)",
                                                            accountID: account.id)
            let payment = event("Paid €12,34 at Cedar Books", at: start)
            _ = try database.saveParserRule(rule(source: source, sample: payment))

            let otp = event("Your OTP code is 482913. Do not share this code.",
                            title: "Verification code", at: start.addingTimeInterval(60))
            let rejectedOTP = try database.captureNotification(otp)
            XCTAssertEqual(rejectedOTP.status, .rejected)
            XCTAssertTrue(rejectedOTP.detail?.contains("OTP") == true)

            let promotion = event("Get €10 cashback this weekend. Open the app to discover the offer.",
                                  title: "Special offer", at: start.addingTimeInterval(120))
            let rejectedPromotion = try database.captureNotification(promotion)
            XCTAssertEqual(rejectedPromotion.status, .rejected)
            XCTAssertTrue(rejectedPromotion.detail?.contains("Promotional") == true)
            XCTAssertTrue(try database.transactions().isEmpty)
        }
    }

    func testDiagnosticRetentionScrubsRawTextButPreservesLedgerAndBackupPreferences() throws {
        try temporaryDatabase { _, database in
            try database.seedDemoIfNeeded()
            let initialTransactionCount = try database.transactions().count
            let oldDate = start.addingTimeInterval(-8 * 86_400)
            let sample = event("Paid €12,34 at Cedar Books", at: oldDate)
            let captured = try database.captureNotification(sample)
            let source = try database.mapParserSource(XCTUnwrap(database.parserSources().first).id,
                                                      to: "Fictional checking")
            let saved = try database.saveParserRule(rule(source: source, sample: sample))
            XCTAssertEqual(try database.processNotificationAttempt(captured.id,
                                                                    preferredRuleID: saved.id).status, .created)
            try database.markAutomationSetupMilestone(.simulationCompleted)
            XCTAssertEqual(try database.setNotificationRetentionDays(7, now: start), 1)

            let scrubbed = try XCTUnwrap(database.parserAttempts().first)
            XCTAssertEqual(scrubbed.event.sourceApp, "Northstar Pay (fictional)")
            XCTAssertTrue(scrubbed.event.title.isEmpty)
            XCTAssertTrue(scrubbed.event.subtitle.isEmpty)
            XCTAssertTrue(scrubbed.event.message.isEmpty)
            XCTAssertEqual(try database.transactions().count, initialTransactionCount + 1)
            XCTAssertEqual(try database.notificationEvents().first?.message, "")

            let backup = try database.exportBackup()
            XCTAssertEqual(backup.schemaVersion, 12)
            XCTAssertEqual(backup.databaseSchemaVersion, 11)
            let targetURL = database.url.deletingLastPathComponent().appendingPathComponent("restored.sqlite")
            let target = try SQLiteDatabase(url: targetURL)
            _ = try target.restoreBackup(backup, preview: target.previewBackup(backup), mode: .replace)
            XCTAssertEqual(try target.notificationRetentionDays(), 7)
            XCTAssertTrue(try target.automationSetupMilestones().contains(.simulationCompleted))
            XCTAssertEqual(try target.transactions().count, initialTransactionCount + 1)
            XCTAssertEqual(try target.parserAttempts().first?.event.message, "")
        }
    }

    func testDiagnosticRetentionBoundaryAndZeroDayPolicy() throws {
        try temporaryDatabase { _, database in
            let cutoff = start.addingTimeInterval(-7 * 86_400)
            _ = try database.captureNotification(event("Paid €1,00 at Older Merchant",
                                                       at: cutoff.addingTimeInterval(-1)))
            _ = try database.captureNotification(event("Paid €2,00 at Boundary Merchant", at: cutoff,
                                                       source: "Boundary Wallet (fictional)"))
            XCTAssertEqual(try database.setNotificationRetentionDays(7, now: start), 1)
            let afterSevenDays = try database.parserAttempts()
            XCTAssertTrue(afterSevenDays.first { $0.event.sourceApp == "Northstar Pay (fictional)" }?.event.message.isEmpty == true)
            XCTAssertTrue(afterSevenDays.first { $0.event.sourceApp == "Boundary Wallet (fictional)" }?.event.message.contains("Boundary") == true)

            XCTAssertEqual(try database.setNotificationRetentionDays(0,
                                                                      now: start.addingTimeInterval(1)), 1)
            XCTAssertTrue(try database.parserAttempts().allSatisfy { $0.event.title.isEmpty &&
                $0.event.subtitle.isEmpty && $0.event.message.isEmpty })
            XCTAssertEqual(try database.notificationRetentionDays(), 0)
        }
    }
}
