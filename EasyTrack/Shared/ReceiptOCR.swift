import Foundation

struct ReceiptOCRLine: Equatable {
    let text: String
    let confidence: Double
}

struct ReceiptAmountCandidate: Identifiable, Equatable {
    let id: String
    let amountMinor: Int64
    let currency: String
    let sourceText: String
    let confidence: Double
    let finalTotalEvidence: Bool
}

struct ReceiptDateCandidate: Identifiable, Equatable {
    let id: String
    let date: Date
    let sourceText: String
}

struct ReceiptExtraction: Equatable {
    let merchantCandidates: [String]
    let dateCandidates: [ReceiptDateCandidate]
    let amountCandidates: [ReceiptAmountCandidate]
    let recommendedAmountID: String?
}

struct ReceiptTransactionDraft: Identifiable, Equatable {
    let id = UUID()
    var merchant: String
    var occurredAt: Date
    var amountMinor: Int64?
    var currency: String
    var dateWasDetected: Bool
}

enum ReceiptOCRParser {
    private static let finalLabels = [
        "totale", "total", "amount due", "da pagare", "pagato", "paid", "grand total",
        "importo", "carta", "card"
    ]
    private static let excludedLabels = [
        "subtotale", "subtotal", "iva", "vat", "tax", "imposta", "resto", "change",
        "contanti", "cash", "sconto", "discount", "tip", "mancia"
    ]
    private static let genericMerchantLines = [
        "receipt", "scontrino", "documento commerciale", "fiscal receipt", "grazie", "thank you"
    ]

    static func extract(lines: [ReceiptOCRLine], calendar: Calendar = .current) -> ReceiptExtraction {
        let cleanLines = lines.map { ReceiptOCRLine(
            text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), confidence: $0.confidence) }
            .filter { !$0.text.isEmpty }
        let dateCandidates = dates(in: cleanLines, calendar: calendar)
        let amounts = amounts(in: cleanLines)
        let highConfidence = amounts.filter(\.finalTotalEvidence)
        let recommended: String?
        if highConfidence.count == 1 { recommended = highConfidence[0].id }
        else if highConfidence.isEmpty && amounts.count == 1 { recommended = amounts[0].id }
        else { recommended = nil }
        return ReceiptExtraction(merchantCandidates: merchants(in: cleanLines),
                                 dateCandidates: dateCandidates,
                                 amountCandidates: amounts,
                                 recommendedAmountID: recommended)
    }

    private static func merchants(in lines: [ReceiptOCRLine]) -> [String] {
        var result: [String] = []
        for line in lines.prefix(8) {
            let normalized = NotificationParser.normalize(line.text)
            guard line.text.rangeOfCharacter(from: .letters) != nil,
                  !genericMerchantLines.contains(where: normalized.contains),
                  !finalLabels.contains(where: normalized.contains),
                  !excludedLabels.contains(where: normalized.contains),
                  dates(in: [line], calendar: .current).isEmpty,
                  detectedMoney(in: line.text).isEmpty else { continue }
            if !result.contains(where: { NotificationParser.normalize($0) == normalized }) {
                result.append(line.text)
            }
            if result.count == 3 { break }
        }
        return result
    }

    private static func dates(in lines: [ReceiptOCRLine], calendar: Calendar) -> [ReceiptDateCandidate] {
        let patterns = [
            #"\b([0-3]?\d)[/.-]([01]?\d)[/.-](20\d{2}|\d{2})\b"#,
            #"\b(20\d{2})[/.-]([01]?\d)[/.-]([0-3]?\d)\b"#
        ]
        var found: [ReceiptDateCandidate] = []
        for line in lines {
            for (patternIndex, pattern) in patterns.enumerated() {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let ns = line.text as NSString
                for match in regex.matches(in: line.text, range: NSRange(location: 0, length: ns.length)) {
                    let values = (1...3).map { Int(ns.substring(with: match.range(at: $0))) ?? 0 }
                    let day: Int
                    let month: Int
                    var year: Int
                    if patternIndex == 0 { day = values[0]; month = values[1]; year = values[2] }
                    else { year = values[0]; month = values[1]; day = values[2] }
                    if year < 100 { year += 2_000 }
                    var components = DateComponents()
                    components.calendar = calendar
                    components.timeZone = calendar.timeZone
                    components.year = year; components.month = month; components.day = day
                    components.hour = 12
                    guard let date = components.date,
                          calendar.component(.year, from: date) == year,
                          calendar.component(.month, from: date) == month,
                          calendar.component(.day, from: date) == day else { continue }
                    let source = ns.substring(with: match.range)
                    let id = "\(year)-\(month)-\(day)"
                    if !found.contains(where: { $0.id == id }) {
                        found.append(ReceiptDateCandidate(id: id, date: date, sourceText: source))
                    }
                }
            }
        }
        return found
    }

    private static func amounts(in lines: [ReceiptOCRLine]) -> [ReceiptAmountCandidate] {
        struct Ranked {
            let candidate: ReceiptAmountCandidate
            let score: Int
            let lineIndex: Int
        }
        var ranked: [Ranked] = []
        for (lineIndex, line) in lines.enumerated() {
            let normalized = NotificationParser.normalize(line.text)
            if excludedLabels.contains(where: normalized.contains) { continue }
            let finalEvidence = finalLabels.contains(where: normalized.contains)
            for money in detectedMoney(in: line.text) {
                let id = "\(money.currency)-\(money.amountMinor)-\(NotificationParser.normalize(line.text))"
                let confidence = min(max(line.confidence, 0), 1)
                ranked.append(Ranked(candidate: ReceiptAmountCandidate(
                    id: id, amountMinor: money.amountMinor, currency: money.currency,
                    sourceText: line.text, confidence: confidence, finalTotalEvidence: finalEvidence),
                    score: finalEvidence ? 3 : 1, lineIndex: lineIndex))
            }
        }
        ranked.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.lineIndex != $1.lineIndex { return $0.lineIndex > $1.lineIndex }
            return $0.candidate.amountMinor > $1.candidate.amountMinor
        }
        var seen: Set<String> = []
        return ranked.compactMap { item in
            let identity = "\(item.candidate.currency)-\(item.candidate.amountMinor)"
            guard seen.insert(identity).inserted else { return nil }
            return item.candidate
        }.prefix(6).map { $0 }
    }

    private static func detectedMoney(in text: String) -> [(amountMinor: Int64, currency: String)] {
        let pattern = #"(?<![A-Za-z0-9])(?:(€|EUR|USD|GBP|\$|£)\s*)?([0-9][0-9., ]*[,.][0-9]{2})(?:\s*(€|EUR|USD|GBP|\$|£))?(?![A-Za-z0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let number = ns.substring(with: match.range(at: 2)).replacingOccurrences(of: " ", with: "")
            guard let amount = Money.parseMinor(number), amount > 0 else { return nil }
            let leading = match.range(at: 1).location == NSNotFound ? "" : ns.substring(with: match.range(at: 1))
            let trailing = match.range(at: 3).location == NSNotFound ? "" : ns.substring(with: match.range(at: 3))
            let marker = (leading.isEmpty ? trailing : leading).uppercased()
            let currency: String
            switch marker {
            case "$", "USD": currency = "USD"
            case "£", "GBP": currency = "GBP"
            default: currency = "EUR"
            }
            return (amount, currency)
        }
    }
}

enum ReceiptDuplicateDetector {
    static func possibleMatches(for draft: ReceiptTransactionDraft, transactions: [Transaction],
                                calendar: Calendar = .current) -> [Transaction] {
        guard draft.currency == "EUR", let amount = draft.amountMinor, amount > 0 else { return [] }
        let merchant = NotificationParser.normalize(draft.merchant)
        return transactions.filter { transaction in
            guard transaction.deletedAt == nil, transaction.kind == .expense,
                  (transaction.eurMinor ?? (transaction.currency == "EUR" ? transaction.amountMinor : nil)) == amount,
                  calendar.isDate(transaction.occurredAt, inSameDayAs: draft.occurredAt) else { return false }
            let existing = NotificationParser.normalize(transaction.merchant)
            return merchant.isEmpty || existing == merchant || existing.contains(merchant) || merchant.contains(existing)
        }
    }
}
