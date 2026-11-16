import XCTest
@testable import EasyTrackCore

final class NotificationParserTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ message: String, source: String = "Northstar Pay (fictional)",
                       title: String = "Card purchase", at date: Date? = nil) -> NotificationEvent {
        NotificationEvent.make(sourceApp: source, title: title, subtitle: "",
                               message: message, receivedAt: date ?? baseDate,
                               capturedAt: date ?? baseDate)!
    }

    private func configured(_ sample: NotificationEvent) -> ParserRuleConfig {
        NotificationParser.suggest(for: sample)
    }

    private func preview(_ sample: NotificationEvent, config: ParserRuleConfig) -> ParserPreview {
        NotificationParser.preview(sample, config: config, mappedAccount: "Fictional checking")
    }

    func testEURExtractionAndMerchantAnchors() {
        let before = event("Paid €1.234,56 at Cedar Books")
        let after = event("Paid 1,234.56 € at Cedar Books")
        let period = event("Paid EUR 12.34 at Cedar Books")
        for sample in [before, after, period] {
            let preview = preview(sample, config: configured(sample))
            XCTAssertTrue(preview.ready, preview.error ?? "")
            XCTAssertEqual(preview.merchant, "Cedar Books")
        }
        XCTAssertEqual(NotificationParser.detectedAmounts(in: before.message).first?.cents, 123_456)
        XCTAssertEqual(NotificationParser.detectedAmounts(in: after.message).first?.cents, 123_456)
        XCTAssertEqual(NotificationParser.detectedAmounts(in: period.message).first?.cents, 1_234)

        var anchor = configured(before)
        anchor.amountPrefix = "Paid "
        anchor.amountSuffix = " at "
        XCTAssertTrue(preview(before, config: anchor).ready)
        anchor.amountSuffix = " from "
        XCTAssertNil(preview(before, config: anchor).amount)

        let harbor = event("Moor Cafe | 8.75 EUR received", source: "Harbor Wallet (fictional)",
                           title: "Wallet receipt")
        var merchant = configured(harbor)
        merchant.merchantMode = .betweenAnchors
        merchant.merchantPrefix = ""
        merchant.merchantSuffix = " |"
        merchant.category = "Coffee"
        XCTAssertEqual(preview(harbor, config: merchant).merchant, "Moor Cafe")
        merchant.merchantMode = .wholeLine
        XCTAssertEqual(preview(harbor, config: merchant).merchant,
                       "Moor Cafe | 8.75 EUR received")
    }

    func testMissingMalformedFieldsAndMatchConditions() {
        let sample = event("Paid €12,34 at Cedar Books")
        var config = configured(sample)
        XCTAssertTrue(preview(sample, config: config).ready)
        XCTAssertNil(preview(event("Paid €12,345 at Cedar Books"), config: config).amount)
        XCTAssertNil(preview(event("Paid at Cedar Books"), config: config).amount)
        XCTAssertFalse(preview(event("Received €12,34 at Cedar Books", title: "Transfer"),
                                                  config: config).conditionMatched)
        config.conditionField = .message
        config.conditionMode = .beginsWith
        config.conditionText = "Paid"
        XCTAssertTrue(preview(sample, config: config).conditionMatched)
        config.conditionMode = .endsWith
        config.conditionText = "Books"
        XCTAssertTrue(preview(sample, config: config).conditionMatched)
        config.conditionMode = .contains
        config.conditionText = "Missing"
        XCTAssertFalse(preview(sample, config: config).conditionMatched)

        config.conditionMode = .regularExpression
        config.conditionText = #"Paid.*Books"#
        XCTAssertTrue(preview(sample, config: config).conditionMatched)
        XCTAssertThrowsError(try NotificationParser.safeRegex("(a+)+$"))
        XCTAssertThrowsError(try NotificationParser.safeRegex("["))
        XCTAssertThrowsError(try NotificationParser.safeRegex(String(repeating: "a", count: 97)))
    }

    func testNormalizedExactAndSemanticFingerprints() {
        let first = event("Paid €12,34 at Cedar Books")
        let whitespace = event("Paid   €12,34\n at Cedar Books")
        XCTAssertEqual(NotificationParser.exactFingerprint(first), NotificationParser.exactFingerprint(whitespace))
        XCTAssertNotEqual(NotificationParser.exactFingerprint(first),
                          NotificationParser.exactFingerprint(event("Paid €13,34 at Cedar Books")))
        XCTAssertEqual(NotificationParser.semanticFingerprint(amountMinor: 1_234, merchant: "Cedar  Books",
                                                               account: "Fictional checking"),
                       NotificationParser.semanticFingerprint(amountMinor: 1_234, merchant: "cedar books",
                                                               account: "FICTIONAL CHECKING"))
        XCTAssertNotEqual(NotificationParser.semanticFingerprint(amountMinor: 1_234, merchant: "Cedar Books",
                                                                  account: "Fictional checking"),
                          NotificationParser.semanticFingerprint(amountMinor: 1_235, merchant: "Cedar Books",
                                                                  account: "Fictional checking"))
    }

    func testDistinctivePhraseSignedAmountsAndMultilineText() throws {
        let outgoing = event("Hai pagato −€1.234,56 presso Cedar Books\nCarta virtuale", title: "Wallet update")
        let incoming = event("Hai ricevuto +1,234.56 EUR da Cedar Books\nSaldo aggiornato", title: "Wallet update")
        var expense = configured(outgoing)
        expense.kind = .expense
        var income = configured(incoming)
        income.kind = .income
        XCTAssertEqual(expense.conditionText, "Hai pagato")
        XCTAssertEqual(income.conditionText, "Hai ricevuto")
        XCTAssertEqual(expense.requiredAmountSign, .negative)
        XCTAssertEqual(income.requiredAmountSign, .positive)
        XCTAssertEqual(preview(outgoing, config: expense).amount?.cents, 123_456)
        XCTAssertEqual(preview(incoming, config: income).amount?.cents, 123_456)
        XCTAssertFalse(preview(incoming, config: expense).ready)
        XCTAssertFalse(preview(outgoing, config: income).ready)

        let encodedLegacy = try JSONEncoder().encode(expense)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedLegacy) as? [String: Any])
        object.removeValue(forKey: "requiredAmountSign")
        let legacy = try JSONDecoder().decode(ParserRuleConfig.self,
            from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.requiredAmountSign)
        XCTAssertEqual(legacy.conditionText, expense.conditionText)
    }

    func testVariablePrefixSuffixAndMerchantNames() {
        let first = event("Card 0000: paid €7,50 to Maple Cafe\nAvailable balance updated",
                          title: "Wallet update")
        let second = event("Card 9999: paid 8.50 EUR to River Books\nReceipt ready",
                           title: "Wallet update")
        var config = configured(first)
        config.conditionField = .message
        config.conditionMode = .contains
        config.conditionText = "paid"
        config.merchantMode = .betweenAnchors
        config.merchantPrefix = " to "
        config.merchantSuffix = "\n"
        XCTAssertEqual(preview(first, config: config).merchant, "Maple Cafe")
        XCTAssertEqual(preview(second, config: config).merchant, "River Books")
        XCTAssertEqual(preview(second, config: config).amount?.cents, 850)
        XCTAssertFalse(preview(event("Card 9999: received 8.50 EUR from River Books",
                                     title: "Wallet update"), config: config).ready)
    }

    func testSafetyFilterRejectsOTPAndPromotionWithoutRejectingPayment() {
        let payment = event("Paid €12,34 at Cedar Books")
        XCTAssertNil(NotificationSafetyFilter.rejectionReason(for: payment))

        let otp = event("Your OTP code is 482913. Do not share this code.",
                        title: "Verification code")
        XCTAssertTrue(NotificationSafetyFilter.rejectionReason(for: otp)?.contains("OTP") == true)

        let promotion = event("Get €10 cashback this weekend. Open the app to discover the offer.",
                              title: "Special offer")
        XCTAssertTrue(NotificationSafetyFilter.rejectionReason(for: promotion)?.contains("Promotional") == true)
    }
}
