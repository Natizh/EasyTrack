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

enum AppDisplayDensity: String, Codable, CaseIterable, Identifiable {
    case standard
    case compact
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct AppearancePreferences: Codable, Equatable {
    var theme: AppThemeStyle = .classic
    var accent: AppAccentChoice = .jade
    var colorScheme: AppColorSchemePreference = .system
    var density: AppDisplayDensity = .standard
    static let `default` = AppearancePreferences()

    private enum CodingKeys: String, CodingKey { case theme, accent, colorScheme, density }

    init(theme: AppThemeStyle = .classic, accent: AppAccentChoice = .jade,
         colorScheme: AppColorSchemePreference = .system,
         density: AppDisplayDensity = .standard) {
        self.theme = theme
        self.accent = accent
        self.colorScheme = colorScheme
        self.density = density
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        theme = try values.decodeIfPresent(AppThemeStyle.self, forKey: .theme) ?? .classic
        accent = try values.decodeIfPresent(AppAccentChoice.self, forKey: .accent) ?? .jade
        colorScheme = try values.decodeIfPresent(AppColorSchemePreference.self, forKey: .colorScheme) ?? .system
        density = try values.decodeIfPresent(AppDisplayDensity.self, forKey: .density) ?? .standard
    }
}

struct BackupReminderPreferences: Codable, Equatable {
    var isEnabled = true
    var lastSuccessfulExportAt: Date?
    static let `default` = BackupReminderPreferences()

    func isDue(at date: Date = .now) -> Bool {
        guard isEnabled else { return false }
        guard let lastSuccessfulExportAt else { return true }
        return date.timeIntervalSince(lastSuccessfulExportAt) >= 30 * 86_400
    }
}

enum BackupFilename {
    static func make(at date: Date = .now, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return "EasyTrack-backup-\(formatter.string(from: date))"
    }
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

enum DashboardHeroMetric: String, Codable, CaseIterable, Identifiable {
    case net, expenses, income, netExpenses, pac, dailyAverage
    var id: String { rawValue }
    var title: String {
        switch self {
        case .net: "Net"
        case .expenses: "Expenses"
        case .income: "Income"
        case .netExpenses: "Net Expenses"
        case .pac: "PAC invested"
        case .dailyAverage: "Daily average"
        }
    }
    var symbol: String {
        switch self {
        case .net: "sum"
        case .expenses: "arrow.up.right"
        case .income: "arrow.down.left"
        case .netExpenses: "arrow.up.right.circle"
        case .pac: "chart.line.uptrend.xyaxis"
        case .dailyAverage: "calendar.day.timeline.left"
        }
    }
    var accessibilityIdentifier: String {
        switch self {
        case .net: "homeNetMetric"
        case .expenses: "homeExpensesMetric"
        case .income: "homeIncomeMetric"
        case .netExpenses: "homeNetExpensesMetric"
        case .pac: "homePACMetric"
        case .dailyAverage: "homeDailyAverageMetric"
        }
    }
}

struct DashboardHeroPreferences: Codable, Equatable {
    var primary: DashboardHeroMetric = .net
    var secondary: [DashboardHeroMetric] = [.income, .pac, .dailyAverage]
    static let `default` = DashboardHeroPreferences()

    var resolved: DashboardHeroPreferences {
        var result = self
        var seen: Set<DashboardHeroMetric> = [primary]
        result.secondary = secondary.filter { seen.insert($0).inserted }
        return result
    }
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
