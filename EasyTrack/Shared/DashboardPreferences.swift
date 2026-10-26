import Foundation

enum AppThemeStyle: String, Codable, CaseIterable, Identifiable {
    case classic
    case neutral
    case graphite
    var id: String { rawValue }
    var title: String {
        switch self {
        case .classic: "Classic Pine & Jade"
        case .neutral: "Neutral + accents"
        case .graphite: "Graphite / monochrome"
        }
    }
}

enum AppAccentChoice: String, Codable, CaseIterable, Identifiable {
    case jade
    case blue
    case violet
    case amber
    case graphite
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum AppColorSchemePreference: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct AppearancePreferences: Codable, Equatable {
    var theme: AppThemeStyle = .classic
    var accent: AppAccentChoice = .jade
    var colorScheme: AppColorSchemePreference = .system
    static let `default` = AppearancePreferences()
}

struct DashboardWidgetPreference: Codable, Equatable, Identifiable {
    var id: String { widgetID }
    let widgetID: String
    var position: Int
    var isVisible: Bool
    var updatedAt: Date
}

struct ResolvedDashboardWidget: Equatable {
    let widgetID: String
    let isVisible: Bool
}

enum DashboardWidgetPreferenceResolver {
    static func resolve(availableIDs: [String], defaultOrder: [String],
                        preferences: [DashboardWidgetPreference]) -> [ResolvedDashboardWidget] {
        let available = Set(availableIDs)
        let canonical = defaultOrder.filter(available.contains) + availableIDs.filter { !defaultOrder.contains($0) }
        guard !preferences.isEmpty else {
            return canonical.map { ResolvedDashboardWidget(widgetID: $0, isVisible: true) }
        }
        let known = preferences.filter { available.contains($0.widgetID) }
            .sorted {
                if $0.position != $1.position { return $0.position < $1.position }
                return $0.widgetID < $1.widgetID
            }
        let configured = Set(known.map(\.widgetID))
        var result = known.map { ResolvedDashboardWidget(widgetID: $0.widgetID, isVisible: $0.isVisible) }
        for missing in canonical.filter({ !configured.contains($0) }) {
            let defaultIndex = canonical.firstIndex(of: missing)!
            let predecessor = canonical[..<defaultIndex].reversed()
                .compactMap { candidate in result.firstIndex { $0.widgetID == candidate } }.first
            if let predecessor {
                result.insert(ResolvedDashboardWidget(widgetID: missing, isVisible: true), at: predecessor + 1)
            } else if let successor = canonical[(defaultIndex + 1)...]
                .compactMap({ candidate in result.firstIndex { $0.widgetID == candidate } }).first {
                result.insert(ResolvedDashboardWidget(widgetID: missing, isVisible: true), at: successor)
            } else {
                result.append(ResolvedDashboardWidget(widgetID: missing, isVisible: true))
            }
        }
        return result
    }
}
