import Foundation

enum FinancialAnalyticsError: LocalizedError, Equatable {
    case invalidPeriod
    case periodHasNotStarted
    case amountOverflow

    var errorDescription: String? {
        switch self {
        case .invalidPeriod: "The selected financial period is invalid."
        case .periodHasNotStarted: "The selected financial period has not started yet."
        case .amountOverflow: "The selected history is too large to total safely in cents."
        }
    }
}

struct LedgerDateInterval: Codable, Equatable, Hashable {
    let start: LocalDay
    let end: LocalDay

    init(start: LocalDay, end: LocalDay) throws {
        guard start <= end else { throw FinancialAnalyticsError.invalidPeriod }
        self.start = start
        self.end = end
    }

    func contains(_ date: Date, timeZone: TimeZone) -> Bool {
        let day = LocalDay(date: date, timeZone: timeZone)
        return start <= day && day <= end
    }

    func dayCount(timeZone: TimeZone) throws -> Int {
        guard let first = start.noon(in: timeZone), let last = end.noon(in: timeZone) else {
            throw FinancialAnalyticsError.invalidPeriod
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let distance = calendar.dateComponents([.day], from: first, to: last).day else {
            throw FinancialAnalyticsError.invalidPeriod
        }
        return distance + 1
    }
}

enum FinancialPeriod: Equatable {
    case month(year: Int, month: Int)
    case year(Int)
    case custom(start: LocalDay, end: LocalDay)

    static func month(containing date: Date, timeZone: TimeZone) -> FinancialPeriod {
        let day = LocalDay(date: date, timeZone: timeZone)
        return .month(year: day.year, month: day.month)
    }

    static func year(containing date: Date, timeZone: TimeZone) -> FinancialPeriod {
        .year(LocalDay(date: date, timeZone: timeZone).year)
    }

    func selection(now: Date, timeZone: TimeZone) throws -> FinancialPeriodSelection {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let requested: LedgerDateInterval
        switch self {
        case let .month(year, month):
            requested = try Self.monthInterval(year: year, month: month, calendar: calendar, timeZone: timeZone)
        case let .year(year):
            guard let start = LocalDay(isoString: String(format: "%04d-01-01", year)),
                  let end = LocalDay(isoString: String(format: "%04d-12-31", year)) else {
                throw FinancialAnalyticsError.invalidPeriod
            }
            requested = try LedgerDateInterval(start: start, end: end)
        case let .custom(start, end):
            requested = try LedgerDateInterval(start: start, end: end)
        }

        let today = LocalDay(date: now, timeZone: timeZone)
        guard today >= requested.start else { throw FinancialAnalyticsError.periodHasNotStarted }
        let effective = try LedgerDateInterval(start: requested.start, end: min(today, requested.end))
        let comparison: LedgerDateInterval

        switch self {
        case .month:
            guard let selectedStart = requested.start.noon(in: timeZone),
                  let priorStartDate = calendar.date(byAdding: .month, value: -1, to: selectedStart) else {
                throw FinancialAnalyticsError.invalidPeriod
            }
            let priorStartDay = LocalDay(date: priorStartDate, timeZone: timeZone)
            let priorFull = try Self.monthInterval(year: priorStartDay.year, month: priorStartDay.month,
                                                   calendar: calendar, timeZone: timeZone)
            let priorEnd = effective.end < requested.end
                ? LocalDay(year: priorStartDay.year, month: priorStartDay.month,
                           day: min(effective.end.day, priorFull.end.day))
                : priorFull.end
            comparison = try LedgerDateInterval(start: priorFull.start, end: priorEnd)
        case let .year(year):
            guard let priorStart = LocalDay(isoString: String(format: "%04d-01-01", year - 1)) else {
                throw FinancialAnalyticsError.invalidPeriod
            }
            let priorEnd: LocalDay
            if effective.end < requested.end {
                let priorMonth = try Self.monthInterval(year: year - 1, month: effective.end.month,
                                                        calendar: calendar, timeZone: timeZone)
                priorEnd = LocalDay(year: year - 1, month: effective.end.month,
                                    day: min(effective.end.day, priorMonth.end.day))
            } else {
                guard let end = LocalDay(isoString: String(format: "%04d-12-31", year - 1)) else {
                    throw FinancialAnalyticsError.invalidPeriod
                }
                priorEnd = end
            }
            comparison = try LedgerDateInterval(start: priorStart, end: priorEnd)
        case .custom:
            guard let effectiveStart = effective.start.noon(in: timeZone),
                  let comparisonEndDate = calendar.date(byAdding: .day, value: -1, to: effectiveStart),
                  let comparisonStartDate = calendar.date(byAdding: .day,
                      value: -(try effective.dayCount(timeZone: timeZone) - 1), to: comparisonEndDate) else {
                throw FinancialAnalyticsError.invalidPeriod
            }
            comparison = try LedgerDateInterval(
                start: LocalDay(date: comparisonStartDate, timeZone: timeZone),
                end: LocalDay(date: comparisonEndDate, timeZone: timeZone)
            )
        }
        return FinancialPeriodSelection(requested: requested, effective: effective,
                                        comparison: comparison, isIncomplete: effective.end < requested.end)
    }

    private static func monthInterval(year: Int, month: Int, calendar: Calendar,
                                      timeZone: TimeZone) throws -> LedgerDateInterval {
        guard (1...12).contains(month),
              let firstDate = calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)),
              let following = calendar.date(byAdding: .month, value: 1, to: firstDate),
              let lastDate = calendar.date(byAdding: .day, value: -1, to: following) else {
            throw FinancialAnalyticsError.invalidPeriod
        }
        return try LedgerDateInterval(start: LocalDay(date: firstDate, timeZone: timeZone),
                                      end: LocalDay(date: lastDate, timeZone: timeZone))
    }
}

struct FinancialPeriodSelection: Equatable {
    let requested: LedgerDateInterval
    let effective: LedgerDateInterval
    let comparison: LedgerDateInterval
    let isIncomplete: Bool
}

struct FinancialTotals: Equatable {
    var personalNetExpensesEURMinor: Int64 = 0
    var grossExpensesEURMinor: Int64 = 0
    var incomeEURMinor: Int64 = 0
    var pacInvestedEURMinor: Int64 = 0
}

struct FinancialDailyAverage: Equatable {
    let personalNetExpensesEURMinor: Int64
    let elapsedDayCount: Int

    var exactEURMinorPerDay: Decimal {
        Decimal(personalNetExpensesEURMinor) / Decimal(elapsedDayCount)
    }
}

struct FinancialCategoryAggregate: Equatable, Identifiable {
    var id: String { key }
    let key: String
    let categoryID: UUID?
    let name: String
    let personalNetExpensesEURMinor: Int64
}

struct FinancialMonthlyAggregate: Equatable, Identifiable {
    var id: LocalDay { month }
    let month: LocalDay
    var grossExpensesEURMinor: Int64 = 0
    var incomeEURMinor: Int64 = 0
    var pacInvestedEURMinor: Int64 = 0
}

struct FinancialDailyAggregate: Equatable, Identifiable {
    var id: LocalDay { day }
    let day: LocalDay
    var personalNetExpensesEURMinor: Int64 = 0
}

struct FinancialMerchantAggregate: Equatable, Identifiable {
    var id: String { key }
    let key: String
    let name: String
    let transactionCount: Int
    let personalNetExpensesEURMinor: Int64
    let transactionIDs: [UUID]
}

struct FinancialChartSelectionIndex: Equatable {
    var monthlyExpenses: [LocalDay: Set<UUID>] = [:]
    var monthlyIncome: [LocalDay: Set<UUID>] = [:]
    var monthlyPAC: [LocalDay: Set<UUID>] = [:]
    var categories: [String: Set<UUID>] = [:]
    var dailySpending: [LocalDay: Set<UUID>] = [:]
    var unallocated: Set<UUID> = []
}

enum FinancialMetric: String, Equatable, Hashable {
    case personalNetExpenses
    case grossExpenses
    case income
    case pacInvestment
}

struct UnconvertedFinancialTransaction: Equatable {
    let transactionID: UUID
    let currency: String
    let originalAmountMinor: Int64
    let unavailableMetrics: Set<FinancialMetric>
}

struct FinancialPercentageChange: Equatable {
    let differenceEURMinor: Int64
    let baselineEURMinor: Int64

    var percent: Decimal {
        Decimal(differenceEURMinor) * 100 / Decimal(baselineEURMinor)
    }
}

struct FinancialPeriodComparison: Equatable {
    let interval: LedgerDateInterval
    let totals: FinancialTotals
    let personalNetExpensesChange: FinancialPercentageChange?
    let unconvertedTransactions: [UnconvertedFinancialTransaction]
}

struct FinancialAnalyticsSnapshot: Equatable {
    let period: FinancialPeriodSelection
    let totals: FinancialTotals
    let dailyAverage: FinancialDailyAverage
    let categories: [FinancialCategoryAggregate]
    let monthlyTrend: [FinancialMonthlyAggregate]
    let dailySpending: [FinancialDailyAggregate]
    let merchants: [FinancialMerchantAggregate]
    let chartSelectionIndex: FinancialChartSelectionIndex
    let unallocatedPersonalAdjustmentEURMinor: Int64
    let nonPositiveCategoryAdjustmentEURMinor: Int64
    let unconvertedTransactions: [UnconvertedFinancialTransaction]
    let comparison: FinancialPeriodComparison
    let appliedFilter: TransactionFilter

    var positiveCategories: [FinancialCategoryAggregate] {
        categories.filter { $0.personalNetExpensesEURMinor > 0 }
    }

}

enum FinancialAnalytics {
    static func snapshot(transactions: [Transaction], period: FinancialPeriod,
                         baseFilter: TransactionFilter = .init(),
                         categoryNames: [UUID: String] = [:],
                         tripNames: [String: String] = [:],
                         timeZone: TimeZone = .current, now: Date = .now) throws -> FinancialAnalyticsSnapshot {
        let selection = try period.selection(now: now, timeZone: timeZone)
        var currentFilter = baseFilter
        currentFilter.dateInterval = selection.effective
        let currentItems = currentFilter.apply(to: transactions, tripNames: tripNames, timeZone: timeZone)
        let current = try aggregate(currentItems, interval: selection.effective,
                                    categoryNames: categoryNames, timeZone: timeZone)

        var comparisonFilter = baseFilter
        comparisonFilter.dateInterval = selection.comparison
        let comparisonItems = comparisonFilter.apply(to: transactions, tripNames: tripNames, timeZone: timeZone)
        let previous = try aggregate(comparisonItems, interval: selection.comparison,
                                     categoryNames: categoryNames, timeZone: timeZone)
        let change: FinancialPercentageChange?
        if previous.totals.personalNetExpensesEURMinor == 0 {
            change = nil
        } else {
            let difference = try subtractChecked(current.totals.personalNetExpensesEURMinor,
                                                 previous.totals.personalNetExpensesEURMinor)
            change = FinancialPercentageChange(differenceEURMinor: difference,
                                               baselineEURMinor: previous.totals.personalNetExpensesEURMinor)
        }

        currentFilter.transactionIDs = Set(currentItems.map(\.id))
        return FinancialAnalyticsSnapshot(
            period: selection,
            totals: current.totals,
            dailyAverage: FinancialDailyAverage(
                personalNetExpensesEURMinor: current.totals.personalNetExpensesEURMinor,
                elapsedDayCount: try selection.effective.dayCount(timeZone: timeZone)),
            categories: current.categories,
            monthlyTrend: current.monthlyTrend,
            dailySpending: current.dailySpending,
            merchants: current.merchants,
            chartSelectionIndex: current.chartSelectionIndex,
            unallocatedPersonalAdjustmentEURMinor: current.unallocated,
            nonPositiveCategoryAdjustmentEURMinor: current.nonPositiveCategories,
            unconvertedTransactions: current.unconverted,
            comparison: FinancialPeriodComparison(interval: selection.comparison,
                totals: previous.totals, personalNetExpensesChange: change,
                unconvertedTransactions: previous.unconverted),
            appliedFilter: currentFilter
        )
    }

    private struct Aggregation {
        let totals: FinancialTotals
        let categories: [FinancialCategoryAggregate]
        let monthlyTrend: [FinancialMonthlyAggregate]
        let dailySpending: [FinancialDailyAggregate]
        let merchants: [FinancialMerchantAggregate]
        let chartSelectionIndex: FinancialChartSelectionIndex
        let unallocated: Int64
        let nonPositiveCategories: Int64
        let unconverted: [UnconvertedFinancialTransaction]
    }

    private struct MutableCategory {
        let categoryID: UUID?
        let name: String
        var amount: Int64
    }

    private struct MutableMerchant {
        let name: String
        var count: Int
        var amount: Int64
        var transactionIDs: Set<UUID>
    }

    private static func aggregate(_ transactions: [Transaction], interval: LedgerDateInterval,
                                  categoryNames: [UUID: String], timeZone: TimeZone) throws -> Aggregation {
        var totals = FinancialTotals()
        var categoryValues: [String: MutableCategory] = [:]
        var unallocated: Int64 = 0
        var unconverted: [UnconvertedFinancialTransaction] = []
        var selectionIndex = FinancialChartSelectionIndex()
        var merchantValues: [String: MutableMerchant] = [:]
        let intervalDays = try days(in: interval, timeZone: timeZone)
        var dailyValues = Dictionary(uniqueKeysWithValues: intervalDays.map {
            ($0, FinancialDailyAggregate(day: $0))
        })
        let months = Set(intervalDays.map { LocalDay(year: $0.year, month: $0.month, day: 1) })
        var monthlyValues = Dictionary(uniqueKeysWithValues: months.map {
            ($0, FinancialMonthlyAggregate(month: $0))
        })

        for item in transactions {
            let localDay = LocalDay(date: item.occurredAt, timeZone: timeZone)
            let month = LocalDay(year: localDay.year, month: localDay.month, day: 1)
            let eur = item.eurMinor ?? (item.currency == "EUR" ? item.amountMinor : nil)
            let personal = item.personalExpenseEURMinor ??
                (item.kind == .expense && item.currency == "EUR" ? item.amountMinor : nil)
            var unavailable: Set<FinancialMetric> = []

            if let personal {
                try addChecked(personal, to: &totals.personalNetExpensesEURMinor)
                if var daily = dailyValues[localDay] {
                    try addChecked(personal, to: &daily.personalNetExpensesEURMinor)
                    dailyValues[localDay] = daily
                }
                selectionIndex.dailySpending[localDay, default: []].insert(item.id)
                let trimmed = item.category.trimmingCharacters(in: .whitespacesAndNewlines)
                if item.categoryID == nil && trimmed.isEmpty {
                    try addChecked(personal, to: &unallocated)
                    selectionIndex.unallocated.insert(item.id)
                } else {
                    let name = item.categoryID.flatMap { categoryNames[$0] } ??
                        (trimmed.isEmpty ? "Uncategorized" : trimmed)
                    let key = item.categoryID.map { "id:\($0.uuidString)" } ?? "label:\(trimmed.lowercased())"
                    var value = categoryValues[key] ?? MutableCategory(categoryID: item.categoryID,
                                                                        name: name, amount: 0)
                    try addChecked(personal, to: &value.amount)
                    categoryValues[key] = value
                    selectionIndex.categories[key, default: []].insert(item.id)
                }
                let merchantKey = NotificationParser.normalize(item.merchant)
                if !merchantKey.isEmpty {
                    var merchant = merchantValues[merchantKey] ?? MutableMerchant(
                        name: item.merchant, count: 0, amount: 0, transactionIDs: [])
                    merchant.count += 1
                    try addChecked(personal, to: &merchant.amount)
                    merchant.transactionIDs.insert(item.id)
                    merchantValues[merchantKey] = merchant
                }
            } else if item.kind == .expense && eur == nil {
                unavailable.insert(.personalNetExpenses)
            } else if item.kind == .reimbursement && eur == nil {
                unavailable.insert(.personalNetExpenses)
            }

            switch item.kind {
            case .expense:
                if let eur {
                    try addChecked(eur, to: &totals.grossExpensesEURMinor)
                    if var monthly = monthlyValues[month] {
                        try addChecked(eur, to: &monthly.grossExpensesEURMinor)
                        monthlyValues[month] = monthly
                    }
                    selectionIndex.monthlyExpenses[month, default: []].insert(item.id)
                }
                else { unavailable.insert(.grossExpenses) }
            case .income:
                if let eur {
                    try addChecked(eur, to: &totals.incomeEURMinor)
                    if var monthly = monthlyValues[month] {
                        try addChecked(eur, to: &monthly.incomeEURMinor)
                        monthlyValues[month] = monthly
                    }
                    selectionIndex.monthlyIncome[month, default: []].insert(item.id)
                }
                else { unavailable.insert(.income) }
            case .pacInvestment:
                if let eur {
                    try addChecked(eur, to: &totals.pacInvestedEURMinor)
                    if var monthly = monthlyValues[month] {
                        try addChecked(eur, to: &monthly.pacInvestedEURMinor)
                        monthlyValues[month] = monthly
                    }
                    selectionIndex.monthlyPAC[month, default: []].insert(item.id)
                }
                else { unavailable.insert(.pacInvestment) }
            case .advanceForOthers, .reimbursement, .deposit, .depositRefund:
                break
            }

            if !unavailable.isEmpty {
                unconverted.append(UnconvertedFinancialTransaction(transactionID: item.id,
                    currency: item.currency, originalAmountMinor: item.amountMinor,
                    unavailableMetrics: unavailable))
            }
        }

        let categories = categoryValues.map { key, value in
            FinancialCategoryAggregate(key: key, categoryID: value.categoryID, name: value.name,
                                       personalNetExpensesEURMinor: value.amount)
        }.sorted {
            if $0.personalNetExpensesEURMinor != $1.personalNetExpensesEURMinor {
                return $0.personalNetExpensesEURMinor > $1.personalNetExpensesEURMinor
            }
            if $0.name != $1.name { return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return $0.key < $1.key
        }
        unconverted.sort { $0.transactionID.uuidString < $1.transactionID.uuidString }
        var nonPositiveCategories: Int64 = 0
        var reconciled = unallocated
        for category in categories {
            try addChecked(category.personalNetExpensesEURMinor, to: &reconciled)
            if category.personalNetExpensesEURMinor <= 0 {
                try addChecked(category.personalNetExpensesEURMinor, to: &nonPositiveCategories)
            }
        }
        precondition(reconciled == totals.personalNetExpensesEURMinor)
        let merchants = merchantValues.map { key, value in
            FinancialMerchantAggregate(key: key, name: value.name, transactionCount: value.count,
                personalNetExpensesEURMinor: value.amount,
                transactionIDs: value.transactionIDs.sorted { $0.uuidString < $1.uuidString })
        }.sorted {
            if $0.personalNetExpensesEURMinor != $1.personalNetExpensesEURMinor {
                return $0.personalNetExpensesEURMinor > $1.personalNetExpensesEURMinor
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return Aggregation(totals: totals, categories: categories,
                           monthlyTrend: monthlyValues.values.sorted { $0.month < $1.month },
                           dailySpending: dailyValues.values.sorted { $0.day < $1.day },
                           merchants: merchants, chartSelectionIndex: selectionIndex,
                           unallocated: unallocated,
                           nonPositiveCategories: nonPositiveCategories, unconverted: unconverted)
    }

    private static func days(in interval: LedgerDateInterval, timeZone: TimeZone) throws -> [LocalDay] {
        guard let start = interval.start.noon(in: timeZone) else {
            throw FinancialAnalyticsError.invalidPeriod
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return try (0..<interval.dayCount(timeZone: timeZone)).map { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                throw FinancialAnalyticsError.invalidPeriod
            }
            return LocalDay(date: date, timeZone: timeZone)
        }
    }

    private static func addChecked(_ amount: Int64, to total: inout Int64) throws {
        let (value, overflow) = total.addingReportingOverflow(amount)
        guard !overflow else { throw FinancialAnalyticsError.amountOverflow }
        total = value
    }

    private static func subtractChecked(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let (value, overflow) = lhs.subtractingReportingOverflow(rhs)
        guard !overflow else { throw FinancialAnalyticsError.amountOverflow }
        return value
    }
}

private extension LocalDay {
    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }
}
