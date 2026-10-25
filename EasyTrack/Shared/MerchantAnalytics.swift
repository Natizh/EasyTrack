import Foundation

struct MerchantAliasGroup: Codable, Equatable, Identifiable {
    let id: UUID
    var canonicalName: String
    var memberKeys: [String]
    var createdAt: Date
    var updatedAt: Date
}

struct MerchantGroupingSuggestion: Equatable, Identifiable {
    var id: String { memberKeys.joined(separator: "|") }
    let canonicalName: String
    let memberKeys: [String]
    let memberNames: [String]
}

enum MerchantAnalytics {
    static func grouped(_ merchants: [FinancialMerchantAggregate],
                        aliases: [MerchantAliasGroup]) throws -> [FinancialMerchantAggregate] {
        let aliasByMember = Dictionary(uniqueKeysWithValues: aliases.flatMap { group in
            group.memberKeys.map { ($0, group) }
        })
        var values: [String: FinancialMerchantAggregate] = [:]
        for merchant in merchants {
            let alias = aliasByMember[merchant.key]
            let key = alias.map { "group:\($0.id.uuidString)" } ?? merchant.key
            let name = alias?.canonicalName ?? merchant.name
            if let current = values[key] {
                let (amount, overflow) = current.personalNetExpensesEURMinor
                    .addingReportingOverflow(merchant.personalNetExpensesEURMinor)
                guard !overflow else { throw FinancialAnalyticsError.amountOverflow }
                values[key] = FinancialMerchantAggregate(key: key, name: name,
                    transactionCount: current.transactionCount + merchant.transactionCount,
                    personalNetExpensesEURMinor: amount,
                    transactionIDs: Array(Set(current.transactionIDs + merchant.transactionIDs))
                        .sorted { $0.uuidString < $1.uuidString })
            } else {
                values[key] = FinancialMerchantAggregate(key: key, name: name,
                    transactionCount: merchant.transactionCount,
                    personalNetExpensesEURMinor: merchant.personalNetExpensesEURMinor,
                    transactionIDs: merchant.transactionIDs)
            }
        }
        return values.values.sorted {
            if $0.personalNetExpensesEURMinor != $1.personalNetExpensesEURMinor {
                return $0.personalNetExpensesEURMinor > $1.personalNetExpensesEURMinor
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func suggestions(from merchants: [FinancialMerchantAggregate],
                            aliases: [MerchantAliasGroup]) -> [MerchantGroupingSuggestion] {
        let approved = Set(aliases.flatMap(\.memberKeys))
        let candidates = merchants.filter { !approved.contains($0.key) }
        let grouped = Dictionary(grouping: candidates) { proposalKey($0.name) }
        return grouped.compactMap { key, members in
            let distinct = Dictionary(grouping: members, by: \.key).compactMap(\.value.first)
            guard !key.isEmpty, distinct.count > 1 else { return nil }
            let ordered = distinct.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return MerchantGroupingSuggestion(canonicalName: key.capitalized,
                memberKeys: ordered.map(\.key), memberNames: ordered.map(\.name))
        }.sorted { $0.canonicalName.localizedCaseInsensitiveCompare($1.canonicalName) == .orderedAscending }
    }

    static func proposalKey(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let tokens = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                !token.isEmpty && !token.allSatisfy(\.isNumber)
            }
        let result = tokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return result.filter(\.isLetter).count >= 4 ? result : ""
    }
}
