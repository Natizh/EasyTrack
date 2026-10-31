import CryptoKit
import Foundation
import SQLite3

struct ImportIssue: Codable, Equatable {
    let table: String
    let sourceRow: Int?
    let field: String
    let reason: String

    var summary: String {
        let location = sourceRow.map { "\(table) row \($0)" } ?? table
        return "\(location): \(field) — \(reason)"
    }
}

enum SeedImportError: LocalizedError, CustomStringConvertible {
    case invalidSchema(String)
    case invalidRows([ImportIssue])
    case changedSource(Int)
    case database(String)

    var errorDescription: String? {
        switch self {
        case .invalidSchema(let message): "Unsupported seed schema: \(message)"
        case .invalidRows(let issues): "Import validation found \(issues.count) issue(s). First: \(issues.first?.summary ?? "unknown")"
        case .changedSource(let count): "\(count) existing historical identities have changed source data. No records were changed."
        case .database(let message): "Seed database could not be read: \(message)"
        }
    }
    var description: String { errorDescription ?? "Seed import failed" }
}

struct ImportedMovement {
    var transaction: Transaction
    let sourceFingerprint: String
    let sourcePayloadJSON: String
}

struct HistoricalReimbursementReconciliation: Equatable {
    let linkID: String
    let expenseSourceID: String
    let expectedEURMinor: Int64
    let receiptSourceID: String?
    let receivedEURMinor: Int64
    let status: String
    let note: String?
}

struct ValidatedSeed {
    let schemaVersion: Int
    let digest: String
    let movements: [ImportedMovement]
    let accounts: [HistoricalAccount]
    let trips: [HistoricalTrip]
    let rules: [HistoricalRecurringRule]
    let rates: [HistoricalExchangeRate]
    let sourceRows: [HistoricalSourceRow]
    let warnings: [HistoricalImportWarning]
    let reimbursements: [HistoricalReimbursementReconciliation]
    let unmatchedAccountLabels: Int
    let missingAccountLabels: Int

    var counts: [String: Int] {
        ["movements": movements.count, "accounts": accounts.count, "trips": trips.count,
         "recurring rules": rules.count, "exchange rates": rates.count,
         "source rows": sourceRows.count, "migration warnings": warnings.count,
         "reimbursements": reimbursements.count]
    }
}

struct HistoricalImportPreview {
    let movements: Int
    let newMovements: Int
    let alreadyImported: Int
    let changedIdentities: Int
    let accounts: Int
    let trips: Int
    let recurringRules: Int
    let exchangeRates: Int
    let migrationWarnings: Int
    let reimbursements: Int
    let unmatchedAccountLabels: Int
    let missingAccountLabels: Int
    let sourceChanged: Bool
    let missingFromSource: Int
    var recurringConflicts: [HistoricalImportConflict] = []
    var rowConflicts: [HistoricalRowConflict] = []
    var duplicateCandidates: [HistoricalDuplicateCandidate] = []
    var incomingTotals: LedgerTotals? = nil

    var canImport: Bool { true }
}

enum HistoricalImportDecision: String, Codable {
    case samePayment, separatePayment
    case keepLocal, applySource
    case importSeparately, skipIncoming
}

struct HistoricalRowConflict: Identifiable {
    let sourceID: String
    let imported: Transaction
    let existing: Transaction
    let localEdited: Bool
    let protectedReason: String?

    var id: String { "changed:\(sourceID)" }
    var canApplySource: Bool { !localEdited && protectedReason == nil }
}

struct HistoricalDuplicateCandidate: Identifiable {
    let sourceID: String
    let imported: Transaction
    let existing: [Transaction]

    var id: String { "duplicate:\(sourceID)" }
}

struct HistoricalImportConflict: Identifiable {
    let occurrenceID: String
    let ruleName: String
    let managedAccountName: String
    let imported: Transaction
    let counted: Transaction
    let reason: String

    var id: String { "\(occurrenceID)|\(imported.id.uuidString)" }
}

final class SeedMapper {
    private var handle: OpaquePointer?
    private let dateFormatter: DateFormatter

    init(url: URL) throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")!
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.isLenient = false
        dateFormatter = formatter
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw SeedImportError.database("cannot open read-only SQLite file")
        }
        guard sqlite3_exec(handle, "PRAGMA query_only=ON", nil, nil, nil) == SQLITE_OK else {
            throw SeedImportError.database("cannot enter read-only mode")
        }
    }

    deinit { sqlite3_close(handle) }

    private func statement(_ sql: String) throws -> OpaquePointer {
        var pointer: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &pointer, nil) == SQLITE_OK, let pointer else {
            throw SeedImportError.invalidSchema("a required query could not be prepared")
        }
        return pointer
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func integer(_ statement: OpaquePointer, _ index: Int32) -> Int64? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, index)
    }

    private func scalar(_ sql: String) throws -> String? {
        let stmt = try statement(sql)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return text(stmt, 0)
    }

    private func originalJSON(_ statement: OpaquePointer) throws -> String {
        var row: [String: Any] = [:]
        for index in 0..<sqlite3_column_count(statement) {
            let name = String(cString: sqlite3_column_name(statement, index))
            switch sqlite3_column_type(statement, index) {
            case SQLITE_INTEGER: row[name] = sqlite3_column_int64(statement, index)
            case SQLITE_FLOAT: row[name] = sqlite3_column_double(statement, index)
            case SQLITE_TEXT: row[name] = text(statement, index) ?? ""
            default: row[name] = NSNull()
            }
        }
        let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func validateJSON(_ value: String?) -> Bool {
        guard let value, let data = value.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private func validRate(_ value: String?) -> Bool {
        guard let value, let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return false }
        return decimal > 0
    }

    static func stableTransactionID(sourceID: String) -> UUID {
        let digest = SHA256.hash(data: Data("EasyTrack historical movement v1:\(sourceID)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func kind(_ source: String) -> TransactionKind? {
        switch source {
        case "Spesa": .expense
        case "Entrata": .income
        case "Investimento PAC": .pacInvestment
        case "Anticipo per altri": .advanceForOthers
        case "Rimborso": .reimbursement
        case "Deposito": .deposit
        case "Rimborso deposito": .depositRefund
        default: nil
        }
    }

    func read(url: URL) throws -> ValidatedSeed {
        guard let versionText = try scalar("SELECT value FROM migration_meta WHERE key = 'schema_version'"),
              let schemaVersion = Int(versionText), [1, 2, 3].contains(schemaVersion) else {
            throw SeedImportError.invalidSchema("migration_meta.schema_version must be 1, 2, or 3")
        }
        guard try scalar("PRAGMA quick_check") == "ok" else {
            throw SeedImportError.invalidSchema("SQLite integrity check failed")
        }
        var required: [String: Set<String>] = [
            "movements": ["id", "occurred_at", "amount_minor", "currency", "eur_minor", "exchange_rate_eur", "description", "kind", "category", "subcategory", "account", "trip_id", "paid_by", "affects_my_accounts", "personal_expense_eur_minor", "recoverable_eur_minor", "needs_review", "review_reason", "origin", "entered_at", "note", "home_type", "source_sheet", "source_row", "source_technical_id", "cached_personal_value", "import_fingerprint"],
            "accounts": ["name", "kind", "currency", "opening_at", "opening_eur_minor", "is_active", "note", "source_sheet", "source_row", "cell_values_json"],
            "trips": ["id", "name", "destination", "starts_at", "ends_at", "currency", "note", "source_sheet", "source_row", "cell_values_json"],
            "recurring_rules": ["id", "rule_kind", "name", "amount_minor", "currency", "frequency", "nominal_day", "starts_at", "ends_at", "account", "is_active", "investment_kind", "date_rule", "initial_contribution_minor", "initial_contribution_at", "note", "source_sheet", "source_row", "cell_values_json"],
            "exchange_rates": ["source_row", "date", "currency", "eur_rate", "status", "origin", "source_key", "cell_values_json"],
            "source_rows": ["source_sheet", "source_row", "cell_values_json"],
            "migration_warnings": ["source_sheet", "source_row", "code", "detail"]
        ]
        if schemaVersion >= 2 {
            required["movements"]?.formUnion([
                "eur_value_source", "exchange_rate_date", "exchange_rate_provider",
                "account_amount_minor", "account_currency"
            ])
        }
        if schemaVersion >= 3 {
            required["reimbursement_reconciliations"] = ["link_id", "expense_source_id",
                "expected_eur_minor", "receipt_source_id", "received_eur_minor", "status", "note"]
        }
        for (table, columns) in required {
            let stmt = try statement("PRAGMA table_info(\(table))")
            var available = Set<String>()
            while sqlite3_step(stmt) == SQLITE_ROW { if let name = text(stmt, 1) { available.insert(name) } }
            sqlite3_finalize(stmt)
            let missing = columns.subtracting(available)
            guard missing.isEmpty else { throw SeedImportError.invalidSchema("\(table) lacks \(missing.sorted().joined(separator: ", "))") }
        }

        var issues: [ImportIssue] = []
        let accounts = try readAccounts(&issues)
        let trips = try readTrips(&issues)
        let tripIDs = Set(trips.map(\.id))
        let rules = try readRules(&issues)
        let rates = try readRates(&issues)
        let sourceRows = try readSourceRows(&issues)
        let sourceRowKeys = Set(sourceRows.map { "\($0.sheet):\($0.row)" })
        let warnings = try readWarnings()
        let reimbursements = schemaVersion >= 3 ? try readReimbursements(&issues) : []
        let accountNames = Set(accounts.map(\.sourceName))
        let (movements, unmatchedAccounts, missingAccounts) = try readMovements(
            schemaVersion: schemaVersion, tripIDs: tripIDs, accountNames: accountNames,
            sourceRowKeys: sourceRowKeys, issues: &issues)
        if sourceRows.count != movements.count {
            issues.append(ImportIssue(table: "source_rows", sourceRow: nil, field: "count", reason: "does not match movements"))
        }
        guard issues.isEmpty else { throw SeedImportError.invalidRows(issues) }
        let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        return ValidatedSeed(schemaVersion: schemaVersion, digest: digest, movements: movements, accounts: accounts,
                             trips: trips, rules: rules, rates: rates, sourceRows: sourceRows,
                             warnings: warnings, reimbursements: reimbursements,
                             unmatchedAccountLabels: unmatchedAccounts,
                             missingAccountLabels: missingAccounts)
    }

    private func readAccounts(_ issues: inout [ImportIssue]) throws -> [HistoricalAccount] {
        let stmt = try statement("SELECT name,kind,currency,opening_at,opening_eur_minor,is_active,note,source_sheet,source_row,cell_values_json FROM accounts")
        defer { sqlite3_finalize(stmt) }
        var rows: [HistoricalAccount] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let row = Int(integer(stmt, 8) ?? 0)
            guard let name = text(stmt, 0), !name.isEmpty, let sheet = text(stmt, 7), row > 0,
                  let json = text(stmt, 9), validateJSON(json) else {
                issues.append(ImportIssue(table: "accounts", sourceRow: row, field: "identity or raw row", reason: "missing or invalid")); continue
            }
            rows.append(HistoricalAccount(sourceName: name, kind: text(stmt, 1), currency: text(stmt, 2),
                                          openingAt: text(stmt, 3), openingEURMinor: integer(stmt, 4),
                                          isActive: integer(stmt, 5).map { $0 != 0 }, note: text(stmt, 6),
                                          sourceSheet: sheet, sourceRow: row, cellValuesJSON: json))
        }
        return rows
    }

    private func readTrips(_ issues: inout [ImportIssue]) throws -> [HistoricalTrip] {
        let stmt = try statement("SELECT id,name,destination,starts_at,ends_at,currency,note,source_sheet,source_row,cell_values_json FROM trips")
        defer { sqlite3_finalize(stmt) }
        var rows: [HistoricalTrip] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let row = Int(integer(stmt, 8) ?? 0)
            guard let id = text(stmt, 0), !id.isEmpty, let name = text(stmt, 1), !name.isEmpty,
                  let sheet = text(stmt, 7), row > 0, let json = text(stmt, 9), validateJSON(json) else {
                issues.append(ImportIssue(table: "trips", sourceRow: row, field: "identity or raw row", reason: "missing or invalid")); continue
            }
            rows.append(HistoricalTrip(id: id, name: name, destination: text(stmt, 2), startsAt: text(stmt, 3),
                                       endsAt: text(stmt, 4), currency: text(stmt, 5), note: text(stmt, 6),
                                       sourceSheet: sheet, sourceRow: row, cellValuesJSON: json))
        }
        return rows
    }

    private func readRules(_ issues: inout [ImportIssue]) throws -> [HistoricalRecurringRule] {
        let stmt = try statement("SELECT id,rule_kind,name,amount_minor,currency,frequency,nominal_day,starts_at,ends_at,account,is_active,investment_kind,date_rule,initial_contribution_minor,initial_contribution_at,note,source_sheet,source_row,cell_values_json FROM recurring_rules")
        defer { sqlite3_finalize(stmt) }
        var rows: [HistoricalRecurringRule] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let row = Int(integer(stmt, 17) ?? 0)
            guard let id = text(stmt, 0), !id.isEmpty, let kind = text(stmt, 1), ["subscription", "investment"].contains(kind),
                  let name = text(stmt, 2), !name.isEmpty, let amount = integer(stmt, 3), amount > 0,
                  let currency = text(stmt, 4), CurrencyMetadata.supportedCodes.contains(currency),
                  let sheet = text(stmt, 16), row > 0, let json = text(stmt, 18), validateJSON(json) else {
                issues.append(ImportIssue(table: "recurring_rules", sourceRow: row, field: "kind, amount, currency, or identity", reason: "unsupported or invalid")); continue
            }
            rows.append(HistoricalRecurringRule(id: id, ruleKind: kind, name: name, amountMinor: amount,
                                                currency: currency, frequency: text(stmt, 5),
                                                nominalDay: integer(stmt, 6).map(Int.init), startsAt: text(stmt, 7),
                                                endsAt: text(stmt, 8), account: text(stmt, 9),
                                                isActive: integer(stmt, 10).map { $0 != 0 },
                                                investmentKind: text(stmt, 11), dateRule: text(stmt, 12),
                                                initialContributionMinor: integer(stmt, 13), initialContributionAt: text(stmt, 14),
                                                note: text(stmt, 15), sourceSheet: sheet, sourceRow: row,
                                                cellValuesJSON: json))
        }
        return rows
    }

    private func readRates(_ issues: inout [ImportIssue]) throws -> [HistoricalExchangeRate] {
        let stmt = try statement("SELECT source_row,date,currency,eur_rate,status,origin,source_key,cell_values_json FROM exchange_rates")
        defer { sqlite3_finalize(stmt) }
        var rows: [HistoricalExchangeRate] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let row = Int(integer(stmt, 0) ?? 0)
            guard row > 0, let date = text(stmt, 1), dateFormatter.date(from: date) != nil,
                  let currency = text(stmt, 2), CurrencyMetadata.supportedCodes.contains(currency),
                  let rate = text(stmt, 3), validRate(rate),
                  let json = text(stmt, 7), validateJSON(json) else {
                issues.append(ImportIssue(table: "exchange_rates", sourceRow: row, field: "date, currency, rate, or raw row", reason: "invalid")); continue
            }
            rows.append(HistoricalExchangeRate(sourceRow: row, date: date, currency: currency, eurRate: rate,
                                               status: text(stmt, 4), origin: text(stmt, 5),
                                               sourceKey: text(stmt, 6), cellValuesJSON: json))
        }
        return rows
    }

    private func readSourceRows(_ issues: inout [ImportIssue]) throws -> [HistoricalSourceRow] {
        let stmt = try statement("SELECT source_sheet,source_row,cell_values_json FROM source_rows")
        defer { sqlite3_finalize(stmt) }
        var rows: [HistoricalSourceRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let row = Int(integer(stmt, 1) ?? 0)
            guard let sheet = text(stmt, 0), !sheet.isEmpty, row > 0,
                  let json = text(stmt, 2), validateJSON(json) else {
                issues.append(ImportIssue(table: "source_rows", sourceRow: row, field: "raw row", reason: "missing or invalid")); continue
            }
            rows.append(HistoricalSourceRow(sheet: sheet, row: row, cellValuesJSON: json))
        }
        return rows
    }

    private func readWarnings() throws -> [HistoricalImportWarning] {
        let stmt = try statement("SELECT source_sheet,source_row,code,detail FROM migration_warnings")
        defer { sqlite3_finalize(stmt) }
        var rows: [HistoricalImportWarning] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(HistoricalImportWarning(sheet: text(stmt, 0) ?? "", row: Int(integer(stmt, 1) ?? 0),
                                                code: text(stmt, 2) ?? "", detail: text(stmt, 3)))
        }
        return rows
    }

    private func readReimbursements(_ issues: inout [ImportIssue]) throws -> [HistoricalReimbursementReconciliation] {
        let stmt = try statement("""
            SELECT link_id,expense_source_id,expected_eur_minor,receipt_source_id,
                   received_eur_minor,status,note
            FROM reimbursement_reconciliations ORDER BY link_id
            """)
        defer { sqlite3_finalize(stmt) }
        var result: [HistoricalReimbursementReconciliation] = []
        var ids = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let linkID = text(stmt, 0) ?? ""
            let expenseID = text(stmt, 1) ?? ""
            let expected = integer(stmt, 2) ?? 0
            let receiptID = text(stmt, 3)
            let received = integer(stmt, 4) ?? 0
            let status = text(stmt, 5) ?? ""
            guard !linkID.isEmpty, ids.insert(linkID).inserted, !expenseID.isEmpty,
                  expected > 0, received >= 0, received <= expected,
                  ["pending", "received"].contains(status),
                  (status == "received") == (receiptID?.isEmpty == false),
                  (status == "received" ? received > 0 : received == 0) else {
                issues.append(ImportIssue(table: "reimbursement_reconciliations", sourceRow: nil,
                    field: "identity, amounts, receipt, or status", reason: "invalid reconciliation"))
                continue
            }
            result.append(HistoricalReimbursementReconciliation(linkID: linkID,
                expenseSourceID: expenseID, expectedEURMinor: expected,
                receiptSourceID: receiptID, receivedEURMinor: received,
                status: status, note: text(stmt, 6)))
        }
        return result
    }

    private func readMovements(schemaVersion: Int, tripIDs: Set<String>, accountNames: Set<String>, sourceRowKeys: Set<String>,
                               issues: inout [ImportIssue]) throws -> ([ImportedMovement], Int, Int) {
        let buildFiveColumns = schemaVersion == 2
            ? "eur_value_source,exchange_rate_date,exchange_rate_provider,account_amount_minor,account_currency"
            : "NULL,NULL,NULL,NULL,NULL"
        let stmt = try statement("SELECT id,occurred_at,amount_minor,currency,eur_minor,exchange_rate_eur,description,kind,category,subcategory,account,trip_id,paid_by,affects_my_accounts,personal_expense_eur_minor,recoverable_eur_minor,needs_review,review_reason,origin,entered_at,note,home_type,source_sheet,source_row,source_technical_id,cached_personal_value,import_fingerprint,\(buildFiveColumns) FROM movements ORDER BY source_row")
        defer { sqlite3_finalize(stmt) }
        var rows: [ImportedMovement] = []
        var unmatchedAccounts = 0
        var missingAccounts = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            let sourceRow = Int(integer(stmt, 23) ?? 0)
            guard let sourceID = text(stmt, 0), !sourceID.isEmpty,
                  let originalDate = text(stmt, 1), let date = dateFormatter.date(from: originalDate),
                  let amount = integer(stmt, 2), amount > 0,
                  let currency = text(stmt, 3), CurrencyMetadata.supportedCodes.contains(currency),
                  let description = text(stmt, 6), !description.isEmpty,
                  let sourceKind = text(stmt, 7), let kind = Self.kind(sourceKind),
                  let sheet = text(stmt, 22), !sheet.isEmpty, sourceRow > 0,
                  let fingerprint = text(stmt, 26), !fingerprint.isEmpty else {
                issues.append(ImportIssue(table: "movements", sourceRow: sourceRow, field: "kind, date, money, or identity", reason: "missing or unsupported")); continue
            }
            let suppliedEUR = integer(stmt, 4)
            let eurMinor = suppliedEUR ?? (currency == "EUR" ? amount : nil)
            if let eurMinor, eurMinor <= 0 {
                issues.append(ImportIssue(table: "movements", sourceRow: sourceRow, field: "eur_minor", reason: "must be positive when present")); continue
            }
            let rate = text(stmt, 5)
            if rate != nil && !validRate(rate) {
                issues.append(ImportIssue(table: "movements", sourceRow: sourceRow, field: "exchange_rate_eur", reason: "must be positive when present")); continue
            }
            let personal = integer(stmt, 14)
            let recoverable = integer(stmt, 15)
            if let recoverable, recoverable < 0 {
                issues.append(ImportIssue(table: "movements", sourceRow: sourceRow, field: "recoverable_eur_minor", reason: "cannot be negative")); continue
            }
            if eurMinor == nil && (personal != nil || recoverable != nil) {
                issues.append(ImportIssue(table: "movements", sourceRow: sourceRow, field: "EUR allocations", reason: "cannot exist without a represented EUR value")); continue
            }
            let accountAmount = integer(stmt, 30)
            let accountCurrency = text(stmt, 31)
            if (accountAmount == nil) != (accountCurrency == nil) || accountAmount.map({ $0 <= 0 }) == true ||
                accountCurrency.map({ !CurrencyMetadata.supportedCodes.contains($0) }) == true {
                issues.append(ImportIssue(table: "movements", sourceRow: sourceRow, field: "account amount and currency", reason: "must be a valid pair when present")); continue
            }
            if !sourceRowKeys.contains("\(sheet):\(sourceRow)") {
                issues.append(ImportIssue(table: "movements", sourceRow: sourceRow, field: "source_rows", reason: "original spreadsheet row missing"))
            }
            if let trip = text(stmt, 11), !trip.isEmpty, !tripIDs.contains(trip) {
                issues.append(ImportIssue(table: "movements", sourceRow: sourceRow, field: "trip_id", reason: "trip reference missing"))
            }
            if let flag = integer(stmt, 13), flag != 0 && flag != 1 {
                issues.append(ImportIssue(table: "movements", sourceRow: sourceRow, field: "affects_my_accounts", reason: "must be 0 or 1"))
            }
            if let account = text(stmt, 10), !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !accountNames.contains(account) { unmatchedAccounts += 1 }
            } else { missingAccounts += 1 }
            var item = Transaction(id: Self.stableTransactionID(sourceID: sourceID), kind: kind,
                                   amountMinor: amount, currency: currency, merchant: description,
                                   account: text(stmt, 10) ?? "", category: text(stmt, 8) ?? "",
                                   note: text(stmt, 20) ?? "", occurredAt: date, updatedAt: .now,
                                   deletedAt: nil, isDemo: false, revision: 1, sourceEventID: nil)
            item.subcategory = text(stmt, 9)
            item.eurMinor = eurMinor
            item.exchangeRateEUR = rate
            item.personalExpenseEURMinor = personal
            item.recoverableEURMinor = recoverable
            item.tripID = text(stmt, 11)
            item.paidBy = text(stmt, 12)
            item.affectsMyAccounts = integer(stmt, 13).map { $0 != 0 }
            item.sourceMovementID = sourceID
            item.sourceSheet = sheet
            item.sourceRow = sourceRow
            item.sourceOccurredAt = originalDate
            item.sourceKind = sourceKind
            if let source = text(stmt, 27).flatMap(EURValueSource.init(rawValue:)) {
                item.eurValueSource = source
            } else if eurMinor != nil {
                item.eurValueSource = currency == "EUR" ? .confirmed : .historical
            }
            item.exchangeRateDate = text(stmt, 28)
            item.exchangeRateProvider = text(stmt, 29)
            item.accountAmountMinor = accountAmount ?? amount
            item.accountCurrency = accountCurrency ?? currency
            rows.append(ImportedMovement(transaction: item, sourceFingerprint: fingerprint,
                                         sourcePayloadJSON: try originalJSON(stmt)))
        }
        return (rows, unmatchedAccounts, missingAccounts)
    }
}
