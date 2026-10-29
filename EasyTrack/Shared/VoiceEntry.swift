import Foundation

enum VoiceEntryLanguage: String, Codable, CaseIterable, Identifiable {
    case italian = "it-IT"
    case english = "en-US"

    var id: String { rawValue }
    var title: String { self == .italian ? "Italiano" : "English" }
    var locale: Locale { Locale(identifier: rawValue) }

    static func restored(_ rawValue: String?) -> VoiceEntryLanguage {
        rawValue.flatMap(VoiceEntryLanguage.init(rawValue:)) ?? .italian
    }
}

struct VoiceSessionTokenGate: Equatable {
    private(set) var generation = 0
    private(set) var activeGeneration: Int?

    mutating func begin() -> Int {
        generation += 1
        activeGeneration = generation
        return generation
    }

    func accepts(_ token: Int) -> Bool { activeGeneration == token }

    mutating func finish(_ token: Int) -> Bool {
        guard accepts(token) else { return false }
        activeGeneration = nil
        return true
    }

    mutating func cancel() { activeGeneration = nil }
}

struct VoiceTransactionDraft: Equatable {
    var kind: TransactionKind?
    var amountMinor: Int64?
    var currency: String?
    var merchant: String?
    var occurredAt: Date?
    var issues: [String]
}

enum VoiceEntryParser {
    static func parse(_ transcript: String, locale: Locale,
                      now: Date = .now, calendar: Calendar = .current) -> VoiceTransactionDraft {
        let text = transcript.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
            .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return VoiceTransactionDraft(kind: nil, amountMinor: nil, currency: nil,
                                         merchant: nil, occurredAt: nil, issues: ["No speech was transcribed."])
        }
        let tokens = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let kind: TransactionKind? = tokens.contains(where: { ["ricevuto", "ricevuta", "received", "income"].contains($0) })
            ? .income : (tokens.contains(where: { ["speso", "spesa", "pagato", "pagata", "spent", "paid"].contains($0) }) ? .expense : nil)
        let currencyInfo: (String, Int)? = [
            ("EUR", tokens.firstIndex(where: { ["euro", "euros"].contains($0) })),
            ("USD", tokens.firstIndex(where: { ["dollar", "dollars", "dollari"].contains($0) })),
            ("GBP", tokens.firstIndex(where: { ["pound", "pounds", "sterline"].contains($0) })),
            ("CNY", tokens.firstIndex(where: { ["yuan", "cny"].contains($0) }))
        ].compactMap { code, index in index.map { (code, $0) } }.first

        var amountMinor: Int64?
        if let (currency, currencyIndex) = currencyInfo {
            let before = Array(tokens[..<currencyIndex])
            let numeric = before.reversed().compactMap { Decimal(string: $0.replacingOccurrences(of: ",", with: ".")) }.first
            let units = numeric ?? Decimal(numberWords: before, italian: locale.identifier.lowercased().hasPrefix("it"))
            var fraction = Decimal(0)
            if currency == "EUR" || currency == "USD" || currency == "GBP" {
                let after = Array(tokens.dropFirst(currencyIndex + 1).prefix { !["al", "alla", "da", "at", "from", "oggi", "ieri", "today", "yesterday"].contains($0) })
                if let value = Decimal(numberWords: after, italian: locale.identifier.lowercased().hasPrefix("it")), value < 100 {
                    fraction = value / 100
                }
            }
            if let units {
                let exponent = CurrencyMetadata.exponent(for: currency)
                var value = (units + fraction) * CurrencyMetadata.divisor(for: currency)
                var rounded = Decimal(); NSDecimalRound(&rounded, &value, 0, .plain)
                amountMinor = NSDecimalNumber(decimal: rounded).int64Value
                if exponent == 0 { amountMinor = NSDecimalNumber(decimal: units).int64Value }
            }
        }

        let merchantMarkers = ["al", "alla", "da", "at", "from"]
        var merchant: String?
        if let marker = tokens.firstIndex(where: merchantMarkers.contains) {
            let words = tokens.dropFirst(marker + 1).prefix { !["oggi", "ieri", "laltro", "today", "yesterday"].contains($0) }
            let value = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            merchant = value.isEmpty ? nil : value
        }
        let occurredAt: Date?
        if text.contains("l'altro ieri") || text.contains("altro ieri") {
            occurredAt = calendar.date(byAdding: .day, value: -2, to: now)
        } else if tokens.contains("ieri") || tokens.contains("yesterday") {
            occurredAt = calendar.date(byAdding: .day, value: -1, to: now)
        } else if tokens.contains("oggi") || tokens.contains("today") {
            occurredAt = now
        } else { occurredAt = nil }
        var issues: [String] = []
        if kind == nil { issues.append("Expense or income direction was not clear.") }
        if currencyInfo == nil { issues.append("Currency was not recognized.") }
        if amountMinor == nil || amountMinor == 0 { issues.append("Amount was not recognized unambiguously.") }
        return VoiceTransactionDraft(kind: kind, amountMinor: amountMinor,
            currency: currencyInfo?.0, merchant: merchant, occurredAt: occurredAt, issues: issues)
    }
}

private extension Decimal {
    init?(numberWords words: [String], italian: Bool) {
        let values: [String: Int] = italian ? [
            "zero":0,"uno":1,"una":1,"due":2,"tre":3,"quattro":4,"cinque":5,"sei":6,"sette":7,"otto":8,"nove":9,
            "dieci":10,"undici":11,"dodici":12,"tredici":13,"quattordici":14,"quindici":15,"sedici":16,
            "diciassette":17,"diciotto":18,"diciannove":19,"venti":20,"trenta":30,"quaranta":40,"cinquanta":50,
            "sessanta":60,"settanta":70,"ottanta":80,"novanta":90,"cento":100
        ] : [
            "zero":0,"one":1,"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,"eight":8,"nine":9,
            "ten":10,"eleven":11,"twelve":12,"thirteen":13,"fourteen":14,"fifteen":15,"sixteen":16,
            "seventeen":17,"eighteen":18,"nineteen":19,"twenty":20,"thirty":30,"forty":40,"fifty":50,
            "sixty":60,"seventy":70,"eighty":80,"ninety":90,"hundred":100
        ]
        let recognized = words.compactMap { values[$0] }
        guard !recognized.isEmpty else { return nil }
        var total = 0, current = 0
        for value in recognized {
            if value == 100 { current = max(current, 1) * 100 }
            else { current += value }
        }
        total += current
        self = Decimal(total)
    }
}
