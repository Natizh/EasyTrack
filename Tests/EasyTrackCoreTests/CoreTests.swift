import XCTest
@testable import EasyTrackCore

final class CoreTests: XCTestCase {
    func testMoneyRejectsExcessPrecisionAndUsesMinorUnits() {
        XCTAssertEqual(Money.parseEUR("12,34"), 1234)
        XCTAssertEqual(Money.parseEUR("0.01"), 1)
        XCTAssertNil(Money.parseEUR("12.345"))
        XCTAssertNil(Money.parseEUR("-1"))
        XCTAssertNil(Money.parseEUR("999999999999999999999"))
    }

    func testLocalizedEURInputAndInlineValidation() {
        let italian = Locale(identifier: "it_IT")
        XCTAssertEqual(Money.editString(1_234, locale: italian), "12,34")
        let display = Money.format(1_234, locale: italian)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
        XCTAssertEqual(display, "12,34 €")
        XCTAssertEqual(Money.parseMinor("12,34"), 1_234)
        XCTAssertEqual(Money.parseMinor("12.34"), 1_234)
        XCTAssertEqual(Money.parseMinor("1.234,56 €"), 123_456)
        XCTAssertEqual(Money.parseMinor("1,234.56"), 123_456)
        XCTAssertNil(Money.parseMinor("12,3456"))
        XCTAssertNil(Money.parseMinor("12abc"))
        XCTAssertEqual(Money.validatedPositiveAmount(""), .failure(.empty))
        XCTAssertEqual(Money.validatedPositiveAmount("-1,00"), .failure(.negative))
        XCTAssertEqual(Money.validatedPositiveAmount("0,00"), .failure(.zero))
        XCTAssertEqual(Money.validatedPositiveAmount("12,3456"), .failure(.malformed))
    }

    func testEURAmountEditPreservesSeparatePersonalShare() {
        var item = Transaction(id: UUID(), kind: .expense, amountMinor: 1_234,
                               currency: "EUR", merchant: "Synthetic", account: "Synthetic",
                               category: "Synthetic", note: "", occurredAt: .now,
                               updatedAt: .now, deletedAt: nil, isDemo: false,
                               revision: 1, sourceEventID: nil)
        item.eurMinor = 1_234
        item.personalExpenseEURMinor = 1_234
        XCTAssertEqual(TransactionEditPolicy.values(original: item, kind: .expense, newEURMinor: 1_875).personal, 1_875)
        item.personalExpenseEURMinor = 600
        XCTAssertTrue(TransactionEditPolicy.hasSeparatePersonalShare(item))
        XCTAssertEqual(TransactionEditPolicy.values(original: item, kind: .expense, newEURMinor: 1_875).personal, 600)
        item.kind = .reimbursement
        item.personalExpenseEURMinor = -1_234
        XCTAssertEqual(TransactionEditPolicy.values(original: item, kind: .reimbursement, newEURMinor: 1_875).personal, -1_875)
        XCTAssertEqual(TransactionEditPolicy.values(original: item, kind: .expense, newEURMinor: 1_875).personal, 1_875)
    }

    func testNotificationFingerprintIsStableForSameOccurrence() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = NotificationEvent.make(sourceApp: "Wallet", title: "Paid", subtitle: "",
                                           message: "€2.00", receivedAt: date)!
        let repeatEvent = NotificationEvent.make(sourceApp: "Wallet", title: "Paid", subtitle: "",
                                                 message: "€2.00", receivedAt: date)!
        let later = NotificationEvent.make(sourceApp: "Wallet", title: "Paid", subtitle: "",
                                           message: "€2.00", receivedAt: date.addingTimeInterval(1))!
        XCTAssertEqual(first.fingerprint, repeatEvent.fingerprint)
        XCTAssertNotEqual(first.fingerprint, later.fingerprint)
        XCTAssertNil(NotificationEvent.make(sourceApp: "", title: "Paid", subtitle: "", message: "", receivedAt: nil))
    }
}
