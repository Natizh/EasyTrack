import Foundation

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
        let added = canonical.filter { !configured.contains($0) }
            .map { ResolvedDashboardWidget(widgetID: $0, isVisible: true) }
        return known.map { ResolvedDashboardWidget(widgetID: $0.widgetID, isVisible: $0.isVisible) } + added
    }
}
