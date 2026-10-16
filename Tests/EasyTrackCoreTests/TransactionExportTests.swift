import Foundation
import XCTest
@testable import EasyTrackCore

final class TransactionExportTests: XCTestCase {
    private let zone = TimeZone(identifier: "Europe/Rome")!

    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    private func item(_ id: String, kind: TransactionKind, cents: Int64, merchant: String,
                      at timestamp: String = "2026-10-15T10:00:00Z") -> Transaction {
        Transaction(id: UUID(uuidString: id)!, kind: kind, amountMinor: cents,
                    currency: "EUR", merchant: merchant, account: "Fictional checking",
                    category: "Food", note: "", occurredAt: date(timestamp),
                    updatedAt: date(timestamp), deletedAt: nil, isDemo: false,
                    revision: 1, sourceEventID: nil)
    }

    private func fixture() -> TransactionExportSnapshot {
        var rows: [Transaction] = []
        let kinds: [(TransactionKind, Int64, String)] = [
            (.expense, 1_234, "Fictional café, \"Blue\"\nPier"),
            (.income, 25_000, "Fictional salary"),
            (.pacInvestment, 3_500, "Fictional PAC"),
            (.advanceForOthers, 700, "Fictional advance"),
            (.reimbursement, 500, "Fictional reimbursement"),
            (.deposit, 2_000, "Fictional deposit"),
            (.depositRefund, 2_000, "Fictional deposit refund")
        ]
        for (index, row) in kinds.enumerated() {
            var transaction = item(String(format: "00000000-0000-4000-8000-%012d", index + 1),
                                   kind: row.0, cents: row.1, merchant: row.2)
            transaction.eurMinor = row.1
            if index == 0 { transaction.personalExpenseEURMinor = 1_000 }
            if index == 4 { transaction.personalExpenseEURMinor = -500 }
            if index == 3 { transaction.recoverableEURMinor = 700 }
            if index == 5 { transaction.recoverableEURMinor = 2_000 }
            if index == 0 { transaction.note = " \t=2+2" }
            rows.append(transaction)
        }
        var historical = item("00000000-0000-4000-8000-000000000008", kind: .expense,
                              cents: 875, merchant: "Fictional imported purchase")
        historical.currency = "EUR" // Current edited amount; original source remains THB.
        historical.eurMinor = 875
        historical.sourceMovementID = "fictional-source-8"
        historical.sourceSheet = "Fictional sheet"
        historical.sourceRow = 8
        historical.sourceOccurredAt = "2025-02-01T12:00:00"
        historical.exchangeRateEUR = "0.027"
        historical.tripID = "fictional-trip"
        rows.append(historical)

        var missingEUR = item("00000000-0000-4000-8000-000000000009", kind: .expense,
                              cents: 2_500, merchant: "Fictional missing EUR")
        missingEUR.currency = "CNY"
        missingEUR.eurMinor = nil
        missingEUR.category = ""
        rows.append(missingEUR)

        var demo = item("00000000-0000-4000-8000-000000000010", kind: .expense,
                        cents: 100, merchant: "Demo excluded")
        demo.isDemo = true
        rows.append(demo)
        var deleted = item("00000000-0000-4000-8000-000000000011", kind: .expense,
                           cents: 100, merchant: "Fictional deleted")
        deleted.deletedAt = .now
        rows.append(deleted)
        return TransactionExportSnapshot(transactions: rows, accountNames: [:], categoryNames: [:],
            tripNames: ["fictional-trip":"Fictional trip"],
            historicalOriginals: [historical.id: HistoricalOriginalValues(
                amountMinor: 32_000, currency: "THB", eurMinor: 800,
                exchangeRateEUR: "0.025", occurredAt: "2025-02-01T12:00:00")])
    }

    private var options: TransactionExportOptions {
        var value = TransactionExportOptions()
        value.timeZoneIdentifier = zone.identifier
        return value
    }

    func testSevenKindsTotalsHistoricalValuesAndCSVPresets() throws {
        let selection = try fixture().select(filter: .init(), options: options)
        XCTAssertEqual(selection.rows.count, 9)
        XCTAssertFalse(selection.rows.contains { $0.item.isDemo || $0.item.deletedAt != nil })
        let totals = try selection.totals()
        XCTAssertEqual(totals.count, 9)
        XCTAssertEqual(totals.expenses, 1_234 + 875)
        XCTAssertEqual(totals.income, 25_000)
        XCTAssertEqual(totals.pac, 3_500)
        XCTAssertEqual(totals.personal, 1_000 - 500 + 875)
        XCTAssertEqual(selection.rows.first { $0.item.sourceMovementID != nil }?.original?.currency, "THB")
        XCTAssertEqual(selection.rows.first { $0.item.sourceMovementID != nil }?.item.currency, "EUR")
        XCTAssertNil(selection.rows.first { $0.item.currency == "CNY" }?.currentEURMinor)

        var settings = options
        settings.columns = .detailed
        settings.includeTechnicalIDs = true
        let csv = try TransactionCSVWriter.encode(selection, options: settings)
        let text = try XCTUnwrap(String(data: csv, encoding: .utf8))
        XCTAssertTrue(text.contains("Imported amount"))
        XCTAssertTrue(text.contains("320.00"))
        XCTAssertTrue(text.contains("THB"))
        XCTAssertTrue(text.contains("Fictional café, \"\"Blue\"\"\nPier"))
        XCTAssertTrue(text.contains("\"\t \t=2+2\""))
        XCTAssertTrue(text.contains("-35.00"))
        XCTAssertFalse(text.contains("Demo excluded"))
        XCTAssertFalse(text.contains("Fictional deleted"))

        settings.csvStyle = .italianExcel
        let italian = try TransactionCSVWriter.encode(selection, options: settings)
        XCTAssertTrue(italian.starts(with: Data([0xEF, 0xBB, 0xBF])))
        XCTAssertTrue(String(decoding: italian, as: UTF8.self).contains("12,34"))
        XCTAssertTrue(String(decoding: italian, as: UTF8.self).contains(";"))
    }

    func testInclusiveDSTDatesCombinedFiltersAndActivityIntersection() throws {
        var first = item("00000000-0000-4000-8000-000000000101", kind: .expense,
                         cents: 100, merchant: "Fictional early", at: "2026-03-28T23:30:00Z")
        first.account = "A"
        first.category = "Food"
        first.tripID = "fictional-trip-a"
        var second = item("00000000-0000-4000-8000-000000000102", kind: .expense,
                          cents: 200, merchant: "Fictional late", at: "2026-03-29T01:30:00Z")
        second.account = "B"
        second.category = ""
        second.tripID = "fictional-trip-b"
        let outside = item("00000000-0000-4000-8000-000000000103", kind: .income,
                           cents: 300, merchant: "Fictional outside", at: "2026-03-29T22:30:00Z")
        let snapshot = TransactionExportSnapshot(transactions: [outside, second, first],
            accountNames: [:], categoryNames: [:], tripNames: [:], historicalOriginals: [:])
        var filter = TransactionExportFilter()
        filter.datePreset = .custom
        filter.customStart = LocalDay(isoString: "2026-03-29")
        filter.customEnd = LocalDay(isoString: "2026-03-29")
        filter.accountKeys = ["label:A", "label:B"]
        filter.categoryKeys = ["label:Food", "uncategorized"]
        filter.kindKeys = ["expense"]
        filter.currencyKeys = ["EUR"]
        filter.tripKeys = ["fictional-trip-a", "fictional-trip-b"]
        let selected = try snapshot.select(filter: filter, options: options)
        XCTAssertEqual(selected.rows.map(\.item.id), [first.id, second.id])
        filter.tripKeys = ["fictional-trip-b"]
        XCTAssertEqual(try snapshot.select(filter: filter, options: options).rows.map(\.item.id), [second.id])
        filter.tripKeys = nil
        let scoped = try snapshot.select(filter: filter,
            activityFilter: TransactionFilter(query: "late", kind: .expense), options: options)
        XCTAssertEqual(scoped.rows.map(\.item.id), [second.id])
        filter.accountKeys = ["label:A"]
        let empty = try snapshot.select(filter: filter,
            activityFilter: TransactionFilter(query: "late"), options: options)
        XCTAssertTrue(empty.rows.isEmpty)
        filter.customStart = LocalDay(isoString: "2026-03-30")
        XCTAssertThrowsError(try snapshot.select(filter: filter, options: options))
    }

    func testXLSXPackageSummaryAndEmptyExport() throws {
        let selected = try fixture().select(filter: .init(), options: options)
        var settings = options
        settings.format = .xlsx
        settings.includeSummary = true
        let file = try TransactionXLSXWriter.encode(selected, options: settings)
        XCTAssertTrue(file.starts(with: Data([0x50, 0x4B, 0x03, 0x04])))
        XCTAssertTrue(file.count > 4_000)
        let empty = try fixture().select(filter: TransactionExportFilter(query: "no such fictional merchant"),
                                          options: settings)
        XCTAssertEqual(empty.rows.count, 0)
        XCTAssertFalse(try TransactionXLSXWriter.encode(empty, options: settings).isEmpty)
        XCTAssertEqual(try TransactionCSVWriter.encode(empty, options: settings).split(separator: 10).count, 1)
    }

    func testFormulaPrefixesDatePresetsArchivedIdentityAndMoneyLimit() throws {
        let unsafe = ["=2+2", "+SUM(A1:A2)", "-7+4", "@IMPORT", " \r\n=42"]
        let rows = unsafe.enumerated().map { index, value in
            item(String(format: "00000000-0000-4000-8002-%012d", index + 1),
                 kind: .expense, cents: 100, merchant: value)
        }
        let account = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!
        let category = UUID(uuidString: "B0000000-0000-4000-8000-000000000001")!
        var archived = rows[0]
        archived.id = UUID(uuidString: "00000000-0000-4000-8002-000000000006")!
        archived.merchant = "Fictional archived label"
        archived.accountID = account
        archived.categoryID = category
        archived.account = "Old account name"
        archived.category = "Old category name"
        let snapshot = TransactionExportSnapshot(transactions: rows + [archived],
            accountNames: [account:"Renamed archived account"],
            categoryNames: [category:"Renamed archived category"],
            tripNames: [:], historicalOriginals: [:])
        var filter = TransactionExportFilter()
        filter.datePreset = .currentMonth
        let current = try snapshot.select(filter: filter, options: options,
                                          now: date("2026-10-15T00:00:00Z"))
        XCTAssertEqual(current.rows.count, 6)
        let text = String(decoding: try TransactionCSVWriter.encode(current, options: options), as: UTF8.self)
        for value in unsafe {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            XCTAssertTrue(text.contains("\"\t" + escaped + "\""))
        }
        XCTAssertTrue(snapshot.categoryChoices.contains { $0.id == "uncategorized" })

        filter.accountKeys = ["id:\(account.uuidString)"]
        filter.categoryKeys = ["id:\(category.uuidString)"]
        let chosen = try snapshot.select(filter: filter, options: options,
                                         now: date("2026-10-15T00:00:00Z"))
        XCTAssertEqual(chosen.rows.count, 1)
        XCTAssertEqual(chosen.rows[0].account, "Renamed archived account")
        XCTAssertEqual(chosen.rows[0].category, "Renamed archived category")
        filter.datePreset = .previousMonth
        XCTAssertEqual(try snapshot.select(filter: filter, options: options,
                                           now: date("2026-10-15T00:00:00Z")).rows.count, 0)
        filter.datePreset = .currentYear
        XCTAssertEqual(try snapshot.select(filter: filter, options: options,
                                           now: date("2026-10-15T00:00:00Z")).rows.count, 1)
        filter.datePreset = .previousYear
        XCTAssertEqual(try snapshot.select(filter: filter, options: options,
                                           now: date("2026-10-15T00:00:00Z")).rows.count, 0)
        XCTAssertEqual(TransactionExportMoney.decimal(Int64.min), "-92233720368547758.08")
        XCTAssertThrowsError(try TransactionExportMoney.xlsxDecimal(1_000_000_000_000_000))
    }

    func testReadOnlySnapshotPreservesDatabaseAndHistoricalSource() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("ledger.sqlite")
        let writer = try SQLiteDatabase(url: url)
        try writer.seedDemoIfNeeded()
        var transaction = item("00000000-0000-4000-8000-000000000201", kind: .expense,
                               cents: 875, merchant: "Fictional imported")
        transaction.sourceMovementID = "fictional-source-201"
        transaction.sourceSheet = "Fictional sheet"
        transaction.sourceRow = 201
        _ = try writer.save(transaction)
        try writer.execute("INSERT INTO historical_imported_movements VALUES ('fictional-source-201','\(transaction.id.uuidString)','fictional-fingerprint','Fictional sheet',201,'{\"amount_minor\":32000,\"currency\":\"THB\",\"eur_minor\":800}')")
        let before = try writer.backupTables()
        let reader = try SQLiteDatabase(readOnlyURL: url)
        let snapshot = try reader.transactionExportSnapshot()
        let after = try writer.backupTables()
        XCTAssertEqual(after, before)
        XCTAssertEqual(snapshot.exportableTransactions.count, 1)
        XCTAssertEqual(snapshot.historicalOriginals[transaction.id]?.amountMinor, 32_000)
        XCTAssertEqual(snapshot.historicalOriginals[transaction.id]?.currency, "THB")
    }

    func testLargerSyntheticHistoryAndIndependentFixtureWhenRequested() throws {
        let base = fixture()
        var many: [Transaction] = []
        for index in 0..<2_000 {
            many.append(item(String(format: "00000000-0000-4000-8001-%012d", index + 1),
                             kind: .expense, cents: Int64(100 + index), merchant: "Fictional #\(index)"))
        }
        let snapshot = TransactionExportSnapshot(transactions: base.transactions + many,
            accountNames: base.accountNames, categoryNames: base.categoryNames,
            tripNames: base.tripNames, historicalOriginals: base.historicalOriginals)
        let selected = try snapshot.select(filter: .init(), options: options)
        XCTAssertEqual(selected.rows.count, 2_009)
        XCTAssertFalse(try TransactionCSVWriter.encode(selected, options: options).isEmpty)
        XCTAssertFalse(try TransactionXLSXWriter.encode(selected, options: options).isEmpty)

        if let path = ProcessInfo.processInfo.environment["EASYTRACK_EXPORT_ARTIFACT_DIR"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var detailed = options
            detailed.columns = .detailed
            detailed.includeTechnicalIDs = true
            detailed.includeSummary = true
            let small = try base.select(filter: .init(), options: detailed)
            try TransactionCSVWriter.encode(small, options: detailed)
                .write(to: directory.appendingPathComponent("fictional-transactions.csv"))
            try TransactionXLSXWriter.encode(small, options: detailed)
                .write(to: directory.appendingPathComponent("fictional-transactions.xlsx"))
        }
    }
}
