import Foundation
import XCTest
@testable import EasyTrackCore

#if os(macOS)
final class ShowcaseFixtureTests: XCTestCase {
    private let zone = TimeZone(identifier: "Europe/Rome")!

    func testSyntheticShowcaseLedgerIsConsistent() throws {
        let requested = ProcessInfo.processInfo.environment["EASYTRACK_SHOWCASE_DB_OUTPUT"]
        let folder = requested.map { URL(fileURLWithPath: $0).deletingLastPathComponent() } ??
            FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-showcase-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { if requested == nil { try? FileManager.default.removeItem(at: folder) } }
        let url = requested.map { URL(fileURLWithPath: $0) } ?? folder.appendingPathComponent("ledger.sqlite")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "Refusing to overwrite a showcase ledger")

        let database = try SQLiteDatabase(url: url)
        try database.completeOnboarding()
        let checking = try database.saveLocalAccount(LocalAccount(
            id: stableID("checking"), name: "Sample Checking", createdAt: .now,
            symbolName: "creditcard.fill", colorName: "teal"))
        let savings = try database.saveLocalAccount(LocalAccount(
            id: stableID("savings"), name: "Sample Savings", createdAt: .now,
            symbolName: "building.columns.fill", colorName: "blue"))
        try database.setDefaultExpenseAccountID(checking.id)

        let definitions: [(String, String, String)] = [
            ("Coffee", "fork.knife", "orange"),
            ("Subscriptions", "doc.text.fill", "purple"),
            ("Investments", "square.grid.2x2.fill", "blue")
        ]
        var categories = Dictionary(uniqueKeysWithValues: try database.ledgerCategories().map { ($0.name, $0) })
        for (index, definition) in definitions.enumerated() {
            let saved = try database.saveLedgerCategory(LedgerCategory(
                id: stableID("category-\(definition.0)"), name: definition.0,
                symbolName: definition.1, colorName: definition.2, sortIndex: index,
                createdAt: .now, updatedAt: .now, archivedAt: nil, revision: 0))
            categories[saved.name] = saved
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let now = Date()
        let current = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let currentDay = calendar.component(.day, from: now)
        let entries: [(Int, TransactionKind, Int64, String, String, LocalAccount)] = [
            (2, .income, 285_000, "Irisford Studio", "Salary", checking),
            (3, .expense, 92_000, "Willowmere Home", "Home", checking),
            (5, .expense, 18_450, "Lumenfield Grocer", "Groceries", checking),
            (7, .expense, 7_800, "Northvale Utilities", "Home", checking),
            (9, .expense, 4_250, "Mosswick Transit", "Transport", checking),
            (11, .expense, 1_860, "Cedarline Coffee", "Coffee", checking),
            (12, .expense, 1_290, "Paperlane Digital", "Subscriptions", checking),
            (13, .pacInvestment, 22_000, "Northstar Index Plan", "Investments", savings)
        ]
        for monthsAgo in 0..<6 {
            let month = calendar.date(byAdding: .month, value: -monthsAgo, to: current)!
            let monthKey = calendar.dateComponents([.year, .month], from: month)
            for (day, kind, amount, merchant, categoryName, account) in entries {
                let visibleDay = monthsAgo == 0 ? min(day, currentDay) : day
                let occurredAt = calendar.date(byAdding: .day, value: visibleDay - 1, to: month)!
                var transaction = Transaction(id: stableID("\(monthKey.year!)-\(monthKey.month!)-\(merchant)"),
                    kind: kind, amountMinor: amount, currency: "EUR", merchant: merchant,
                    account: account.name, category: categoryName, note: "Fictional showcase entry",
                    occurredAt: occurredAt, updatedAt: now, deletedAt: nil, isDemo: false,
                    revision: 0, sourceEventID: nil)
                transaction.accountID = account.id
                transaction.categoryID = categories[categoryName]?.id
                transaction.eurMinor = amount
                transaction.personalExpenseEURMinor = kind == .expense ? amount : 0
                _ = try database.save(transaction)
            }
        }
        let reimbursementDate = calendar.date(byAdding: .day, value: min(14, currentDay) - 1,
                                              to: current)!
        var reimbursement = Transaction(id: stableID("showcase-reimbursement"), kind: .reimbursement,
            amountMinor: 3_200, currency: "EUR", merchant: "Shared weekend refund",
            account: checking.name, category: "", note: "Fictional shared expense refund",
            occurredAt: reimbursementDate, updatedAt: now, deletedAt: nil, isDemo: false,
            revision: 0, sourceEventID: nil)
        reimbursement.accountID = checking.id
        reimbursement.eurMinor = 3_200
        reimbursement.personalExpenseEURMinor = -3_200
        _ = try database.save(reimbursement)

        let nextMonth = calendar.date(byAdding: .month, value: 1, to: current)!
        let nextDay = LocalDay(date: nextMonth, timeZone: zone)
        _ = try database.saveRecurringRule(RecurringRule(id: stableID("monthly-plan"),
            name: "Paperlane Monthly", type: .subscription, amountMinor: 1_290,
            accountID: checking.id, categoryID: categories["Subscriptions"]!.id,
            startDay: nextDay, frequency: .monthly, nextIndex: 0, endDay: nil,
            timeZoneIdentifier: zone.identifier, isActive: true, note: "Fictional plan",
            createdAt: now, updatedAt: now, archivedAt: nil, revision: 0))
        _ = try database.saveMonthlyBudget(MonthlyBudget(id: stableID("overall-budget"),
            scope: .overall, categoryID: nil, limitEURMinor: 150_000,
            createdAt: now, updatedAt: now, archivedAt: nil, revision: 0))
        try addNotificationExamples(to: database, account: checking, now: now)
        try importFictionalExample(into: database, folder: folder)

        let month = LocalDay(date: current, timeZone: zone)
        let currentRows = try database.transactions().filter {
            let day = LocalDay(date: $0.occurredAt, timeZone: zone)
            return day.year == month.year && day.month == month.month
        }
        let totals = LedgerTotals(transactions: currentRows)
        XCTAssertEqual(totals.totalExpensesEURMinor, 125_650)
        XCTAssertEqual(totals.personalSpendingEURMinor, 122_450)
        XCTAssertEqual(totals.incomeEURMinor, 285_000)
        XCTAssertEqual(totals.pacInvestedEURMinor, 22_000)
        XCTAssertEqual(try database.transactions().count, 52)
        XCTAssertEqual(try database.parserRules().count, 2)
        try database.checkDatabase()
        try database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    private func importFictionalExample(into database: SQLiteDatabase, folder: URL) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let seedURL = folder.appendingPathComponent("example-seed.sqlite")
        let converter = Process()
        converter.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        converter.arguments = ["python3", "Tools/HistoricalImportConverter/convert_xlsx.py",
            "--input", "docs/examples/EasyTrack-example-import.xlsx",
            "--mapping", "docs/examples/simple-import-mapping.json",
            "--output", seedURL.path,
            "--audit", folder.appendingPathComponent("example-audit.txt").path]
        converter.currentDirectoryURL = root
        let output = Pipe()
        converter.standardOutput = output
        converter.standardError = output
        try converter.run()
        converter.waitUntilExit()
        let diagnostic = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(converter.terminationStatus, 0, diagnostic)
        let seed = try SeedMapper(url: seedURL).read(url: seedURL)
        XCTAssertEqual(seed.movements.count, 3)
        XCTAssertTrue(seed.warnings.isEmpty)
        XCTAssertEqual(try database.importHistoricalSeed(seed).newMovements, 3)
    }

    private func addNotificationExamples(to database: SQLiteDatabase, account: LocalAccount,
                                          now: Date) throws {
        let source = try database.configureParserSource(named: "Sample Wallet", accountID: account.id)
        let examples: [(String, TransactionKind, String, String)] = [
            ("Incoming credits", .income, "Wallet update", "Received €145,00 from Irisford Studio"),
            ("Card payments", .expense, "Wallet update", "Paid €18,40 at Lumenfield Grocer")
        ]
        for (index, example) in examples.enumerated() {
            let (name, kind, title, message) = example
            let capturedAt = now.addingTimeInterval(Double(index - 1) * 60)
            let event = try XCTUnwrap(NotificationEvent.make(sourceApp: source.name,
                title: title, subtitle: "Example notification", message: message,
                receivedAt: capturedAt, capturedAt: capturedAt))
            let attempt = try database.captureNotification(event)
            var config = NotificationParser.suggest(for: event)
            config.kind = kind
            _ = try database.saveParserRule(ParserRule(id: stableID("parser-\(name)"),
                sourceID: source.id, name: name, enabled: true,
                priority: kind == .expense ? 1 : 2, version: 0, config: config,
                createdAt: now, updatedAt: now, deletedAt: nil))
            try database.leaveSampleReady(attempt.id)
        }
    }

    private func stableID(_ value: String) -> UUID {
        SeedMapper.stableTransactionID(sourceID: "EasyTrack showcase: \(value)")
    }
}
#endif
