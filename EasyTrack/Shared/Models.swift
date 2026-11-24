import CryptoKit
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case italian = "it"
    case english = "en"

    static let storageKey = "easyTrackLanguage"
    var id: String { rawValue }
    var title: String { self == .italian ? "Italiano" : "English" }
    var locale: Locale { Locale(identifier: self == .italian ? "it_IT" : "en_US") }

    static func resolved(_ code: String?) -> AppLanguage {
        code.flatMap(AppLanguage.init(rawValue:)) ?? .italian
    }

    static var current: AppLanguage {
        resolved(UserDefaults.standard.string(forKey: storageKey))
    }

    /// Formatter locale follows the selected app language in the iOS app.
    /// Command-line tools and SwiftPM tests retain their host locale.
    static var formatLocale: Locale {
        Bundle.main.path(forResource: "it", ofType: "lproj") == nil ? .current : current.locale
    }

    static func localized(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: current.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func formatted(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: formatLocale, arguments: arguments)
    }
}

extension Date {
    func easyTrackFormatted(date: Date.FormatStyle.DateStyle,
                            time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time).locale(AppLanguage.formatLocale))
    }
}

enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case expense, income, pacInvestment, advanceForOthers, reimbursement, deposit, depositRefund
    var id: String { rawValue }
    var title: String {
        switch self {
        case .expense: "Expense"
        case .income: "Income"
        case .pacInvestment: "PAC investment"
        case .advanceForOthers: "Paid for others"
        case .reimbursement: "Reimbursement"
        case .deposit: "Deposit"
        case .depositRefund: "Deposit refund"
        }
    }
    var isOutflow: Bool {
        switch self {
        case .expense, .pacInvestment, .advanceForOthers, .deposit: true
        case .income, .reimbursement, .depositRefund: false
        }
    }
}

struct Transaction: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: TransactionKind
    var amountMinor: Int64
    var currency: String
    var merchant: String
    var account: String
    var category: String
    var note: String
    var occurredAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var isDemo: Bool
    var revision: Int64
    var sourceEventID: UUID?
    var subcategory: String? = nil
    var eurMinor: Int64? = nil
    var exchangeRateEUR: String? = nil
    var personalExpenseEURMinor: Int64? = nil
    var recoverableEURMinor: Int64? = nil
    var tripID: String? = nil
    var paidBy: String? = nil
    var affectsMyAccounts: Bool? = nil
    var sourceMovementID: String? = nil
    var sourceSheet: String? = nil
    var sourceRow: Int? = nil
    var sourceOccurredAt: String? = nil
    var sourceKind: String? = nil
    var accountID: UUID? = nil
    var categoryID: UUID? = nil
    var recurringOccurrenceID: String? = nil
    var eurValueSource: EURValueSource? = nil
    var exchangeRateDate: String? = nil
    var exchangeRateProvider: String? = nil
    var accountAmountMinor: Int64? = nil
    var accountCurrency: String? = nil
}

enum TransactionAccountPrefill {
    static func resolve(original: Transaction?, explicitAccountID: UUID?, defaultAccountID: UUID?,
                        accounts: [LocalAccount]) -> LocalAccount? {
        let requested = original?.accountID ?? explicitAccountID ?? (original == nil ? defaultAccountID : nil)
        guard let requested else { return nil }
        return accounts.first { $0.id == requested && ($0.archivedAt == nil || original?.accountID == requested) }
    }
}

enum Money {
    static func parseMinor(_ input: String) -> Int64? {
        parseMinor(input, currency: "EUR")
    }

    static func parseMinor(_ input: String, currency: String) -> Int64? {
        let exponent = CurrencyMetadata.exponent(for: currency)
        let spaces = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{00A0}\u{202F}"))
        var value = input.trimmingCharacters(in: spaces)
        if value.first == "€" { value.removeFirst() }
        if value.last == "€" { value.removeLast() }
        value = value.trimmingCharacters(in: spaces)
        guard !value.isEmpty, value.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }) else { return nil }

        let dots = value.filter { $0 == "." }.count
        let commas = value.filter { $0 == "," }.count
        let whole: String
        let fraction: String
        if dots > 0 && commas > 0 {
            let decimalSeparator: Character = value.lastIndex(of: ".")! > value.lastIndex(of: ",")! ? "." : ","
            let groupingSeparator: Character = decimalSeparator == "." ? "," : "."
            let parts = value.split(separator: decimalSeparator, omittingEmptySubsequences: false)
            guard parts.count == 2, (exponent == 0 ? parts[1].isEmpty : (1...exponent).contains(parts[1].count)), parts[1].allSatisfy(\.isNumber),
                  validGroupedWhole(String(parts[0]), separator: groupingSeparator) else { return nil }
            whole = parts[0].filter { $0 != groupingSeparator }
            fraction = String(parts[1])
        } else if dots + commas > 0 {
            let separator: Character = dots > 0 ? "." : ","
            let parts = value.split(separator: separator, omittingEmptySubsequences: false)
            if parts.count == 2, (exponent == 0 ? parts[1].isEmpty : (1...exponent).contains(parts[1].count)),
               parts[0].allSatisfy(\.isNumber), parts[1].allSatisfy(\.isNumber) {
                whole = String(parts[0])
                fraction = String(parts[1])
            } else if parts.count > 2 && validGroupedWhole(value, separator: separator) {
                whole = value.filter { $0 != separator }
                fraction = ""
            } else { return nil }
        } else {
            whole = value
            fraction = ""
        }
        guard !whole.isEmpty, whole.allSatisfy(\.isNumber), let units = Int64(whole) else { return nil }
        let paddedFraction = fraction.padding(toLength: exponent, withPad: "0", startingAt: 0)
        guard let fractionalMinor = Int64(paddedFraction.isEmpty ? "0" : paddedFraction) else { return nil }
        let multiplier = (0..<exponent).reduce(Int64(1)) { value, _ in value * 10 }
        let (base, overflow) = units.multipliedReportingOverflow(by: multiplier)
        guard !overflow else { return nil }
        let (minor, addOverflow) = base.addingReportingOverflow(fractionalMinor)
        return addOverflow ? nil : minor
    }

    private static func validGroupedWhole(_ value: String, separator: Character) -> Bool {
        let groups = value.split(separator: separator, omittingEmptySubsequences: false)
        guard groups.count > 1, (1...3).contains(groups[0].count), groups[0].allSatisfy(\.isNumber) else { return false }
        return groups.dropFirst().allSatisfy { $0.count == 3 && $0.allSatisfy(\.isNumber) }
    }

    static func parseEUR(_ input: String) -> Int64? { parseMinor(input) }

    static func parseSignedMinor(_ input: String) -> Int64? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("-") {
            guard let magnitude = parseMinor(String(trimmed.dropFirst())) else { return nil }
            return -magnitude
        }
        return parseMinor(trimmed)
    }

    static func editString(_ minor: Int64, currency: String = "EUR", locale: Locale = AppLanguage.formatLocale) -> String {
        let exponent = CurrencyMetadata.exponent(for: currency)
        let amount = NSDecimalNumber(value: minor).dividing(by: NSDecimalNumber(decimal: CurrencyMetadata.divisor(for: currency)))
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = exponent
        formatter.maximumFractionDigits = exponent
        return formatter.string(from: amount) ?? amount.stringValue
    }

    static func format(_ minor: Int64, currency: String = "EUR", locale: Locale = AppLanguage.formatLocale) -> String {
        let amount = NSDecimalNumber(value: minor).dividing(by: NSDecimalNumber(decimal: CurrencyMetadata.divisor(for: currency)))
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currency
        return formatter.string(from: amount) ?? "\(minor) \(currency)"
    }
}

enum AmountInputError: Error, Equatable {
    case empty, negative, zero, malformed

    var message: String {
        switch self {
        case .empty: AppLanguage.localized("Enter an amount.")
        case .negative: AppLanguage.localized("Use a positive amount; the transaction type sets its direction.")
        case .zero: AppLanguage.localized("Amount must be greater than zero.")
        case .malformed: AppLanguage.localized("Enter a valid amount with at most two decimal places.")
        }
    }
}

extension Money {
    static func validatedPositiveAmount(_ input: String) -> Result<Int64, AmountInputError> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .failure(.empty) }
        if trimmed.hasPrefix("-") || trimmed.hasPrefix("−") { return .failure(.negative) }
        guard let cents = parseMinor(trimmed) else { return .failure(.malformed) }
        if cents == 0 { return .failure(.zero) }
        return .success(cents)
    }
}

enum TransactionEditPolicy {
    static func values(original: Transaction?, kind: TransactionKind, newEURMinor: Int64) -> (personal: Int64, recoverable: Int64) {
        guard let original, original.kind == kind else {
            switch kind {
            case .expense: return (newEURMinor, 0)
            case .reimbursement: return (-newEURMinor, 0)
            case .advanceForOthers, .deposit: return (0, newEURMinor)
            case .income, .pacInvestment, .depositRefund: return (0, 0)
            }
        }
        let oldEUR = original.eurMinor ?? (original.currency == "EUR" ? original.amountMinor : 0)
        let oldPersonal = original.personalExpenseEURMinor ?? (kind == .expense ? oldEUR : 0)
        let oldRecoverable = original.recoverableEURMinor ?? 0
        let personal: Int64
        if kind == .expense && oldPersonal == oldEUR { personal = newEURMinor }
        else if kind == .reimbursement && oldPersonal == -oldEUR { personal = -newEURMinor }
        else { personal = oldPersonal }
        let recoverable = (kind == .advanceForOthers || kind == .deposit) && oldRecoverable == oldEUR
            ? newEURMinor : oldRecoverable
        return (personal, recoverable)
    }

    static func hasSeparatePersonalShare(_ item: Transaction) -> Bool {
        guard item.kind == .expense, let personal = item.personalExpenseEURMinor else { return false }
        let total = item.eurMinor ?? (item.currency == "EUR" ? item.amountMinor : 0)
        return personal != total
    }
}

struct HistoricalAccount: Identifiable, Codable {
    var id: String { sourceName }
    let sourceName: String
    let kind: String?
    let currency: String?
    let openingAt: String?
    let openingEURMinor: Int64?
    let isActive: Bool?
    let note: String?
    let sourceSheet: String
    let sourceRow: Int
    let cellValuesJSON: String
}

struct HistoricalTrip: Identifiable, Codable {
    let id: String
    let name: String
    let destination: String?
    let startsAt: String?
    let endsAt: String?
    let currency: String?
    let note: String?
    let sourceSheet: String
    let sourceRow: Int
    let cellValuesJSON: String
}

struct HistoricalRecurringRule: Identifiable, Codable {
    let id: String
    let ruleKind: String
    let name: String
    let amountMinor: Int64
    let currency: String
    let frequency: String?
    let nominalDay: Int?
    let startsAt: String?
    let endsAt: String?
    let account: String?
    let isActive: Bool?
    let investmentKind: String?
    let dateRule: String?
    let initialContributionMinor: Int64?
    let initialContributionAt: String?
    let note: String?
    let sourceSheet: String
    let sourceRow: Int
    let cellValuesJSON: String
}

struct HistoricalExchangeRate: Codable {
    let sourceRow: Int
    let date: String
    let currency: String
    let eurRate: String
    let status: String?
    let origin: String?
    let sourceKey: String?
    let cellValuesJSON: String
}

struct LedgerTotals: Equatable {
    let personalSpendingEURMinor: Int64
    let totalExpensesEURMinor: Int64
    let incomeEURMinor: Int64
    let pacInvestedEURMinor: Int64

    init(transactions: [Transaction]) {
        var personal: Int64 = 0
        var expenses: Int64 = 0
        var income: Int64 = 0
        var invested: Int64 = 0
        for item in transactions where item.deletedAt == nil {
            let eur = item.eurMinor ?? (item.currency == "EUR" ? item.amountMinor : 0)
            personal += item.personalExpenseEURMinor ?? (item.kind == .expense && item.currency == "EUR" ? item.amountMinor : 0)
            switch item.kind {
            case .expense: expenses += eur
            case .income, .reimbursement: income += eur
            case .pacInvestment: invested += eur
            case .advanceForOthers, .deposit, .depositRefund: break
            }
        }
        personalSpendingEURMinor = personal
        totalExpensesEURMinor = expenses
        incomeEURMinor = income
        pacInvestedEURMinor = invested
    }
}

struct TransactionFilter: Equatable {
    var query = ""
    var kind: TransactionKind?
    var category: String?
    var account: String?
    var tripID: String?
    var currency: String?
    var dateInterval: LedgerDateInterval?
    var transactionIDs: Set<UUID>?
    var accountKeys: Set<String>?
    var categoryKeys: Set<String>?
    var kindKeys: Set<String>?
    var tripIDs: Set<String>?
    var currencies: Set<String>?

    static func accountKey(_ item: Transaction) -> String {
        item.accountID.map { "id:\($0.uuidString)" } ?? "label:\(item.account)"
    }

    static func categoryKey(_ item: Transaction) -> String {
        if let id = item.categoryID { return "id:\(id.uuidString)" }
        return item.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "uncategorized" : "label:\(item.category)"
    }

    func apply(to transactions: [Transaction], tripNames: [String: String] = [:],
               timeZone: TimeZone = .current) -> [Transaction] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return transactions.filter { item in
            guard item.deletedAt == nil,
                  kind == nil || item.kind == kind,
                  category == nil || item.category == category,
                  account == nil || item.account == account,
                  tripID == nil || item.tripID == tripID,
                  currency == nil || item.currency == currency,
                  dateInterval?.contains(item.occurredAt, timeZone: timeZone) != false,
                  transactionIDs?.contains(item.id) != false,
                  accountKeys?.contains(Self.accountKey(item)) != false,
                  categoryKeys?.contains(Self.categoryKey(item)) != false,
                  kindKeys?.contains(item.kind.rawValue) != false,
                  tripIDs?.contains(item.tripID ?? "") != false,
                  currencies?.contains(item.currency) != false else { return false }
            guard !needle.isEmpty else { return true }
            return [item.merchant, item.account, item.category, item.subcategory ?? "", item.note,
                    item.paidBy ?? "", tripNames[item.tripID ?? ""] ?? "", item.kind.title,
                    AppLanguage.localized(item.kind.title)]
                .contains { $0.localizedCaseInsensitiveContains(needle) }
        }
    }
}

struct NotificationEvent: Identifiable, Codable, Equatable {
    var id: UUID
    var sourceApp: String
    var title: String
    var subtitle: String
    var message: String
    var receivedAt: Date?
    var capturedAt: Date
    var fingerprint: String

    static func make(sourceApp: String, title: String, subtitle: String, message: String,
                     receivedAt: Date?, capturedAt: Date = .now) -> NotificationEvent? {
        let source = sourceApp.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = [source, title, subtitle, message]
        guard !source.isEmpty, fields.allSatisfy({ $0.utf8.count <= 8_192 }),
              fields.contains(where: { !$0.isEmpty }) else { return nil }
        var bytes = Data()
        for field in fields {
            let data = Data(NotificationParser.normalize(field).utf8)
            var length = UInt32(data.count).bigEndian
            withUnsafeBytes(of: &length) { bytes.append(contentsOf: $0) }
            bytes.append(data)
        }
        if let receivedAt {
            var milliseconds = Int64((receivedAt.timeIntervalSince1970 * 1_000).rounded()).bigEndian
            withUnsafeBytes(of: &milliseconds) { bytes.append(contentsOf: $0) }
        } else {
            // Without a payload date, identical text can represent a later real purchase.
            // A ten-minute bucket keeps the canonical source-event identity bounded;
            // the exact and semantic tables still check the actual time window.
            var bucket = Int64((capturedAt.timeIntervalSince1970 / 600).rounded(.down)).bigEndian
            withUnsafeBytes(of: &bucket) { bytes.append(contentsOf: $0) }
        }
        let fingerprint = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return NotificationEvent(id: UUID(), sourceApp: source, title: title, subtitle: subtitle,
                                 message: message, receivedAt: receivedAt, capturedAt: capturedAt,
                                 fingerprint: fingerprint)
    }
}

struct BackupEnvelope: Codable {
    let schemaVersion: Int
    let exportID: UUID
    let exportedAt: Date
    let transactions: [Transaction]
    let notificationEvents: [NotificationEvent]
    let operations: [LedgerOperation]
    let historical: HistoricalImportBackup?
    let parserSources: [ParserSource]
    let parserRules: [ParserRule]
    let localAccounts: [LocalAccount]
    let ledgerCategories: [LedgerCategory]
    let recurringRules: [RecurringRule]
    let recurringOccurrences: [RecurringOccurrence]
    let parserRuleVersions: [ParserRuleRevision]
    let parserAttempts: [ParserAttempt]
}

struct HistoricalProvenanceRecord: Codable {
    let sourceID: String
    let transactionID: UUID
    let sourceFingerprint: String
    let sourceSheet: String
    let sourceRow: Int
    let sourcePayloadJSON: String
}

struct HistoricalImportBackup: Codable {
    let sourceDigest: String?
    let provenance: [HistoricalProvenanceRecord]
    let accounts: [HistoricalAccount]
    let trips: [HistoricalTrip]
    let recurringRules: [HistoricalRecurringRule]
    let exchangeRates: [HistoricalExchangeRate]
    let sourceRows: [HistoricalSourceRow]
    let importWarnings: [HistoricalImportWarning]
}

struct HistoricalSourceRow: Codable {
    let sheet: String
    let row: Int
    let cellValuesJSON: String
}

struct HistoricalImportWarning: Codable {
    let sheet: String
    let row: Int
    let code: String
    let detail: String?
}

struct LedgerOperation: Identifiable, Codable {
    let id: UUID
    let entityID: UUID
    let action: String
    let revision: Int64
    let payloadJSON: String
    let createdAt: Date
}
