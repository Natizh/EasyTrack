import Foundation

enum TransactionExportError: LocalizedError {
    case invalidDates, invalidTimeZone, tooPreciseForXLSX, tooLarge, cancelled

    var errorDescription: String? {
        switch self {
        case .invalidDates: AppLanguage.localized("Choose a valid start date on or before the end date.")
        case .invalidTimeZone: AppLanguage.localized("The export time zone is unavailable. Reopen export and try again.")
        case .tooPreciseForXLSX: AppLanguage.localized("An amount exceeds Excel's 15-digit numeric precision. Use CSV to preserve every cent.")
        case .tooLarge: AppLanguage.localized("The export is too large for a single spreadsheet. Narrow the filters.")
        case .cancelled: AppLanguage.localized("Export was cancelled.")
        }
    }
}

enum TransactionExportFormat: String, CaseIterable, Identifiable {
    case csv, xlsx
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

enum TransactionCSVStyle: String, CaseIterable, Identifiable {
    case interoperable, italianExcel
    var id: String { rawValue }
    var title: String { self == .interoperable ? "Interoperable" : "Italian Excel" }
    var separator: Character { self == .interoperable ? "," : ";" }
    var decimalSeparator: Character { self == .interoperable ? "." : "," }
    var hasBOM: Bool { self == .italianExcel }
}

enum TransactionExportColumns: String, CaseIterable, Identifiable {
    case basic, detailed
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum TransactionExportDatePreset: String, CaseIterable, Identifiable {
    case allTime, currentMonth, previousMonth, currentYear, previousYear, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .allTime: "All time"
        case .currentMonth: "Current month"
        case .previousMonth: "Previous month"
        case .currentYear: "Current year"
        case .previousYear: "Previous year"
        case .custom: "Custom dates"
        }
    }
}

struct TransactionExportOptions {
    var format: TransactionExportFormat = .csv
    var csvStyle: TransactionCSVStyle = .interoperable
    var columns: TransactionExportColumns = .basic
    var includeTechnicalIDs = false
    var includeSummary = false
    var timeZoneIdentifier = TimeZone.current.identifier
}

struct TransactionExportFilter {
    var datePreset: TransactionExportDatePreset = .allTime
    var customStart: LocalDay?
    var customEnd: LocalDay?
    var accountKeys: Set<String>?
    var categoryKeys: Set<String>?
    var kindKeys: Set<String>?
    var tripKeys: Set<String>?
    var currencyKeys: Set<String>?
    var query = ""

    func dates(now: Date, timeZone: TimeZone) throws -> ClosedRange<LocalDay>? {
        let today = LocalDay(date: now, timeZone: timeZone)
        let calendar = Calendar(identifier: .gregorian)
        switch datePreset {
        case .allTime: return nil
        case .custom:
            guard let customStart, let customEnd, customStart <= customEnd else { throw TransactionExportError.invalidDates }
            return customStart...customEnd
        case .currentMonth, .previousMonth:
            let year = datePreset == .previousMonth && today.month == 1 ? today.year - 1 : today.year
            let month = datePreset == .previousMonth ? (today.month == 1 ? 12 : today.month - 1) : today.month
            var cal = calendar
            cal.timeZone = timeZone
            guard let first = cal.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)),
                  let following = cal.date(byAdding: .month, value: 1, to: first),
                  let last = cal.date(byAdding: .day, value: -1, to: following) else { throw TransactionExportError.invalidDates }
            return LocalDay(date: first, timeZone: timeZone)...LocalDay(date: last, timeZone: timeZone)
        case .currentYear, .previousYear:
            let year = today.year - (datePreset == .previousYear ? 1 : 0)
            return LocalDay(isoString: String(format: "%04d-01-01", year))!...LocalDay(isoString: String(format: "%04d-12-31", year))!
        }
    }
}

struct TransactionExportChoice: Identifiable, Hashable {
    let id: String
    let title: String
}

struct HistoricalOriginalValues: Decodable, Equatable {
    let amountMinor: Int64?
    let currency: String?
    let eurMinor: Int64?
    let exchangeRateEUR: String?
    let occurredAt: String?

    enum CodingKeys: String, CodingKey {
        case amountMinor = "amount_minor", currency, eurMinor = "eur_minor"
        case exchangeRateEUR = "exchange_rate_eur", occurredAt = "occurred_at"
    }
}

struct TransactionExportSnapshot {
    let transactions: [Transaction]
    let accountNames: [UUID: String]
    let categoryNames: [UUID: String]
    let tripNames: [String: String]
    let historicalOriginals: [UUID: HistoricalOriginalValues]
    var reimbursementStatuses: [UUID: ExpenseReimbursementStatus] = [:]

    static func accountKey(_ item: Transaction) -> String {
        item.accountID.map { "id:\($0.uuidString)" } ?? "label:\(item.account)"
    }

    static func categoryKey(_ item: Transaction) -> String {
        if let id = item.categoryID { return "id:\(id.uuidString)" }
        return item.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "uncategorized" : "label:\(item.category)"
    }

    var exportableTransactions: [Transaction] {
        transactions.filter { $0.deletedAt == nil && !$0.isDemo }
    }

    var accountChoices: [TransactionExportChoice] {
        choices { item in TransactionExportChoice(id: Self.accountKey(item),
            title: item.accountID.flatMap { accountNames[$0] } ?? (item.account.isEmpty ? "Unspecified" : item.account)) }
    }
    var categoryChoices: [TransactionExportChoice] {
        var result = choices { item in TransactionExportChoice(id: Self.categoryKey(item),
            title: item.categoryID.flatMap { categoryNames[$0] } ??
                (item.category.isEmpty ? "Uncategorized" : item.category)) }
        if !result.contains(where: { $0.id == "uncategorized" }) {
            result.insert(TransactionExportChoice(id: "uncategorized", title: "Uncategorized"), at: 0)
        }
        return result
    }
    var tripChoices: [TransactionExportChoice] {
        choices { item in
            guard let id = item.tripID else { return nil }
            return TransactionExportChoice(id: id, title: tripNames[id] ?? id)
        }
    }
    var currencyChoices: [TransactionExportChoice] {
        choices { TransactionExportChoice(id: $0.currency, title: $0.currency) }
    }
    var kindChoices: [TransactionExportChoice] {
        TransactionKind.allCases.map { TransactionExportChoice(id: $0.rawValue, title: $0.title) }
    }

    private func choices(_ make: (Transaction) -> TransactionExportChoice?) -> [TransactionExportChoice] {
        var found: [String: TransactionExportChoice] = [:]
        for item in exportableTransactions {
            if let choice = make(item) { found[choice.id] = choice }
        }
        return found.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func select(filter: TransactionExportFilter, activityFilter: TransactionFilter? = nil,
                options: TransactionExportOptions = .init(), now: Date = .now) throws -> TransactionExportSelection {
        guard let zone = TimeZone(identifier: options.timeZoneIdentifier) else { throw TransactionExportError.invalidTimeZone }
        let range = try filter.dates(now: now, timeZone: zone)
        let activity = activityFilter?.apply(to: exportableTransactions, tripNames: tripNames) ?? exportableTransactions
        let needle = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = activity.filter { item in
            if let range, !range.contains(LocalDay(date: item.occurredAt, timeZone: zone)) { return false }
            if let keys = filter.accountKeys, !keys.contains(Self.accountKey(item)) { return false }
            if let keys = filter.categoryKeys, !keys.contains(Self.categoryKey(item)) { return false }
            if let keys = filter.kindKeys, !keys.contains(item.kind.rawValue) { return false }
            if let keys = filter.tripKeys, !keys.contains(item.tripID ?? "") { return false }
            if let keys = filter.currencyKeys, !keys.contains(item.currency) { return false }
            guard !needle.isEmpty else { return true }
            let fields = [item.merchant, item.account, item.accountID.flatMap { accountNames[$0] } ?? "",
                          item.category, item.categoryID.flatMap { categoryNames[$0] } ?? "",
                          item.subcategory ?? "", item.note, item.paidBy ?? "",
                          tripNames[item.tripID ?? ""] ?? "", item.kind.title,
                          AppLanguage.localized(item.kind.title)]
            return fields.contains { $0.localizedCaseInsensitiveContains(needle) }
        }.sorted {
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let rows = selected.map { item in
            TransactionExportRow(item: item,
                account: item.accountID.flatMap { accountNames[$0] } ?? item.account,
                category: item.categoryID.flatMap { categoryNames[$0] } ?? item.category,
                trip: item.tripID.flatMap { tripNames[$0] } ?? item.tripID,
                original: historicalOriginals[item.id],
                reimbursementStatus: reimbursementStatuses[item.id])
        }
        if rows.contains(where: { $0.item.kind.isOutflow && $0.currentEURMinor == Int64.min }) {
            throw TransactionExportError.tooLarge
        }
        return TransactionExportSelection(rows: rows, timeZone: zone)
    }
}

struct TransactionExportRow {
    let item: Transaction
    let account: String
    let category: String
    let trip: String?
    let original: HistoricalOriginalValues?
    let reimbursementStatus: ExpenseReimbursementStatus?

    var currentEURMinor: Int64? { item.eurMinor ?? (item.currency == "EUR" ? item.amountMinor : nil) }
    var personalEURMinor: Int64? {
        item.personalExpenseEURMinor ??
            (item.kind == .expense && item.currency == "EUR" ? item.amountMinor : nil)
    }
    var recoverableEURMinor: Int64? { item.recoverableEURMinor }
    var signedEURMinor: Int64? {
        guard let amount = currentEURMinor else { return nil }
        return item.kind.isOutflow && amount == Int64.min ? nil : (item.kind.isOutflow ? -amount : amount)
    }
}

struct TransactionExportTotals: Equatable {
    var count = 0
    var personal = Int64(0)
    var expenses = Int64(0)
    var income = Int64(0)
    var pac = Int64(0)

    mutating func add(_ row: TransactionExportRow) throws {
        count += 1
        try Self.addChecked(row.personalEURMinor ?? 0, to: &personal)
        let eur = row.currentEURMinor ?? 0
        switch row.item.kind {
        case .expense: try Self.addChecked(eur, to: &expenses)
        case .income, .reimbursement: try Self.addChecked(eur, to: &income)
        case .pacInvestment: try Self.addChecked(eur, to: &pac)
        case .advanceForOthers, .deposit, .depositRefund: break
        }
    }

    private static func addChecked(_ amount: Int64, to total: inout Int64) throws {
        let (next, overflow) = total.addingReportingOverflow(amount)
        guard !overflow else { throw TransactionExportError.tooLarge }
        total = next
    }
}

struct TransactionExportSelection {
    let rows: [TransactionExportRow]
    let timeZone: TimeZone

    func totals() throws -> TransactionExportTotals {
        var result = TransactionExportTotals()
        for row in rows { try result.add(row) }
        return result
    }

    func grouped(_ key: (TransactionExportRow) -> String) throws -> [(String, TransactionExportTotals)] {
        var result: [String: TransactionExportTotals] = [:]
        for row in rows {
            var total = result[key(row), default: TransactionExportTotals()]
            try total.add(row)
            result[key(row)] = total
        }
        return result.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { ($0.key, $0.value) }
    }
}

enum TransactionExportMoney {
    static func decimal(_ minor: Int64, separator: Character = ".", exponent: Int = 2) -> String {
        let magnitude = minor.magnitude
        let divisor = (0..<exponent).reduce(UInt64(1)) { value, _ in value * 10 }
        guard exponent > 0 else { return "\(minor < 0 ? "-" : "")\(magnitude)" }
        let rawFraction = String(magnitude % divisor)
        let fraction = String(repeating: "0", count: max(0, exponent - rawFraction.count)) + rawFraction
        return "\(minor < 0 ? "-" : "")\(magnitude / divisor)\(separator)\(fraction)"
    }

    static func xlsxDecimal(_ minor: Int64) throws -> String {
        guard String(minor.magnitude).count <= 15 else { throw TransactionExportError.tooPreciseForXLSX }
        return decimal(minor)
    }
}

enum TransactionExportCell {
    case text(String), money(Int64, isEUR: Bool), integer(Int), date(Date), empty
}

enum TransactionExportColumn: String, CaseIterable {
    case occurredAt, description, kind, account, category, currentAmount, currentCurrency,
         currentEUR, personalEUR, recoverableEUR, signedEUR, note,
         subcategory, trip, payer, affectsAccounts, historicalRate, eurValueSource,
         exchangeRateDate, exchangeRateProvider, accountAmount, accountCurrency,
         importedAmount, importedCurrency, importedEUR, importedAt,
         reimbursementStatus, reimbursementExpected, reimbursementReceived,
         reimbursementOutstanding, reimbursementWrittenOff, linkedReimbursementIDs,
         transactionID, sourceMovementID, sourceEventID, recurringOccurrenceID, sourceSheet, sourceRow

    static func selected(_ options: TransactionExportOptions) -> [Self] {
        var columns: [Self] = [.occurredAt, .description, .kind, .account, .category,
                               .currentAmount, .currentCurrency, .currentEUR, .personalEUR,
                               .recoverableEUR, .signedEUR, .note]
        if options.columns == .detailed {
            columns += [.subcategory, .trip, .payer, .affectsAccounts, .historicalRate,
                        .eurValueSource, .exchangeRateDate, .exchangeRateProvider,
                        .accountAmount, .accountCurrency,
                        .importedAmount, .importedCurrency, .importedEUR, .importedAt,
                        .reimbursementStatus, .reimbursementExpected, .reimbursementReceived,
                        .reimbursementOutstanding, .reimbursementWrittenOff, .linkedReimbursementIDs]
        }
        if options.includeTechnicalIDs {
            columns += [.transactionID, .sourceMovementID, .sourceEventID,
                        .recurringOccurrenceID, .sourceSheet, .sourceRow]
        }
        return columns
    }

    var title: String {
        switch self {
        case .occurredAt: "Occurred at"
        case .description: "Description"
        case .kind: "Kind"
        case .account: "Account"
        case .category: "Category"
        case .currentAmount: "Current amount"
        case .currentCurrency: "Current currency"
        case .currentEUR: "Current EUR amount"
        case .personalEUR: "Personal spending EUR"
        case .recoverableEUR: "Recoverable EUR"
        case .signedEUR: "Signed directional EUR"
        case .note: "Note"
        case .subcategory: "Subcategory"
        case .trip: "Trip"
        case .payer: "Payer"
        case .affectsAccounts: "Affects my accounts"
        case .historicalRate: "Historical EUR exchange rate"
        case .eurValueSource: "EUR value source"
        case .exchangeRateDate: "Exchange rate date"
        case .exchangeRateProvider: "Exchange rate provider"
        case .accountAmount: "Account charged amount"
        case .accountCurrency: "Account currency"
        case .importedAmount: "Imported amount"
        case .importedCurrency: "Imported currency"
        case .importedEUR: "Imported EUR amount"
        case .importedAt: "Imported timestamp"
        case .reimbursementStatus: "Reimbursement status"
        case .reimbursementExpected: "Expected reimbursement EUR"
        case .reimbursementReceived: "Received reimbursement EUR"
        case .reimbursementOutstanding: "Outstanding reimbursement EUR"
        case .reimbursementWrittenOff: "Written-off reimbursement EUR"
        case .linkedReimbursementIDs: "Linked reimbursement IDs"
        case .transactionID: "Transaction ID"
        case .sourceMovementID: "Source movement ID"
        case .sourceEventID: "Source event ID"
        case .recurringOccurrenceID: "Recurring occurrence ID"
        case .sourceSheet: "Source sheet"
        case .sourceRow: "Source row"
        }
    }

    var width: Double {
        switch self {
        case .occurredAt, .importedAt: 22
        case .description, .note: 34
        case .transactionID, .sourceEventID, .sourceMovementID, .recurringOccurrenceID,
             .linkedReimbursementIDs: 38
        default: 20
        }
    }

    func cell(_ row: TransactionExportRow) -> TransactionExportCell {
        let item = row.item
        func amount(_ value: Int64?, eur: Bool = true) -> TransactionExportCell {
            value.map { .money($0, isEUR: eur) } ?? .empty
        }
        return switch self {
        case .occurredAt: .date(item.occurredAt)
        case .description: .text(item.merchant)
        case .kind: .text(item.kind.title)
        case .account: .text(row.account)
        case .category: .text(row.category.isEmpty ? "Uncategorized" : row.category)
        case .currentAmount:
            CurrencyMetadata.exponent(for: item.currency) == 2 ? amount(item.amountMinor, eur: false) :
                .text(TransactionExportMoney.decimal(item.amountMinor,
                    exponent: CurrencyMetadata.exponent(for: item.currency)))
        case .currentCurrency: .text(item.currency)
        case .currentEUR: amount(row.currentEURMinor)
        case .personalEUR: amount(row.personalEURMinor)
        case .recoverableEUR: amount(row.recoverableEURMinor)
        case .signedEUR: amount(row.signedEURMinor)
        case .note: .text(item.note)
        case .subcategory: row.item.subcategory.map { .text($0) } ?? .empty
        case .trip: row.trip.map { .text($0) } ?? .empty
        case .payer: item.paidBy.map { .text($0) } ?? .empty
        case .affectsAccounts: item.affectsMyAccounts.map { .text($0 ? "Yes" : "No") } ?? .empty
        case .historicalRate: item.exchangeRateEUR.map { .text($0) } ?? .empty
        case .eurValueSource: item.eurValueSource.map { .text($0.rawValue) } ?? .empty
        case .exchangeRateDate: item.exchangeRateDate.map { .text($0) } ?? .empty
        case .exchangeRateProvider: item.exchangeRateProvider.map { .text($0) } ?? .empty
        case .accountAmount:
            if let value = item.accountAmountMinor, let currency = item.accountCurrency {
                .text(TransactionExportMoney.decimal(value, exponent: CurrencyMetadata.exponent(for: currency)))
            } else { .empty }
        case .accountCurrency: item.accountCurrency.map { .text($0) } ?? .empty
        case .importedAmount: amount(row.original?.amountMinor, eur: false)
        case .importedCurrency: row.original?.currency.map { .text($0) } ?? .empty
        case .importedEUR: amount(row.original?.eurMinor)
        case .importedAt: row.original?.occurredAt.map { .text($0) } ?? .empty
        case .reimbursementStatus: row.reimbursementStatus.map { .text($0.title) } ?? .empty
        case .reimbursementExpected: amount(row.reimbursementStatus?.expectedEURMinor)
        case .reimbursementReceived: amount(row.reimbursementStatus?.receivedEURMinor)
        case .reimbursementOutstanding: amount(row.reimbursementStatus?.outstandingEURMinor)
        case .reimbursementWrittenOff: amount(row.reimbursementStatus?.writtenOffEURMinor)
        case .linkedReimbursementIDs: row.reimbursementStatus.map {
            .text($0.linkedTransactionIDs.map(\.uuidString).joined(separator: " | "))
        } ?? .empty
        case .transactionID: .text(item.id.uuidString)
        case .sourceMovementID: item.sourceMovementID.map { .text($0) } ?? .empty
        case .sourceEventID: item.sourceEventID.map { .text($0.uuidString) } ?? .empty
        case .recurringOccurrenceID: item.recurringOccurrenceID.map { .text($0) } ?? .empty
        case .sourceSheet: item.sourceSheet.map { .text($0) } ?? .empty
        case .sourceRow: item.sourceRow.map { .text(String($0)) } ?? .empty
        }
    }
}

enum TransactionCSVWriter {
    static func encode(_ selection: TransactionExportSelection, options: TransactionExportOptions) throws -> Data {
        let columns = TransactionExportColumn.selected(options)
        let delimiter = String(options.csvStyle.separator)
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = selection.timeZone
        formatter.formatOptions = [.withInternetDateTime]
        var lines = [columns.map { quote($0.title, separator: options.csvStyle.separator, untrusted: false) }.joined(separator: delimiter)]
        lines.reserveCapacity(selection.rows.count + 1)
        for row in selection.rows {
            try Task.checkCancellation()
            let fields = columns.map { column -> String in
                switch column.cell(row) {
                case .empty: return ""
                case .date(let date): return quote(formatter.string(from: date), separator: options.csvStyle.separator, untrusted: false)
                case .money(let cents, _): return TransactionExportMoney.decimal(cents, separator: options.csvStyle.decimalSeparator)
                case .integer(let value): return String(value)
                case .text(let value): return quote(value, separator: options.csvStyle.separator, untrusted: true)
                }
            }
            lines.append(fields.joined(separator: delimiter))
        }
        var data = Data()
        if options.csvStyle.hasBOM { data.append(contentsOf: [0xEF, 0xBB, 0xBF]) }
        data.append(Data((lines.joined(separator: "\r\n") + "\r\n").utf8))
        return data
    }

    private static func quote(_ text: String, separator: Character, untrusted: Bool) -> String {
        let firstSignificant = text.unicodeScalars.first { !CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }
        let dangerous = untrusted && firstSignificant.map { "=+-@".unicodeScalars.contains($0) } == true
        let safe = (dangerous ? "\t" : "") + text
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
