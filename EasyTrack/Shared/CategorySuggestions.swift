import Foundation

struct CategoryKeywordRule: Codable, Equatable, Identifiable {
    let id: UUID
    var pattern: String
    var categoryID: UUID
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var revision: Int64
}

enum CategorySuggestionSource: String, Equatable { case userRule, builtIn }

struct CategorySuggestion: Equatable, Identifiable {
    var id: UUID { categoryID }
    let categoryID: UUID
    let categoryName: String
    let matchedText: String
    let source: CategorySuggestionSource
}

struct MovementIconAppearance: Equatable {
    let symbolName: String
    let colorName: String
}

enum CategorySuggestionEngine {
    private struct Match {
        let category: LedgerCategory
        let matchedText: String
        let source: CategorySuggestionSource
        let tokenCount: Int
        let characterCount: Int
    }

    private struct BuiltInRule {
        let pattern: String
        let categoryNames: [String]
    }

    private static let builtIns: [BuiltInRule] = [
        .init(pattern: "supermercato", categoryNames: ["Groceries"]),
        .init(pattern: "supermarket", categoryNames: ["Groceries"]),
        .init(pattern: "grocery", categoryNames: ["Groceries"]),
        .init(pattern: "farmacia", categoryNames: ["Health"]),
        .init(pattern: "pharmacy", categoryNames: ["Health"]),
        .init(pattern: "ristorante", categoryNames: ["Eating Out"]),
        .init(pattern: "pizzeria", categoryNames: ["Eating Out"]),
        .init(pattern: "restaurant", categoryNames: ["Eating Out"]),
        .init(pattern: "caffe", categoryNames: ["Eating Out"]),
        .init(pattern: "benzina", categoryNames: ["Transport"]),
        .init(pattern: "carburante", categoryNames: ["Transport"]),
        .init(pattern: "taxi", categoryNames: ["Transport"]),
        .init(pattern: "hotel", categoryNames: ["Travel"]),
        .init(pattern: "airline", categoryNames: ["Travel"]),
        .init(pattern: "tuition", categoryNames: ["Education"])
    ]

    static func suggestions(description: String, kind: TransactionKind,
                            categories: [LedgerCategory], userRules: [CategoryKeywordRule],
                            isEnabled: Bool, limit: Int = 3) -> [CategorySuggestion] {
        guard isEnabled, kind == .expense, limit > 0 else { return [] }
        let descriptionTokens = tokens(description)
        guard !descriptionTokens.isEmpty else { return [] }
        let active = categories.filter { $0.archivedAt == nil }
        let categoriesByID = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        var matches: [Match] = []

        for rule in userRules where rule.isEnabled {
            let patternTokens = tokens(rule.pattern)
            guard let category = categoriesByID[rule.categoryID],
                  contains(patternTokens, in: descriptionTokens) else { continue }
            matches.append(Match(category: category, matchedText: rule.pattern,
                                 source: .userRule, tokenCount: patternTokens.count,
                                 characterCount: normalized(rule.pattern).count))
        }

        for rule in builtIns {
            let patternTokens = tokens(rule.pattern)
            guard contains(patternTokens, in: descriptionTokens),
                  let category = active.first(where: { category in
                      rule.categoryNames.contains { normalized($0) == normalized(category.name) }
                  }) else { continue }
            matches.append(Match(category: category, matchedText: rule.pattern,
                                 source: .builtIn, tokenCount: patternTokens.count,
                                 characterCount: normalized(rule.pattern).count))
        }

        matches.sort {
            if $0.source != $1.source { return $0.source == .userRule }
            if $0.tokenCount != $1.tokenCount { return $0.tokenCount > $1.tokenCount }
            if $0.characterCount != $1.characterCount { return $0.characterCount > $1.characterCount }
            if $0.category.sortIndex != $1.category.sortIndex { return $0.category.sortIndex < $1.category.sortIndex }
            return $0.category.id.uuidString < $1.category.id.uuidString
        }
        var seen: Set<UUID> = []
        return matches.compactMap { match in
            guard seen.insert(match.category.id).inserted else { return nil }
            return CategorySuggestion(categoryID: match.category.id,
                categoryName: match.category.name, matchedText: match.matchedText,
                source: match.source)
        }.prefix(limit).map { $0 }
    }

    static func suggestedRulePattern(from description: String) -> String {
        let ignored: Set<String> = ["the", "and", "di", "da", "del", "della", "con", "per", "payment", "pagamento"]
        return tokens(description).filter { $0.count >= 3 && !ignored.contains($0) }
            .max { lhs, rhs in lhs.count < rhs.count } ?? ""
    }

    static func normalized(_ value: String) -> String { tokens(value).joined(separator: " ") }

    static func tokens(_ value: String) -> [String] {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func contains(_ pattern: [String], in text: [String]) -> Bool {
        guard !pattern.isEmpty, pattern.count <= text.count else { return false }
        if pattern.count == 1 { return text.contains(pattern[0]) }
        return (0...(text.count - pattern.count)).contains { start in
            Array(text[start..<(start + pattern.count)]) == pattern
        }
    }
}

enum MovementIconResolver {
    static func fallback(description: String, kind: TransactionKind) -> MovementIconAppearance {
        let words = Set(CategorySuggestionEngine.tokens(description))
        let mappings: [([String], MovementIconAppearance)] = [
            (["supermercato", "supermarket", "grocery"], .init(symbolName: "cart.fill", colorName: "green")),
            (["ristorante", "pizzeria", "restaurant", "cafe", "caffe", "coffee"], .init(symbolName: "fork.knife", colorName: "orange")),
            (["benzina", "carburante", "fuel", "taxi"], .init(symbolName: "car.fill", colorName: "blue")),
            (["farmacia", "pharmacy"], .init(symbolName: "cross.case.fill", colorName: "red")),
            (["hotel", "airline", "flight"], .init(symbolName: "airplane", colorName: "blue")),
            (["salary", "stipendio"], .init(symbolName: "banknote.fill", colorName: "green"))
        ]
        if let match = mappings.first(where: { keys, _ in !words.isDisjoint(with: keys) }) {
            return match.1
        }
        return kind.isOutflow
            ? .init(symbolName: "creditcard.fill", colorName: "teal")
            : .init(symbolName: "arrow.down.left.circle.fill", colorName: "teal")
    }
}
