import Foundation
import XCTest
@testable import EasyTrackCore

final class FinancialAnalyticsTests: XCTestCase {
    func testFinancialMonthNavigationCrossesYearsAndUsesLeapDSTBoundaries() throws {
        let december = try XCTUnwrap(FinancialMonth(year: 2025, month: 12))
        XCTAssertEqual(december.adding(months: 1), FinancialMonth(year: 2026, month: 1))
        XCTAssertEqual(december.adding(months: -12), FinancialMonth(year: 2024, month: 12))
        XCTAssertEqual(FinancialMonth(key: "2026-02")?.id, "2026-02")
        XCTAssertNil(FinancialMonth(key: "2026-13"))

        let zone = TimeZone(identifier: "Europe/Rome")!
        let leap = try FinancialPeriod.month(year: 2024, month: 2)
            .selection(now: LocalDay(isoString: "2024-03-15")!.noon(in: zone)!, timeZone: zone)
        XCTAssertEqual(try leap.requested.dayCount(timeZone: zone), 29)
        let dst = try FinancialPeriod.month(year: 2026, month: 3)
            .selection(now: LocalDay(isoString: "2026-04-15")!.noon(in: zone)!, timeZone: zone)
        XCTAssertEqual(try dst.requested.dayCount(timeZone: zone), 31)
    }
    private let zone = TimeZone(identifier: "Europe/Rome")!

    private func day(_ value: String) -> LocalDay {
        LocalDay(isoString: value)!
    }

    private func date(_ value: String) -> Date {
        day(value).noon(in: zone)!
    }

    private func item(_ suffix: Int, kind: TransactionKind, cents: Int64, day: String,
                      category: String = "", categoryID: UUID? = nil) -> Transaction {
        Transaction(id: UUID(uuidString: String(format: "00000000-0000-4003-8000-%012d", suffix))!,
                    kind: kind, amountMinor: cents, currency: "EUR",
                    merchant: "Fictional movement \(suffix)", account: "Fictional checking",
                    category: category, note: "", occurredAt: date(day), updatedAt: date(day),
                    deletedAt: nil, isDemo: false, revision: 1, sourceEventID: nil,
                    accountID: UUID(uuidString: "A0000000-0000-4000-8000-000000000001"),
                    categoryID: categoryID)
    }

    func testNetGrossIncomePACCategoriesRefundsAndMissingConversionsStayDistinct() throws {
        let foodID = UUID(uuidString: "B0000000-0000-4000-8000-000000000001")!
        let travelID = UUID(uuidString: "B0000000-0000-4000-8000-000000000002")!
        var foodExpense = item(1, kind: .expense, cents: 10_000, day: "2026-10-02",
                               category: "Food", categoryID: foodID)
        foodExpense.eurMinor = 10_000
        foodExpense.personalExpenseEURMinor = 6_000
        var travelExpense = item(2, kind: .expense, cents: 2_000, day: "2026-10-03",
                                 category: "Travel", categoryID: travelID)
        travelExpense.eurMinor = 2_000
        travelExpense.personalExpenseEURMinor = 2_000
        var foodRefund = item(3, kind: .reimbursement, cents: 7_000, day: "2026-10-04",
                              category: "Food", categoryID: foodID)
        foodRefund.eurMinor = 7_000
        foodRefund.personalExpenseEURMinor = -7_000
        var unallocatedRefund = item(4, kind: .reimbursement, cents: 500, day: "2026-10-05")
        unallocatedRefund.eurMinor = 500
        unallocatedRefund.personalExpenseEURMinor = -500
        var income = item(5, kind: .income, cents: 50_000, day: "2026-10-06")
        income.eurMinor = 50_000
        var pac = item(6, kind: .pacInvestment, cents: 3_000, day: "2026-10-07")
        pac.eurMinor = 3_000
        var foreignExpense = item(7, kind: .expense, cents: 80_000, day: "2026-10-08",
                                  category: "Travel", categoryID: travelID)
        foreignExpense.currency = "CNY"
        var foreignIncome = item(8, kind: .income, cents: 9_000, day: "2026-10-09")
        foreignIncome.currency = "USD"
        var foreignPAC = item(9, kind: .pacInvestment, cents: 4_000, day: "2026-10-10")
        foreignPAC.currency = "GBP"

        let snapshot = try FinancialAnalytics.snapshot(
            transactions: [foodExpense, travelExpense, foodRefund, unallocatedRefund,
                           income, pac, foreignExpense, foreignIncome, foreignPAC],
            period: .month(year: 2026, month: 10),
            categoryNames: [foodID: "Food", travelID: "Travel"], zone: zone,
            now: date("2026-10-15")
        )

        XCTAssertEqual(snapshot.totals.personalNetExpensesEURMinor, 500)
        XCTAssertEqual(snapshot.totals.grossExpensesEURMinor, 12_000)
        XCTAssertEqual(snapshot.totals.incomeEURMinor, 57_500)
        XCTAssertEqual(snapshot.totals.cashNetEURMinor, 45_500)
        XCTAssertEqual(snapshot.totals.pacInvestedEURMinor, 3_000)
        XCTAssertEqual(snapshot.dailyAverage,
                       FinancialDailyAverage(personalNetExpensesEURMinor: 500, elapsedDayCount: 15))
        XCTAssertEqual(snapshot.monthlyTrend, [FinancialMonthlyAggregate(
            month: day("2026-10-01"), grossExpensesEURMinor: 12_000,
            incomeEURMinor: 57_500, pacInvestedEURMinor: 3_000)])
        XCTAssertEqual(snapshot.dailySpending.count, 15)
        XCTAssertEqual(snapshot.dailySpending.first { $0.day == day("2026-10-02") }?.personalNetExpensesEURMinor,
                       6_000)
        XCTAssertEqual(snapshot.dailySpending.first { $0.day == day("2026-10-04") }?.personalNetExpensesEURMinor,
                       -7_000)
        XCTAssertEqual(snapshot.dailySpending.first { $0.day == day("2026-10-11") }?.personalNetExpensesEURMinor,
                       0)
        XCTAssertEqual(snapshot.chartSelectionIndex.categories["id:\(foodID.uuidString)"],
                       [foodExpense.id, foodRefund.id])
        XCTAssertEqual(snapshot.chartSelectionIndex.unallocated, [unallocatedRefund.id])
        XCTAssertEqual(snapshot.chartSelectionIndex.monthlyExpenses[day("2026-10-01")],
                       [foodExpense.id, travelExpense.id])
        XCTAssertEqual(snapshot.chartSelectionIndex.dailySpending[day("2026-10-04")], [foodRefund.id])
        XCTAssertEqual(snapshot.categories.map(\.personalNetExpensesEURMinor), [2_000, -1_000])
        XCTAssertEqual(snapshot.positiveCategories.map(\.name), ["Travel"])
        XCTAssertEqual(snapshot.nonPositiveCategoryAdjustmentEURMinor, -1_000)
        XCTAssertEqual(snapshot.unallocatedPersonalAdjustmentEURMinor, -500)
        XCTAssertEqual(snapshot.categories.reduce(snapshot.unallocatedPersonalAdjustmentEURMinor) {
            $0 + $1.personalNetExpensesEURMinor
        }, snapshot.totals.personalNetExpensesEURMinor)
        XCTAssertEqual(snapshot.unconvertedTransactions.count, 3)
        XCTAssertEqual(snapshot.unconvertedTransactions.first { $0.currency == "CNY" }?.unavailableMetrics,
                       [.personalNetExpenses, .grossExpenses])
        XCTAssertEqual(snapshot.unconvertedTransactions.first { $0.currency == "USD" }?.unavailableMetrics,
                       [.income])
        XCTAssertEqual(snapshot.unconvertedTransactions.first { $0.currency == "GBP" }?.unavailableMetrics,
                       [.pacInvestment])
        XCTAssertNil(snapshot.comparison.personalNetExpensesChange)
    }

    func testChartSeriesSpanMonthsIncludeEmptyDaysAndKeepSignedPersonalAmounts() throws {
        var septemberExpense = item(10, kind: .expense, cents: 1_200, day: "2026-09-29", category: "Food")
        septemberExpense.eurMinor = 1_200
        septemberExpense.personalExpenseEURMinor = 1_000
        var octoberRefund = item(11, kind: .reimbursement, cents: 250, day: "2026-10-01")
        octoberRefund.eurMinor = 250
        octoberRefund.personalExpenseEURMinor = -250
        var octoberIncome = item(12, kind: .income, cents: 5_000, day: "2026-10-02")
        octoberIncome.eurMinor = 5_000
        var octoberPAC = item(13, kind: .pacInvestment, cents: 700, day: "2026-10-02")
        octoberPAC.eurMinor = 700

        let snapshot = try FinancialAnalytics.snapshot(
            transactions: [septemberExpense, octoberRefund, octoberIncome, octoberPAC],
            period: .custom(start: day("2026-09-29"), end: day("2026-10-02")),
            zone: zone, now: date("2026-10-10"))

        XCTAssertEqual(snapshot.monthlyTrend, [
            FinancialMonthlyAggregate(month: day("2026-09-01"), grossExpensesEURMinor: 1_200),
            FinancialMonthlyAggregate(month: day("2026-10-01"), incomeEURMinor: 5_250,
                                      pacInvestedEURMinor: 700)
        ])
        XCTAssertEqual(snapshot.dailySpending.map(\.personalNetExpensesEURMinor), [1_000, 0, -250, 0])
        XCTAssertEqual(snapshot.dailySpending.map(\.day),
                       [day("2026-09-29"), day("2026-09-30"), day("2026-10-01"), day("2026-10-02")])
        XCTAssertEqual(snapshot.unallocatedPersonalAdjustmentEURMinor, -250)
    }

    func testIncompleteCalendarPeriodsAndEquivalentComparisons() throws {
        let month = try FinancialPeriod.month(year: 2026, month: 10)
            .selection(now: date("2026-10-25"), timeZone: zone)
        XCTAssertEqual(month.effective, try LedgerDateInterval(start: day("2026-10-01"), end: day("2026-10-25")))
        XCTAssertEqual(month.comparison, try LedgerDateInterval(start: day("2026-09-01"), end: day("2026-09-25")))
        XCTAssertTrue(month.isIncomplete)

        let historicalMonth = try FinancialPeriod.month(year: 2026, month: 2)
            .selection(now: date("2026-10-25"), timeZone: zone)
        XCTAssertEqual(historicalMonth.effective,
                       try LedgerDateInterval(start: day("2026-02-01"), end: day("2026-02-28")))
        XCTAssertEqual(historicalMonth.comparison,
                       try LedgerDateInterval(start: day("2026-01-01"), end: day("2026-01-31")))

        let leapYear = try FinancialPeriod.year(2024)
            .selection(now: date("2024-02-29"), timeZone: zone)
        XCTAssertEqual(leapYear.comparison,
                       try LedgerDateInterval(start: day("2023-01-01"), end: day("2023-02-28")))

        let custom = try FinancialPeriod.custom(start: day("2026-03-29"), end: day("2026-03-31"))
            .selection(now: date("2026-04-10"), timeZone: zone)
        XCTAssertEqual(try custom.effective.dayCount(timeZone: zone), 3)
        XCTAssertEqual(custom.comparison,
                       try LedgerDateInterval(start: day("2026-03-26"), end: day("2026-03-28")))
        XCTAssertEqual(try custom.comparison.dayCount(timeZone: zone), 3)
    }

    func testComparisonPercentageUsesPreviousKnownNetAndZeroBaseIsUnavailable() throws {
        var previous = item(20, kind: .expense, cents: 100, day: "2026-09-10", category: "Food")
        previous.personalExpenseEURMinor = 100
        var current = item(21, kind: .expense, cents: 150, day: "2026-10-10", category: "Food")
        current.personalExpenseEURMinor = 150
        let snapshot = try FinancialAnalytics.snapshot(transactions: [previous, current],
            period: .month(year: 2026, month: 10), zone: zone, now: date("2026-10-25"))
        XCTAssertEqual(snapshot.comparison.totals.personalNetExpensesEURMinor, 100)
        XCTAssertEqual(snapshot.comparison.personalNetExpensesChange,
                       FinancialPercentageChange(differenceEURMinor: 50, baselineEURMinor: 100))
        XCTAssertEqual(snapshot.comparison.personalNetExpensesChange?.percent, 50)

        let noBaseline = try FinancialAnalytics.snapshot(transactions: [current],
            period: .month(year: 2026, month: 10), zone: zone, now: date("2026-10-25"))
        XCTAssertNil(noBaseline.comparison.personalNetExpensesChange)
    }

    func testSharedFilterIntersectsDateIDsAndLedgerDimensions() throws {
        let accountID = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!
        let categoryID = UUID(uuidString: "B0000000-0000-4000-8000-000000000001")!
        var matching = item(30, kind: .expense, cents: 400, day: "2026-10-12",
                            category: "Food", categoryID: categoryID)
        matching.personalExpenseEURMinor = 400
        matching.tripID = "fictional-trip"
        var wrongTrip = item(31, kind: .expense, cents: 800, day: "2026-10-12",
                             category: "Food", categoryID: categoryID)
        wrongTrip.personalExpenseEURMinor = 800
        wrongTrip.tripID = "another-trip"
        var filter = TransactionFilter(query: "movement", accountKeys: ["id:\(accountID.uuidString)"],
            categoryKeys: ["id:\(categoryID.uuidString)"], kindKeys: ["expense"],
            tripIDs: ["fictional-trip"], currencies: ["EUR"])
        filter.transactionIDs = [matching.id, wrongTrip.id]

        let snapshot = try FinancialAnalytics.snapshot(transactions: [matching, wrongTrip],
            period: .custom(start: day("2026-10-10"), end: day("2026-10-15")),
            baseFilter: filter, zone: zone, now: date("2026-10-20"))
        XCTAssertEqual(snapshot.totals.personalNetExpensesEURMinor, 400)
        XCTAssertEqual(snapshot.appliedFilter.apply(to: [matching, wrongTrip], timeZone: zone).map(\.id),
                       [matching.id])
        XCTAssertEqual(snapshot.appliedFilter.dateInterval,
                       try LedgerDateInterval(start: day("2026-10-10"), end: day("2026-10-15")))
    }

    func testInvalidFuturePeriodAndCheckedCentOverflow() throws {
        XCTAssertThrowsError(try FinancialPeriod.custom(start: day("2026-11-01"), end: day("2026-11-02"))
            .selection(now: date("2026-10-25"), timeZone: zone)) {
            XCTAssertEqual($0 as? FinancialAnalyticsError, .periodHasNotStarted)
        }
        var maximum = item(40, kind: .expense, cents: Int64.max, day: "2026-10-01", category: "Food")
        maximum.personalExpenseEURMinor = Int64.max
        var extra = item(41, kind: .expense, cents: 1, day: "2026-10-02", category: "Food")
        extra.personalExpenseEURMinor = 1
        XCTAssertThrowsError(try FinancialAnalytics.snapshot(transactions: [maximum, extra],
            period: .month(year: 2026, month: 10), zone: zone, now: date("2026-10-25"))) {
            XCTAssertEqual($0 as? FinancialAnalyticsError, .amountOverflow)
        }
    }
}

private extension FinancialAnalytics {
    static func snapshot(transactions: [Transaction], period: FinancialPeriod,
                         baseFilter: TransactionFilter = .init(),
                         categoryNames: [UUID: String] = [:],
                         tripNames: [String: String] = [:], zone: TimeZone,
                         now: Date) throws -> FinancialAnalyticsSnapshot {
        try snapshot(transactions: transactions, period: period, baseFilter: baseFilter,
                     categoryNames: categoryNames, tripNames: tripNames,
                     timeZone: zone, now: now)
    }
}
