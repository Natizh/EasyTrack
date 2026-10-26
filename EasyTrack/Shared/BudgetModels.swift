import Foundation

enum MonthlyBudgetScope: String, Codable, CaseIterable, Identifiable {
    case overall, category
    var id: String { rawValue }
    var title: String { self == .overall ? "Overall" : "Category" }
}

struct MonthlyBudget: Codable, Equatable, Identifiable {
    let id: UUID
    var scope: MonthlyBudgetScope
    var categoryID: UUID?
    var limitEURMinor: Int64
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var revision: Int64
}

struct SavingsGoal: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var targetEURMinor: Int64
    var progressEURMinor: Int64
    var dueDate: LocalDay?
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var revision: Int64
}

struct BudgetProgress: Equatable, Identifiable {
    var id: UUID { budget.id }
    let budget: MonthlyBudget
    let title: String
    let spentEURMinor: Int64
    let remainingEURMinor: Int64

    var isOverLimit: Bool { remainingEURMinor < 0 }
}

struct MonthlyBudgetSnapshot: Equatable {
    let month: LocalDay
    let overall: BudgetProgress?
    let categories: [BudgetProgress]
    let missingConversionCount: Int
}

enum BudgetAnalytics {
    static func snapshot(financial: FinancialAnalyticsSnapshot,
                         budgets: [MonthlyBudget], categories: [LedgerCategory]) throws -> MonthlyBudgetSnapshot {
        let active = budgets.filter { $0.archivedAt == nil }
        let names = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let categoryAmounts = Dictionary(uniqueKeysWithValues: financial.categories.compactMap { value in
            value.categoryID.map { ($0, value.personalNetExpensesEURMinor) }
        })
        func progress(_ budget: MonthlyBudget, title: String, spent: Int64) throws -> BudgetProgress {
            let (remaining, overflow) = budget.limitEURMinor.subtractingReportingOverflow(spent)
            guard !overflow else { throw FinancialAnalyticsError.amountOverflow }
            return BudgetProgress(budget: budget, title: title, spentEURMinor: spent,
                                  remainingEURMinor: remaining)
        }
        let overallBudget = active.first { $0.scope == .overall }
        let overall = try overallBudget.map {
            try progress($0, title: "Overall budget", spent: financial.totals.personalNetExpensesEURMinor)
        }
        let categoryProgress = try active.filter { $0.scope == .category }.map { budget in
            let title = budget.categoryID.flatMap { names[$0] } ?? "Unavailable category"
            return try progress(budget, title: title,
                                spent: budget.categoryID.flatMap { categoryAmounts[$0] } ?? 0)
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let start = financial.period.effective.start
        return MonthlyBudgetSnapshot(month: LocalDay(isoString: String(format: "%04d-%02d-01",
                                                                        start.year, start.month))!,
                                     overall: overall, categories: categoryProgress,
                                     missingConversionCount: financial.unconvertedTransactions.count)
    }
}
