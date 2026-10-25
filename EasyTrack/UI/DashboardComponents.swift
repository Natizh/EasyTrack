import SwiftUI

enum EasyTrackTheme {
    static let midnightPine = Color(red: 20 / 255, green: 43 / 255, blue: 50 / 255)
    static let deepTeal = Color(red: 20 / 255, green: 115 / 255, blue: 110 / 255)
    static let softJade = Color(red: 217 / 255, green: 242 / 255, blue: 237 / 255)
    static let champagne = Color(red: 196 / 255, green: 154 / 255, blue: 93 / 255)
    static let coral = Color(red: 180 / 255, green: 92 / 255, blue: 85 / 255)

    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.38, green: 0.84, blue: 0.80, alpha: 1)
            : UIColor(red: 20 / 255, green: 115 / 255, blue: 110 / 255, alpha: 1)
    })
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 12 / 255, green: 23 / 255, blue: 26 / 255, alpha: 1)
            : UIColor(red: 245 / 255, green: 247 / 255, blue: 246 / 255, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 23 / 255, green: 43 / 255, blue: 48 / 255, alpha: 1)
            : .white
    })
    static let primaryText = Color.primary
    static let jadeWash = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 20 / 255, green: 115 / 255, blue: 110 / 255, alpha: 0.22)
            : UIColor(red: 217 / 255, green: 242 / 255, blue: 237 / 255, alpha: 1)
    })
}

struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct FinancialHeroCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let snapshot: FinancialAnalyticsSnapshot?
    let periodTitle: String

    private var dailyAverage: String {
        guard let average = snapshot?.dailyAverage else { return "—" }
        let behavior = NSDecimalNumberHandler(roundingMode: .plain, scale: 0,
                                              raiseOnExactness: false, raiseOnOverflow: false,
                                              raiseOnUnderflow: false, raiseOnDivideByZero: false)
        let rounded = NSDecimalNumber(decimal: average.exactEURMinorPerDay)
            .rounding(accordingToBehavior: behavior).int64Value
        return Money.format(rounded)
    }

    private var metrics: some View {
        Group {
            MetricTile(title: "Income", value: snapshot.map { Money.format($0.totals.incomeEURMinor) } ?? "—",
                       symbol: "arrow.down.left")
            MetricTile(title: "PAC", value: snapshot.map { Money.format($0.totals.pacInvestedEURMinor) } ?? "—",
                       symbol: "chart.line.uptrend.xyaxis")
            MetricTile(title: "Daily average", value: dailyAverage, symbol: "calendar.day.timeline.left")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(periodTitle.uppercased()) · NET PERSONAL SPENDING")
                    .font(.caption.weight(.bold))
                    .tracking(1.05)
                    .foregroundStyle(.white.opacity(0.72))
                Text(snapshot.map { Money.format($0.totals.personalNetExpensesEURMinor) } ?? "—")
                    .font(.system(size: 43, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("homePersonalSpendingTotal")
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) { metrics }
            } else {
                HStack(spacing: 10) { metrics }
            }

            if let snapshot, !snapshot.unconvertedTransactions.isEmpty {
                Label("\(snapshot.unconvertedTransactions.count) movement(s) excluded where EUR value is unavailable",
                      systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(colors: [EasyTrackTheme.midnightPine, EasyTrackTheme.deepTeal],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

struct RecentTransactionCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: Transaction
    let category: LedgerCategory?

    private var categoryName: String {
        category?.name ?? (item.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Uncategorized" : item.category)
    }

    private var iconName: String {
        category?.symbolName ?? (item.kind.isOutflow ? "creditcard.fill" : "arrow.down.left.circle.fill")
    }

    private var accent: Color {
        category.map { LedgerColor.color($0.colorName) } ?? EasyTrackTheme.accent
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
                .foregroundStyle(EasyTrackTheme.primaryText)
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
                .foregroundStyle(item.kind.isOutflow ? EasyTrackTheme.primaryText : EasyTrackTheme.accent)
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
        .padding(15)
        .background(EasyTrackTheme.surface, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .stroke(EasyTrackTheme.accent.opacity(0.08), lineWidth: 1)
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
            .frame(width: 46, height: 46)
            .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct DashboardModuleCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EasyTrackTheme.surface,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
