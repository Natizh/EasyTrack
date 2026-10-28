import XCTest
@testable import EasyTrackCore

final class VoiceEntryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testItalianExpenseWithCentsMerchantAndYesterday() {
        let draft = VoiceEntryParser.parse("Ho speso dodici euro e cinquanta al supermercato ieri",
                                           locale: Locale(identifier: "it-IT"), now: now)
        XCTAssertEqual(draft.kind, .expense)
        XCTAssertEqual(draft.amountMinor, 1_250)
        XCTAssertEqual(draft.currency, "EUR")
        XCTAssertEqual(draft.merchant, "supermercato")
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: draft.occurredAt!, to: now).day, 1)
    }

    func testEnglishDollarsAndItalianIncomeYuan() {
        let english = VoiceEntryParser.parse("Spent twenty three dollars at the bookstore today",
                                             locale: Locale(identifier: "en-US"), now: now)
        XCTAssertEqual(english.kind, .expense)
        XCTAssertEqual(english.amountMinor, 2_300)
        XCTAssertEqual(english.currency, "USD")
        XCTAssertEqual(english.merchant, "the bookstore")
        let income = VoiceEntryParser.parse("Ho ricevuto cinquanta euro",
                                            locale: Locale(identifier: "it-IT"), now: now)
        XCTAssertEqual(income.kind, .income)
        XCTAssertEqual(income.amountMinor, 5_000)
        let yuan = VoiceEntryParser.parse("Ho pagato cento yuan", locale: Locale(identifier: "it-IT"))
        XCTAssertEqual(yuan.currency, "CNY")
        XCTAssertEqual(yuan.amountMinor, 10_000)
    }

    func testEmptyAndAmbiguousCommandsDoNotInventFields() {
        XCTAssertFalse(VoiceEntryParser.parse("", locale: .current).issues.isEmpty)
        let ambiguous = VoiceEntryParser.parse("supermercato domani", locale: Locale(identifier: "it-IT"))
        XCTAssertNil(ambiguous.amountMinor)
        XCTAssertNil(ambiguous.currency)
        XCTAssertNil(ambiguous.kind)
        XCTAssertFalse(ambiguous.issues.isEmpty)
    }
}
