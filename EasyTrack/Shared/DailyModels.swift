import Foundation

struct LedgerCategory: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var symbolName: String
    var colorName: String
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var revision: Int64
}

enum LedgerAppearance {
    static let colors = ["teal", "blue", "green", "orange", "red", "purple", "indigo", "gray"]
    static let symbols = ["creditcard.fill", "banknote.fill", "building.columns.fill", "wallet.pass.fill",
                          "cart.fill", "fork.knife", "car.fill", "bag.fill", "house.fill",
                          "doc.text.fill", "cross.case.fill", "ticket.fill", "airplane",
                          "book.fill", "square.grid.2x2.fill", "gift.fill", "heart.fill"]
}

enum DailyValidationError: LocalizedError {
    case emptyName, duplicateName, staleRecord, invalidAppearance, invalidAmount,
         missingAccount, archivedAccount, invalidCategory, invalidRule

    var errorDescription: String? {
        switch self {
        case .emptyName: "Enter a name."
        case .duplicateName: "That name is already in use."
        case .staleRecord: "This item changed. Reopen it before saving."
        case .invalidAppearance: "Choose an available icon and color."
        case .invalidAmount: "Enter a positive EUR amount."
        case .missingAccount: "Choose an account."
        case .archivedAccount: "This account is archived. Choose an active account."
        case .invalidCategory: "Choose an active category or leave it uncategorized."
        case .invalidRule: "This recurring rule cannot be saved. Check its dates and schedule."
        }
    }
}

enum RecurringFrequency: String, Codable, CaseIterable, Identifiable {
    case weekly, monthly, yearly
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum RecurringType: String, Codable, CaseIterable, Identifiable {
    case subscription, expense, income, pacInvestment
    var id: String { rawValue }
    var title: String {
        switch self {
        case .subscription: "Subscription"
        case .expense: "Recurring expense"
        case .income: "Recurring income"
        case .pacInvestment: "PAC investment"
        }
    }
    var transactionKind: TransactionKind {
        switch self {
        case .subscription, .expense: .expense
        case .income: .income
        case .pacInvestment: .pacInvestment
        }
    }
    var symbolName: String {
        switch self {
        case .subscription: "repeat.circle"
        case .expense: "arrow.up.right"
        case .income: "arrow.down.left"
        case .pacInvestment: "chart.line.uptrend.xyaxis"
        }
    }
}

struct LocalDay: Codable, Hashable, Comparable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year!
        month = components.month!
        day = components.day!
    }

    init?(isoString: String) {
        let parts = isoString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        self.year = year; self.month = month; self.day = day
    }

    var isoString: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var description: String { isoString }

    static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    func noon(in timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }
}

struct RecurringRule: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var type: RecurringType
    var amountMinor: Int64
    var accountID: UUID
    var categoryID: UUID?
    var startDay: LocalDay
    var frequency: RecurringFrequency
    var nextIndex: Int
    var endDay: LocalDay?
    var timeZoneIdentifier: String
    var isActive: Bool
    var note: String
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var revision: Int64
    var historicalSourceID: String? = nil
}

enum RecurringOccurrenceStatus: String, Codable {
    case materialized, skipped
}

struct RecurringOccurrence: Identifiable, Codable, Equatable {
    let id: String
    let ruleID: UUID
    let scheduledDay: LocalDay
    let status: RecurringOccurrenceStatus
    let transactionID: UUID?
    let createdAt: Date
}

struct UpcomingRecurringItem: Identifiable, Equatable {
    let rule: RecurringRule
    let index: Int
    let day: LocalDay
    var id: String { RecurringSchedule.occurrenceID(ruleID: rule.id, day: day) }
}

enum RecurringError: LocalizedError {
    case invalidDate, invalidSchedule, tooManyMissed, inactive, occurrenceChanged
    var errorDescription: String? {
        switch self {
        case .invalidDate: "Choose a valid schedule date."
        case .invalidSchedule: "This repeating schedule could not be calculated."
        case .tooManyMissed: "This rule has too many missed dates. Edit its next date before continuing."
        case .inactive: "Resume this rule before creating its next transaction."
        case .occurrenceChanged: "This occurrence changed. Reopen the rule and try again."
        }
    }
}
