import Foundation
import XCTest
@testable import EasyTrackCore

final class LocalizationTests: XCTestCase {
    func testFirstLaunchLanguageIsItalianForAnySystemLocale() {
        XCTAssertEqual(AppLanguage.resolved(nil), .italian)
        XCTAssertEqual(AppLanguage.resolved("it"), .italian)
        XCTAssertEqual(AppLanguage.resolved("en"), .english)
        XCTAssertEqual(AppLanguage.resolved("fr"), .italian)
        XCTAssertEqual(AppLanguage.italian.locale.language.languageCode?.identifier, "it")
        XCTAssertEqual(AppLanguage.english.locale.language.languageCode?.identifier, "en")
    }

    func testLanguageDoesNotChangeMoneyOrStableMovementCodes() {
        XCTAssertEqual(Money.parseMinor("12,34"), 1_234)
        XCTAssertEqual(Money.parseMinor("12.34"), 1_234)
        XCTAssertEqual(TransactionKind.reimbursement.rawValue, "reimbursement")
        XCTAssertEqual(TransactionKind.pacInvestment.rawValue, "pacInvestment")
        XCTAssertNotEqual(Money.format(1_234, locale: AppLanguage.italian.locale),
                          Money.format(1_234, locale: AppLanguage.english.locale))
    }
}
