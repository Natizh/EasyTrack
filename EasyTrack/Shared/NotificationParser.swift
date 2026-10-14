import CryptoKit
import Foundation

enum NotificationField: String, Codable, CaseIterable, Identifiable {
    case title, subtitle, message, combined
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    func text(in event: NotificationEvent) -> String {
        switch self {
        case .title: event.title
        case .subtitle: event.subtitle
        case .message: event.message
        case .combined: [event.title, event.subtitle, event.message].filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }
}

enum TextMatchMode: String, Codable, CaseIterable, Identifiable {
    case contains, beginsWith, endsWith, regularExpression
    var id: String { rawValue }
    var title: String {
        switch self {
        case .contains: "Contains"
        case .beginsWith: "Begins with"
        case .endsWith: "Ends with"
        case .regularExpression: "Regular expression"
        }
    }
}

enum MerchantMode: String, Codable, CaseIterable, Identifiable {
    case afterAmount, beforeAmount, wholeLine, betweenAnchors, regularExpression
    var id: String { rawValue }
    var title: String {
        switch self {
        case .afterAmount: "After amount"
        case .beforeAmount: "Before amount"
        case .wholeLine: "Whole line"
        case .betweenAnchors: "Between text"
        case .regularExpression: "Regular expression"
        }
    }
}

struct ParserRuleConfig: Codable, Equatable {
    var inputField: NotificationField = .message
    var amountPrefix = ""
    var amountSuffix = ""
    var merchantField: NotificationField = .message
    var merchantMode: MerchantMode = .afterAmount
    var merchantPrefix = ""
    var merchantSuffix = ""
    var merchantPattern = ""
    var conditionField: NotificationField = .title
    var conditionMode: TextMatchMode = .contains
    var conditionText = ""
    var kind: TransactionKind = .expense
    // Retained only to decode and audit schema-3 rule history. New rules use
    // ParserSource.accountID and leave transactions uncategorized.
    var account = ""
    var category = ""
    var duplicateWindowSeconds = 600
}

struct LocalAccount: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let createdAt: Date
}

struct ParserSource: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let createdAt: Date
    let accountID: UUID?
    let accountName: String?
}

struct ParserRule: Identifiable, Codable, Equatable {
    var id: UUID
    var sourceID: UUID
    var name: String
    var enabled: Bool
    var priority: Int
    var version: Int
    var config: ParserRuleConfig
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}

struct ParserRuleRevision: Codable, Equatable {
    let ruleID: UUID
    let version: Int
    let config: ParserRuleConfig
    let changedAt: Date
}

enum ParserAttemptStatus: String, Codable {
    case captured, setupRequired, unmatched, failed, duplicateIgnored, created, ready

    var title: String {
        switch self {
        case .captured: "Captured"
        case .setupRequired: "Set up notification format"
        case .unmatched: "Add notification format"
        case .failed: "Could not create transaction"
        case .duplicateIgnored: "Duplicate ignored"
        case .created: "Transaction created"
        case .ready: "Rule ready"
        }
    }
}

struct ParserAttempt: Identifiable, Codable {
    let id: UUID
    let event: NotificationEvent
    let sourceID: UUID
    let capturedAt: Date
    var status: ParserAttemptStatus
    var ruleID: UUID?
    var ruleVersion: Int?
    var transactionID: UUID?
    var detail: String?
}

struct AmountCapture: Equatable {
    let cents: Int64
    let currency: String
    let token: String
    let range: Range<String.Index>
}

struct ParserPreview {
    let conditionMatched: Bool
    let amount: AmountCapture?
    let merchant: String?
    let occurredAt: Date
    let error: String?
    var ready: Bool { conditionMatched && amount != nil && merchant != nil && error == nil }
}

enum ParserValidationError: LocalizedError {
    case invalidRule(String)
    var errorDescription: String? {
        switch self { case .invalidRule(let message): message }
    }
}

enum NotificationParser {
    static func normalize(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func digest(_ components: [String]) -> String {
        var data = Data()
        for component in components {
            let bytes = Data(component.utf8)
            var length = UInt32(bytes.count).bigEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
            data.append(bytes)
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func exactFingerprint(_ event: NotificationEvent) -> String {
        digest([normalize(event.sourceApp), normalize(event.title), normalize(event.subtitle),
                normalize(event.message), event.receivedAt.map { String(Int64($0.timeIntervalSince1970.rounded())) } ?? ""])
    }

    static func semanticFingerprint(amountMinor: Int64, merchant: String, account: String) -> String {
        digest([String(amountMinor), "EUR", normalize(merchant), normalize(account)])
    }

    static func validate(_ config: ParserRuleConfig) throws {
        guard [300, 600, 1_800].contains(config.duplicateWindowSeconds) else {
            throw ParserValidationError.invalidRule("Choose a 5, 10, or 30 minute duplicate window.")
        }
        for anchor in [config.amountPrefix, config.amountSuffix, config.merchantPrefix, config.merchantSuffix] {
            guard anchor.utf8.count <= 80 else { throw ParserValidationError.invalidRule("Keep matching text under 80 characters.") }
        }
        if config.conditionMode == .regularExpression { _ = try safeRegex(config.conditionText) }
        if config.merchantMode == .regularExpression { _ = try safeRegex(config.merchantPattern) }
    }

    // Advanced patterns are deliberately a small, bounded subset. No grouping, alternation,
    // backreferences, counted repetitions, or lookarounds. One repetition operator on at most
    // 512 input characters avoids nested or adjacent quantifier backtracking.
    static func safeRegex(_ pattern: String) throws -> NSRegularExpression {
        guard !pattern.isEmpty, pattern.utf8.count <= 96,
              !pattern.contains("("), !pattern.contains(")"), !pattern.contains("|"),
              !pattern.contains("{"), !pattern.contains("}"),
              !pattern.contains("\\1"), !pattern.contains("\\k"),
              pattern.filter({ "*+?".contains($0) }).count <= 1 else {
            throw ParserValidationError.invalidRule("This advanced pattern is too complex. Use short text anchors instead.")
        }
        do { return try NSRegularExpression(pattern: pattern) }
        catch { throw ParserValidationError.invalidRule("Enter a valid regular expression.") }
    }

    static func detectedAmounts(in text: String) -> [AmountCapture] {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![A-Za-z0-9])(?:(?:€|EUR)\s*[0-9][0-9.,]*|[0-9][0-9.,]*\s*(?:€|EUR))(?![A-Za-z0-9])"#, options: [.caseInsensitive]),
              let number = try? NSRegularExpression(pattern: #"[0-9][0-9.,]*"#) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let token = ns.substring(with: match.range)
            let tokenNS = token as NSString
            guard let numberRange = number.firstMatch(in: token, range: NSRange(location: 0, length: tokenNS.length))?.range,
                  let cents = Money.parseMinor(tokenNS.substring(with: numberRange)), cents > 0,
                  let range = Range(match.range, in: text) else { return nil }
            return AmountCapture(cents: cents, currency: "EUR", token: token, range: range)
        }
    }

    static func suggest(for event: NotificationEvent) -> ParserRuleConfig {
        var config = ParserRuleConfig()
        config.inputField = [.message, .subtitle, .title, .combined].first { !detectedAmounts(in: $0.text(in: event)).isEmpty } ?? .combined
        config.merchantField = config.inputField
        config.conditionField = event.title.isEmpty ? config.inputField : .title
        config.conditionText = event.title.isEmpty ? "" : event.title
        if let amount = detectedAmounts(in: config.inputField.text(in: event)).first {
            let text = config.inputField.text(in: event)
            let trailing = String(text[amount.range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            config.merchantMode = trailing.isEmpty ? .beforeAmount : .afterAmount
        }
        if let merchant = preview(event, config: config, mappedAccount: "sample").merchant,
           !merchant.isEmpty, event.title.localizedCaseInsensitiveContains(merchant) {
            config.conditionText = ""
        }
        return config
    }

    static func preview(_ event: NotificationEvent, config: ParserRuleConfig,
                        mappedAccount: String? = nil) -> ParserPreview {
        let date = event.receivedAt ?? event.capturedAt
        if config.conditionMode == .regularExpression && (try? safeRegex(config.conditionText)) == nil ||
            config.merchantMode == .regularExpression && (try? safeRegex(config.merchantPattern)) == nil {
            return ParserPreview(conditionMatched: false, amount: nil, merchant: nil, occurredAt: date,
                                 error: "Use a short valid advanced pattern.")
        }
        let condition = config.conditionField.text(in: event)
        let needle = config.conditionText
        let matched: Bool
        switch config.conditionMode {
        case .contains: matched = needle.isEmpty || condition.localizedCaseInsensitiveContains(needle)
        case .beginsWith: matched = needle.isEmpty || condition.lowercased().hasPrefix(needle.lowercased())
        case .endsWith: matched = needle.isEmpty || condition.lowercased().hasSuffix(needle.lowercased())
        case .regularExpression:
            let bounded = String(condition.prefix(512))
            matched = (try? safeRegex(needle).firstMatch(in: bounded, range: NSRange(location: 0, length: (bounded as NSString).length))) != nil
        }
        guard matched else { return ParserPreview(conditionMatched: false, amount: nil, merchant: nil, occurredAt: date, error: nil) }
        let input = config.inputField.text(in: event)
        let amount = detectedAmounts(in: input).first(where: { capture in
            let before = String(input[..<capture.range.lowerBound])
            let after = String(input[capture.range.upperBound...])
            return (config.amountPrefix.isEmpty || before.lowercased().hasSuffix(config.amountPrefix.lowercased())) &&
                (config.amountSuffix.isEmpty || after.lowercased().hasPrefix(config.amountSuffix.lowercased()))
        })
        guard let amount else {
            return ParserPreview(conditionMatched: true, amount: nil, merchant: nil, occurredAt: date,
                                 error: "No matching EUR amount was found.")
        }
        let merchantInput = config.merchantField.text(in: event)
        let merchantAmount = detectedAmounts(in: merchantInput).first
        let raw: String
        switch config.merchantMode {
        case .afterAmount:
            raw = merchantAmount.map { String(merchantInput[$0.range.upperBound...]).components(separatedBy: .newlines).first ?? "" } ?? ""
        case .beforeAmount:
            raw = merchantAmount.map { String(merchantInput[..<$0.range.lowerBound]).components(separatedBy: .newlines).last ?? "" } ?? ""
        case .wholeLine:
            raw = merchantInput.components(separatedBy: .newlines).first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        case .betweenAnchors:
            let start = config.merchantPrefix.isEmpty ? merchantInput.startIndex :
                merchantInput.range(of: config.merchantPrefix, options: .caseInsensitive)?.upperBound
            if let start {
                let tail = merchantInput[start...]
                let end = config.merchantSuffix.isEmpty ? tail.endIndex :
                    tail.range(of: config.merchantSuffix, options: .caseInsensitive)?.lowerBound
                raw = end.map { String(tail[..<$0]) } ?? ""
            } else { raw = "" }
        case .regularExpression:
            let bounded = String(merchantInput.prefix(512))
            if let regex = try? safeRegex(config.merchantPattern),
               let match = regex.firstMatch(in: bounded, range: NSRange(location: 0, length: (bounded as NSString).length)),
               let range = Range(match.range(at: match.numberOfRanges > 1 ? 1 : 0), in: bounded) {
                raw = String(bounded[range])
            } else { raw = "" }
        }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: #"^(?i:at|to|from|da|a|presso|per)\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return ParserPreview(conditionMatched: true, amount: amount,
                             merchant: cleaned.isEmpty ? nil : cleaned, occurredAt: date,
                             error: cleaned.isEmpty ? "No description was found." :
                                (normalize(mappedAccount ?? "").isEmpty ?
                                 "Map this notification source to an account." : nil))
    }
}
