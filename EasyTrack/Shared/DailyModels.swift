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

    static func symbolTitle(_ symbol: String) -> String {
        symbol.replacingOccurrences(of: ".fill", with: "")
            .replacingOccurrences(of: ".", with: " ")
            .capitalized
    }
}

enum DailyValidationError: LocalizedError {
    case emptyName, duplicateName, staleRecord, invalidAppearance, invalidAmount,
         missingAccount, archivedAccount, invalidCategory, invalidRule

    var errorDescription: String? {
        switch self {
        case .emptyName: AppLanguage.localized("Enter a name.")
        case .duplicateName: AppLanguage.localized("That name is already in use.")
        case .staleRecord: AppLanguage.localized("This item changed. Reopen it before saving.")
        case .invalidAppearance: AppLanguage.localized("Choose an available icon and color.")
        case .invalidAmount: AppLanguage.localized("Enter a positive EUR amount.")
        case .missingAccount: AppLanguage.localized("Choose an account.")
        case .archivedAccount: AppLanguage.localized("This account is archived. Choose an active account.")
        case .invalidCategory: AppLanguage.localized("Choose an active category or leave it uncategorized.")
        case .invalidRule: AppLanguage.localized("This recurring rule cannot be saved. Check its dates and schedule.")
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
    var localizedString: String {
        noon(in: .current)?.easyTrackFormatted(date: .abbreviated, time: .omitted) ?? isoString
    }
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
    var reviewWindowDays: Int = 3
}

enum RecurringOccurrenceStatus: String, Codable {
    case expected, legacyCounted = "legacy_counted", recordedManual = "recorded_manual"
    case confirmed, skipped, missed, cancelled, materialized // last case decodes format-5 JSON only

    var title: String {
        switch self {
        case .expected: "Expected"
        case .legacyCounted: "Legacy counted"
        case .recordedManual: "Recorded manually"
        case .confirmed: "Paid"
        case .skipped: "Skipped"
        case .missed: "Missed"
        case .cancelled: "Cancelled"
        case .materialized: "Legacy counted"
        }
    }
}

extension RecurringRule {
    private enum CodingKeys: String, CodingKey {
        case id,name,type,amountMinor,accountID,categoryID,startDay,frequency,nextIndex,endDay
        case timeZoneIdentifier,isActive,note,createdAt,updatedAt,archivedAt,revision
        case historicalSourceID,reviewWindowDays
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  name: try c.decode(String.self, forKey: .name),
                  type: try c.decode(RecurringType.self, forKey: .type),
                  amountMinor: try c.decode(Int64.self, forKey: .amountMinor),
                  accountID: try c.decode(UUID.self, forKey: .accountID),
                  categoryID: try c.decodeIfPresent(UUID.self, forKey: .categoryID),
                  startDay: try c.decode(LocalDay.self, forKey: .startDay),
                  frequency: try c.decode(RecurringFrequency.self, forKey: .frequency),
                  nextIndex: try c.decode(Int.self, forKey: .nextIndex),
                  endDay: try c.decodeIfPresent(LocalDay.self, forKey: .endDay),
                  timeZoneIdentifier: try c.decode(String.self, forKey: .timeZoneIdentifier),
                  isActive: try c.decode(Bool.self, forKey: .isActive),
                  note: try c.decode(String.self, forKey: .note),
                  createdAt: try c.decode(Date.self, forKey: .createdAt),
                  updatedAt: try c.decode(Date.self, forKey: .updatedAt),
                  archivedAt: try c.decodeIfPresent(Date.self, forKey: .archivedAt),
                  revision: try c.decode(Int64.self, forKey: .revision))
        historicalSourceID = try c.decodeIfPresent(String.self, forKey: .historicalSourceID)
        reviewWindowDays = try c.decodeIfPresent(Int.self, forKey: .reviewWindowDays) ?? 3
    }
}

extension RecurringOccurrence {
    private enum CodingKeys: String, CodingKey {
        case id,ruleID,scheduledDay,status,transactionID,createdAt
        case provisionalTransactionID,updatedAt,revision,reviewReason
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  ruleID: try c.decode(UUID.self, forKey: .ruleID),
                  scheduledDay: try c.decode(LocalDay.self, forKey: .scheduledDay),
                  status: try c.decode(RecurringOccurrenceStatus.self, forKey: .status),
                  transactionID: try c.decodeIfPresent(UUID.self, forKey: .transactionID),
                  createdAt: try c.decode(Date.self, forKey: .createdAt))
        provisionalTransactionID = try c.decodeIfPresent(UUID.self, forKey: .provisionalTransactionID)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        revision = try c.decodeIfPresent(Int64.self, forKey: .revision) ?? 1
        reviewReason = try c.decodeIfPresent(String.self, forKey: .reviewReason)
    }
}

struct RecurringOccurrence: Identifiable, Codable, Equatable {
    let id: String
    let ruleID: UUID
    let scheduledDay: LocalDay
    let status: RecurringOccurrenceStatus
    let transactionID: UUID?
    let createdAt: Date
    var provisionalTransactionID: UUID? = nil
    var updatedAt: Date = .now
    var revision: Int64 = 1
    var reviewReason: String? = nil
}

enum RecurringCandidateStatus: String, Codable { case pending, rejected, confirmed }

struct RecurringCandidate: Identifiable, Equatable {
    let id: UUID
    let occurrenceID: String
    let eventID: UUID?
    let transactionID: UUID?
    let status: RecurringCandidateStatus
    let reason: String
    let createdAt: Date
    let updatedAt: Date
    let revision: Int64
}

struct RecurringMatchOption {
    let occurrence: RecurringOccurrence
    let rule: RecurringRule
    let reason: String
    let strict: Bool
    let counted: Bool
    let approvedPayee: Bool
    let dayDistance: Int
    let amountDifference: Int64
}

struct UpcomingRecurringItem: Identifiable, Equatable {
    let rule: RecurringRule
    let index: Int
    let day: LocalDay
    var id: String { RecurringSchedule.occurrenceID(ruleID: rule.id, day: day) }
}

enum RecurringError: LocalizedError {
    case invalidDate, invalidSchedule, tooManyMissed, inactive, occurrenceChanged, linkRequiresUnlink
    var errorDescription: String? {
        switch self {
        case .invalidDate: AppLanguage.localized("Choose a valid schedule date.")
        case .invalidSchedule: AppLanguage.localized("This repeating schedule could not be calculated.")
        case .tooManyMissed: AppLanguage.localized("This rule has too many missed dates. Edit its next date before continuing.")
        case .inactive: AppLanguage.localized("Resume this rule before creating its next transaction.")
        case .occurrenceChanged: AppLanguage.localized("This occurrence changed. Reopen the rule and try again.")
        case .linkRequiresUnlink: AppLanguage.localized("Unlink the confirmed recurring payment before changing its account or movement kind.")
        }
    }
}
