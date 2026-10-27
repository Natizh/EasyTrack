import XCTest
@testable import EasyTrackCore

final class ReceiptOCRTests: XCTestCase {
    private let zone = TimeZone(identifier: "Europe/Rome")!

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    func testClearItalianReceiptFindsMerchantDateAndFinalPaidTotal() throws {
        let extraction = ReceiptOCRParser.extract(lines: [
            .init(text: "Supermercato Fantasia", confidence: 0.99),
            .init(text: "Via Fittizia 10", confidence: 0.96),
            .init(text: "27/10/2026", confidence: 0.94),
            .init(text: "SUBTOTALE 12,00", confidence: 0.97),
            .init(text: "IVA 2,50", confidence: 0.96),
            .init(text: "TOTALE € 14,50", confidence: 0.99),
            .init(text: "CONTANTI 20,00", confidence: 0.92),
            .init(text: "RESTO 5,50", confidence: 0.91)
        ], calendar: calendar())
        XCTAssertEqual(extraction.merchantCandidates.first, "Supermercato Fantasia")
        XCTAssertEqual(extraction.amountCandidates.map(\.amountMinor), [1_450])
        XCTAssertEqual(extraction.amountCandidates.first?.currency, "EUR")
        XCTAssertEqual(extraction.recommendedAmountID, extraction.amountCandidates.first?.id)
        let date = try XCTUnwrap(extraction.dateCandidates.first?.date)
        XCTAssertEqual(calendar().dateComponents([.year, .month, .day], from: date),
                       DateComponents(year: 2026, month: 10, day: 27))
    }

    func testAmbiguousTotalsRequireChoiceAndPreserveSourceText() {
        let extraction = ReceiptOCRParser.extract(lines: [
            .init(text: "Cafe Example", confidence: 0.95),
            .init(text: "TOTALE 12,00 EUR", confidence: 0.97),
            .init(text: "PAGATO CARTA 10,00 EUR", confidence: 0.96)
        ])
        XCTAssertEqual(extraction.amountCandidates.count, 2)
        XCTAssertNil(extraction.recommendedAmountID)
        XCTAssertEqual(Set(extraction.amountCandidates.map(\.sourceText)),
                       Set(["TOTALE 12,00 EUR", "PAGATO CARTA 10,00 EUR"]))
    }

    func testCommaThousandsNonEURMissingTotalAndMissingDateStayExplicit() {
        let comma = ReceiptOCRParser.extract(lines: [
            .init(text: "Negozio Fittizio", confidence: 0.9),
            .init(text: "TOTAL EUR 1.234,56", confidence: 0.98)
        ])
        XCTAssertEqual(comma.amountCandidates.first?.amountMinor, 123_456)
        XCTAssertTrue(comma.dateCandidates.isEmpty)

        let dollars = ReceiptOCRParser.extract(lines: [
            .init(text: "Example Store", confidence: 0.9),
            .init(text: "TOTAL $ 20.00", confidence: 0.98)
        ])
        XCTAssertEqual(dollars.amountCandidates.first?.currency, "USD")

        let missing = ReceiptOCRParser.extract(lines: [
            .init(text: "Example Store", confidence: 0.9),
            .init(text: "Thank you", confidence: 0.8)
        ])
        XCTAssertTrue(missing.amountCandidates.isEmpty)
        XCTAssertNil(missing.recommendedAmountID)
        XCTAssertTrue(missing.dateCandidates.isEmpty)
    }

    func testLineOrderFixtureAndDuplicateAwarenessDoNotMutateLedger() {
        let lines = [
            ReceiptOCRLine(text: "Rotated Fixture Shop", confidence: 0.95),
            ReceiptOCRLine(text: "2026-10-27", confidence: 0.9),
            ReceiptOCRLine(text: "TOTAL 9,99 EUR", confidence: 0.98)
        ]
        let extraction = ReceiptOCRParser.extract(lines: lines, calendar: calendar())
        XCTAssertEqual(extraction.merchantCandidates.first, "Rotated Fixture Shop")
        let amount = extraction.amountCandidates.first?.amountMinor
        let date = extraction.dateCandidates.first?.date ?? .now
        let draft = ReceiptTransactionDraft(merchant: "Rotated Fixture Shop", occurredAt: date,
                                            amountMinor: amount, currency: "EUR", dateWasDetected: true)
        let existing = Transaction(id: UUID(), kind: .expense, amountMinor: 999, currency: "EUR",
            merchant: "Rotated Fixture Shop", account: "Fictional", category: "", note: "",
            occurredAt: date, updatedAt: .now, deletedAt: nil, isDemo: false, revision: 1,
            sourceEventID: nil)
        let ledger = [existing]
        XCTAssertEqual(ReceiptDuplicateDetector.possibleMatches(for: draft, transactions: ledger).map(\.id),
                       [existing.id])
        XCTAssertEqual(ledger, [existing])
    }

    func testReceiptParsingAddsNoBackupTableOrPersistentImage() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyTrack-receipt-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try SQLiteDatabase(url: folder.appendingPathComponent("ledger.sqlite"))
        try database.seedDemoIfNeeded()
        _ = ReceiptOCRParser.extract(lines: [
            .init(text: "Synthetic Shop", confidence: 1),
            .init(text: "TOTAL 5,00 EUR", confidence: 1)
        ])
        let backup = try database.exportBackup()
        XCTAssertFalse(backup.tables.contains { $0.name.localizedCaseInsensitiveContains("receipt") ||
            $0.columns.contains(where: { $0.localizedCaseInsensitiveContains("image") }) })
        XCTAssertEqual(try database.transactions().filter { !$0.isDemo }.count, 0)
    }
}
