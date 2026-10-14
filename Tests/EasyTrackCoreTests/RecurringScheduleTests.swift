import XCTest
@testable import EasyTrackCore

final class RecurringScheduleTests: XCTestCase {
    private let rome = TimeZone(identifier: "Europe/Rome")!

    private func rule(start: String, frequency: RecurringFrequency = .monthly,
                      type: RecurringType = .subscription) -> RecurringRule {
        RecurringRule(id: UUID(uuidString: "E2F5F154-47D3-43B9-B36B-5302155A8401")!,
                      name: "Fictional plan", type: type, amountMinor: 1_250,
                      accountID: UUID(), categoryID: nil, startDay: LocalDay(isoString: start)!,
                      frequency: frequency, nextIndex: 0, endDay: nil,
                      timeZoneIdentifier: rome.identifier, isActive: true, note: "",
                      createdAt: .now, updatedAt: .now, archivedAt: nil, revision: 0)
    }

    private func date(_ value: String) -> Date {
        LocalDay(isoString: value)!.noon(in: rome)!
    }

    func testMonthlyMonthEndAndYearBoundaryDoNotDrift() throws {
        let january = rule(start: "2026-01-31")
        XCTAssertEqual(try (0...4).map { try RecurringSchedule.day(for: january, index: $0).isoString },
                       ["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30", "2026-05-31"])
        let december = rule(start: "2026-12-31")
        XCTAssertEqual(try RecurringSchedule.day(for: december, index: 1).isoString, "2027-01-31")
        XCTAssertEqual(try RecurringSchedule.day(for: december, index: 2).isoString, "2027-02-28")
        XCTAssertNil(LocalDay(isoString: "2026-02-30"))
    }

    func testYearlyLeapDayAndPACType() throws {
        let leap = rule(start: "2024-02-29", frequency: .yearly, type: .pacInvestment)
        XCTAssertEqual(try (0...4).map { try RecurringSchedule.day(for: leap, index: $0).isoString },
                       ["2024-02-29", "2025-02-28", "2026-02-28", "2027-02-28", "2028-02-29"])
        XCTAssertEqual(leap.type.transactionKind, .pacInvestment)
    }

    func testWeeklyEuropeRomeDSTKeepsLocalDayAndStableID() throws {
        let spring = rule(start: "2026-03-22", frequency: .weekly)
        let next = try RecurringSchedule.day(for: spring, index: 1)
        XCTAssertEqual(next.isoString, "2026-03-29")
        XCTAssertEqual(try RecurringSchedule.day(for: spring, index: 2).isoString, "2026-04-05")
        let gap = next.noon(in: rome)!.timeIntervalSince(spring.startDay.noon(in: rome)!)
        XCTAssertEqual(gap, 7 * 86_400 - 3_600)
        let autumn = rule(start: "2026-10-18", frequency: .weekly)
        let fall = try RecurringSchedule.day(for: autumn, index: 1)
        XCTAssertEqual(fall.isoString, "2026-10-25")
        XCTAssertEqual(fall.noon(in: rome)!.timeIntervalSince(autumn.startDay.noon(in: rome)!),
                       7 * 86_400 + 3_600)
        XCTAssertEqual(RecurringSchedule.occurrenceID(ruleID: spring.id, day: next),
                       RecurringSchedule.occurrenceID(ruleID: spring.id, day: next))
    }

    func testCatchUpProjectionPauseAndEndDate() throws {
        var monthly = rule(start: "2026-01-31")
        XCTAssertEqual(try RecurringSchedule.due(for: monthly, now: date("2026-03-15")).map(\.day.isoString),
                       ["2026-01-31", "2026-02-28"])
        monthly.nextIndex = 2
        XCTAssertEqual(try RecurringSchedule.upcoming(for: monthly, now: date("2026-03-01"))
            .map(\.day.isoString), ["2026-03-31"])
        monthly.endDay = LocalDay(isoString: "2026-04-30")
        monthly.nextIndex = 4
        XCTAssertNil(try RecurringSchedule.nextDay(for: monthly))
        monthly.isActive = false
        XCTAssertTrue(try RecurringSchedule.due(for: monthly, now: date("2026-12-31")).isEmpty)
        XCTAssertTrue(try RecurringSchedule.upcoming(for: monthly, now: date("2026-03-01")).isEmpty)
    }
}
