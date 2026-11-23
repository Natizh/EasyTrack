import SwiftUI

extension AppAccentChoice {
    var color: Color {
        switch self {
        case .jade:
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.38, green: 0.84, blue: 0.80, alpha: 1)
                    : UIColor(red: 20 / 255, green: 115 / 255, blue: 110 / 255, alpha: 1)
            })
        case .blue: .blue
        case .violet: .purple
        case .amber: .orange
        case .graphite:
            Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .lightGray : .darkGray })
        }
    }
}

extension AppColorSchemePreference {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct EasyTrackTheme {
    let preferences: AppearancePreferences

    private var effectiveAccent: AppAccentChoice {
        preferences.theme == .graphite ? .graphite : preferences.accent
    }

    var accent: Color { effectiveAccent.color }
    var isCompact: Bool { preferences.density == .compact }
    var screenPadding: CGFloat { isCompact ? 16 : 20 }
    var sectionSpacing: CGFloat { isCompact ? 14 : 22 }
    var cardPadding: CGFloat { isCompact ? 13 : 17 }
    var heroPadding: CGFloat { isCompact ? 18 : 22 }
    var rowVerticalPadding: CGFloat { isCompact ? 1 : 4 }
    var listRowSpacing: CGFloat? { isCompact ? 0 : nil }
    var decorativeIconSize: CGFloat { isCompact ? 40 : 46 }
    var primaryText: Color { .primary }
    let champagne = Color(red: 196 / 255, green: 154 / 255, blue: 93 / 255)
    let coral = Color(red: 180 / 255, green: 92 / 255, blue: 85 / 255)

    var canvas: Color {
        switch preferences.theme {
        case .classic:
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 12 / 255, green: 23 / 255, blue: 26 / 255, alpha: 1)
                    : UIColor(red: 245 / 255, green: 247 / 255, blue: 246 / 255, alpha: 1)
            })
        case .neutral: Color(uiColor: .systemGroupedBackground)
        case .graphite:
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 14 / 255, green: 14 / 255, blue: 15 / 255, alpha: 1)
                    : UIColor(red: 242 / 255, green: 242 / 255, blue: 244 / 255, alpha: 1)
            })
        }
    }

    var surface: Color {
        switch preferences.theme {
        case .classic:
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 23 / 255, green: 43 / 255, blue: 48 / 255, alpha: 1)
                    : .white
            })
        case .neutral: Color(uiColor: .secondarySystemGroupedBackground)
        case .graphite:
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 30 / 255, green: 30 / 255, blue: 32 / 255, alpha: 1)
                    : .white
            })
        }
    }

    var accentWash: Color {
        switch preferences.theme {
        case .classic where effectiveAccent == .jade:
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 20 / 255, green: 115 / 255, blue: 110 / 255, alpha: 0.22)
                    : UIColor(red: 217 / 255, green: 242 / 255, blue: 237 / 255, alpha: 1)
            })
        default: accent.opacity(preferences.theme == .neutral ? 0.10 : 0.16)
        }
    }

    var heroColors: [Color] {
        switch preferences.theme {
        case .classic:
            [Color(red: 20 / 255, green: 43 / 255, blue: 50 / 255), accent]
        case .neutral:
            [surface, Color(uiColor: .tertiarySystemGroupedBackground)]
        case .graphite:
            [Color(red: 28 / 255, green: 29 / 255, blue: 31 / 255),
             Color(red: 65 / 255, green: 66 / 255, blue: 70 / 255)]
        }
    }

    var heroText: Color { preferences.theme == .neutral ? .primary : .white }
    var heroSecondaryText: Color { heroText.opacity(0.72) }
    var heroMetricBackground: Color {
        preferences.theme == .neutral ? accent.opacity(0.08) : .white.opacity(0.09)
    }
    var heroBorder: Color {
        preferences.theme == .neutral ? accent.opacity(0.18) : .white.opacity(0.11)
    }

    static let classic = EasyTrackTheme(preferences: .default)
}

private struct EasyTrackThemeKey: EnvironmentKey {
    static let defaultValue = EasyTrackTheme.classic
}

extension EnvironmentValues {
    var easyTrackTheme: EasyTrackTheme {
        get { self[EasyTrackThemeKey.self] }
        set { self[EasyTrackThemeKey.self] = newValue }
    }
}

struct MetricTile: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.easyTrackTheme) private var theme
    let title: String
    let value: String
    let symbol: String
    var accessibilityTitle: String? = nil
    var periodTitle: String? = nil
    var showsDisclosure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 4) {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.heroSecondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if showsDisclosure {
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.heroSecondaryText)
                        .accessibilityHidden(true)
                }
            }
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(theme.heroText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.heroMetricBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel([accessibilityTitle ?? title, value, periodTitle]
            .compactMap { $0 }.joined(separator: ", "))
    }
}

struct FinancialHeroCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.easyTrackTheme) private var theme
    @ScaledMetric(relativeTo: .largeTitle) private var heroFontSize: CGFloat = 43
    let snapshot: FinancialAnalyticsSnapshot?
    let periodTitle: String
    var preferences: DashboardHeroPreferences = .default
    var onMetricTap: ((DashboardHeroMetric) -> Void)? = nil

    private func isAction(_ metric: DashboardHeroMetric) -> Bool {
        snapshot != nil && onMetricTap != nil
    }

    private func value(for metric: DashboardHeroMetric) -> String {
        guard let totals = snapshot?.totals else { return "—" }
        switch metric {
        case .net: return Money.format(totals.netEURMinor)
        case .expenses: return Money.format(totals.grossExpensesEURMinor)
        case .income: return Money.format(totals.grossIncomeEURMinor)
        case .netExpenses: return Money.format(totals.netExpensesEURMinor)
        case .pac: return Money.format(totals.pacInvestedEURMinor)
        case .dailyAverage: return dailyAverage
        }
    }

    private var dailyAverage: String {
        guard let average = snapshot?.dailyAverage else { return "—" }
        return Money.format(average.roundedEURMinorPerDay)
    }

    private var secondaryMetrics: some View {
        let metrics = preferences.resolved.secondary
        return VStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(metrics.prefix(2))) { metric in metricTile(metric) }
                }
                VStack(spacing: 10) {
                    ForEach(Array(metrics.prefix(2))) { metric in metricTile(metric) }
                }
            }
            ForEach(Array(metrics.dropFirst(2))) { metric in metricTile(metric) }
        }
    }

    @ViewBuilder private func metricTile(_ metric: DashboardHeroMetric) -> some View {
        if isAction(metric), let onMetricTap {
            Button { onMetricTap(metric) } label: {
                MetricTile(title: metric.title, value: value(for: metric), symbol: metric.symbol,
                           periodTitle: periodTitle, showsDisclosure: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Show contributing movements for \(metric.title) in \(periodTitle)")
            .accessibilityIdentifier(metric.accessibilityIdentifier)
        } else {
            MetricTile(title: metric.title, value: value(for: metric),
                       symbol: metric.symbol, periodTitle: periodTitle)
        }
    }

    private var primaryMetricContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(periodTitle.uppercased()) · \(preferences.primary.title.uppercased())")
                    .font(.caption.weight(.bold))
                    .tracking(1.05)
                if isAction(preferences.primary) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(theme.heroSecondaryText)
            Text(value(for: preferences.primary))
                .font(.system(size: heroFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .foregroundStyle(theme.heroText)
                .accessibilityIdentifier("homePersonalSpendingTotal")
                .accessibilityLabel("\(preferences.primary.title), \(value(for: preferences.primary)), \(periodTitle)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var primaryMetric: some View {
        if isAction(preferences.primary), let onMetricTap {
            Button { onMetricTap(preferences.primary) } label: { primaryMetricContent }
                .buttonStyle(.plain)
                .accessibilityHint("Show contributing movements for \(preferences.primary.title) in \(periodTitle)")
                .accessibilityIdentifier(preferences.primary.accessibilityIdentifier)
        } else {
            primaryMetricContent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            primaryMetric

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    ForEach(preferences.resolved.secondary) { metric in metricTile(metric) }
                }
            } else { secondaryMetrics }

            if let snapshot, !snapshot.unconvertedTransactions.isEmpty {
                Label("\(snapshot.unconvertedTransactions.count) movement(s) excluded where EUR value is unavailable",
                      systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(theme.heroSecondaryText)
            }
            if let snapshot, snapshot.estimatedEURTransactionCount > 0 {
                Label("\(snapshot.estimatedEURTransactionCount) movement(s) use indicative EUR estimates",
                      systemImage: "approximately")
                    .font(.caption).foregroundStyle(theme.heroSecondaryText)
            }
        }
        .padding(theme.heroPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(colors: theme.heroColors,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(theme.heroBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

struct RecentTransactionCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.easyTrackTheme) private var theme
    let item: Transaction
    let category: LedgerCategory?

    private var categoryName: String {
        category?.name ?? (item.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Uncategorized" : item.category)
    }

    private var iconName: String {
        category?.symbolName ?? MovementIconResolver.fallback(description: item.merchant,
                                                               kind: item.kind).symbolName
    }

    private var accent: Color {
        category.map { LedgerColor.color($0.colorName) } ??
            LedgerColor.color(MovementIconResolver.fallback(description: item.merchant,
                                                             kind: item.kind).colorName)
    }

    private var amountText: String {
        let prefix = item.kind.isOutflow ? "−" : "+"
        if let eur = item.eurMinor ?? (item.currency == "EUR" ? item.amountMinor : nil) {
            return prefix + Money.format(eur)
        }
        return prefix + Money.format(item.amountMinor, currency: item.currency)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.merchant)
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            Text(categoryName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var amount: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(amountText)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(item.kind.isOutflow ? theme.primaryText : theme.accent)
                .lineLimit(1)
            Text(item.occurredAt.formatted(.dateTime.day().month(.abbreviated)))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 13) { icon; labels }
                    HStack { Spacer(minLength: 0); amount }
                }
            } else {
                HStack(spacing: 13) {
                    icon
                    labels
                    Spacer(minLength: 6)
                    amount
                }
            }
        }
        .padding(theme.isCompact ? 12 : 15)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .stroke(theme.accent.opacity(0.08), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.merchant), \(categoryName), \(amountText), \(item.occurredAt.formatted(date: .abbreviated, time: .omitted))")
        .accessibilityHint("Edit transaction")
        .accessibilityIdentifier("homeRecentTransaction-\(item.id.uuidString)")
    }

    private var icon: some View {
        Image(systemName: iconName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: theme.decorativeIconSize, height: theme.decorativeIconSize)
            .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct DashboardModuleCard<Content: View>: View {
    @Environment(\.easyTrackTheme) private var theme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
