import Charts
import SwiftUI

enum EasyTrackTab: Hashable { case home, activity, automations, settings }

struct ActivityChartScope: Equatable {
    let label: String
    let filter: TransactionFilter
}

@MainActor
final class AppNavigationModel: ObservableObject {
    @Published var selectedTab: EasyTrackTab = .home
    @Published var activityChartScope: ActivityChartScope?

    func showActivity(label: String, filter: TransactionFilter) {
        activityChartScope = ActivityChartScope(label: label, filter: filter)
        selectedTab = .activity
    }

    func clearChartScope() { activityChartScope = nil }
}

struct DashboardWidgetID: RawRepresentable, Codable, Hashable, Identifiable {
    let rawValue: String
    var id: String { rawValue }

    static let monthlyTrend = DashboardWidgetID(rawValue: "monthlyTrend")
    static let categoryBreakdown = DashboardWidgetID(rawValue: "categoryBreakdown")
    static let recurring = DashboardWidgetID(rawValue: "recurring")
    static let dailySpending = DashboardWidgetID(rawValue: "dailySpending")
    static let topMerchants = DashboardWidgetID(rawValue: "topMerchants")
    static let uncategorized = DashboardWidgetID(rawValue: "uncategorized")
}

struct DashboardWidgetDescriptor: Identifiable, Equatable {
    let id: DashboardWidgetID
    let title: String
    let systemImage: String
    let defaultOrder: Int
}

enum DashboardWidgetRegistry {
    static let available: [DashboardWidgetDescriptor] = [
        .init(id: .monthlyTrend, title: "Monthly trend", systemImage: "chart.xyaxis.line", defaultOrder: 0),
        .init(id: .categoryBreakdown, title: "Categories", systemImage: "chart.pie", defaultOrder: 1),
        .init(id: .recurring, title: "Upcoming", systemImage: "calendar", defaultOrder: 2),
        .init(id: .dailySpending, title: "Daily spending", systemImage: "chart.bar", defaultOrder: 3),
        .init(id: .topMerchants, title: "Top merchants", systemImage: "building.2", defaultOrder: 4),
        .init(id: .uncategorized, title: "Uncategorized", systemImage: "tag", defaultOrder: 5)
    ].sorted { $0.defaultOrder < $1.defaultOrder }

    static func resolved(preferences: [DashboardWidgetPreference]) -> [(DashboardWidgetDescriptor, Bool)] {
        let byID = Dictionary(uniqueKeysWithValues: available.map { ($0.id.rawValue, $0) })
        return DashboardWidgetPreferenceResolver.resolve(
            availableIDs: available.map { $0.id.rawValue },
            defaultOrder: available.map { $0.id.rawValue },
            preferences: preferences
        ).compactMap { item in
            byID[item.widgetID].map { ($0, item.isVisible) }
        }
    }

    static func visible(preferences: [DashboardWidgetPreference]) -> [DashboardWidgetDescriptor] {
        resolved(preferences: preferences).compactMap { descriptor, isVisible in
            isVisible ? descriptor : nil
        }
    }
}

private struct EditableDashboardWidget: Identifiable {
    let descriptor: DashboardWidgetDescriptor
    var isVisible: Bool
    var id: DashboardWidgetID { descriptor.id }
}

struct DashboardWidgetEditorView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    @State private var items: [EditableDashboardWidget] = []
    @State private var confirmingReset = false

    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    Toggle(isOn: visibilityBinding(for: item.id)) {
                        Label(item.descriptor.title, systemImage: item.descriptor.systemImage)
                    }
                    .accessibilityHint("Controls whether this module appears on Home")
                }
                .onMove(perform: move)
            } footer: {
                Text("The financial hero and recent activity always remain first.")
            }
            Section {
                Button("Restore default layout", role: .destructive) { confirmingReset = true }
            }
        }
        .navigationTitle("Customize Home")
        .environment(\.editMode, .constant(.active))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .onAppear {
            items = DashboardWidgetRegistry.resolved(preferences: store.dashboardWidgetPreferences)
                .map { EditableDashboardWidget(descriptor: $0.0, isVisible: $0.1) }
        }
        .confirmationDialog("Restore the default widget order and visibility?",
                            isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Restore defaults", role: .destructive) { reset() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func visibilityBinding(for id: DashboardWidgetID) -> Binding<Bool> {
        Binding {
            items.first { $0.id == id }?.isVisible ?? true
        } set: { value in
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            items[index].isVisible = value
            persist()
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func persist() {
        do {
            let now = Date()
            try store.saveDashboardWidgetPreferences(items.enumerated().map { index, item in
                DashboardWidgetPreference(widgetID: item.id.rawValue, position: index,
                                          isVisible: item.isVisible, updatedAt: now)
            })
        } catch { store.errorMessage = error.localizedDescription }
    }

    private func reset() {
        do {
            try store.resetDashboardWidgetPreferences()
            items = DashboardWidgetRegistry.available.map {
                EditableDashboardWidget(descriptor: $0, isVisible: true)
            }
        } catch { store.errorMessage = error.localizedDescription }
    }
}

struct DashboardWidgetLayout<Recurring: View, Uncategorized: View>: View {
    let snapshot: FinancialAnalyticsSnapshot?
    let widgets: [DashboardWidgetDescriptor]
    let recurring: Recurring
    let uncategorized: Uncategorized

    init(snapshot: FinancialAnalyticsSnapshot?,
         widgets: [DashboardWidgetDescriptor] = DashboardWidgetRegistry.available,
         @ViewBuilder recurring: () -> Recurring,
         @ViewBuilder uncategorized: () -> Uncategorized) {
        self.snapshot = snapshot
        self.widgets = widgets
        self.recurring = recurring()
        self.uncategorized = uncategorized()
    }

    var body: some View {
        VStack(spacing: 22) {
            ForEach(widgets) { descriptor in
                widget(descriptor.id)
            }
        }
    }

    @ViewBuilder
    private func widget(_ id: DashboardWidgetID) -> some View {
        if id == .monthlyTrend {
            MonthlyTrendWidget(snapshot: snapshot)
        } else if id == .categoryBreakdown {
            CategoryBreakdownWidget(snapshot: snapshot)
        } else if id == .recurring {
            recurring
        } else if id == .dailySpending {
            DailySpendingWidget(snapshot: snapshot)
        } else if id == .topMerchants {
            TopMerchantsWidget(snapshot: snapshot)
        } else if id == .uncategorized {
            uncategorized
        }
    }
}

struct MonthlyTrendWidget: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var navigation: AppNavigationModel
    @State private var selectedDate: Date?
    let snapshot: FinancialAnalyticsSnapshot?

    private var points: [FinancialMonthlyAggregate] { snapshot?.monthlyTrend ?? [] }
    private var hasValues: Bool {
        points.contains { $0.grossExpensesEURMinor != 0 || $0.incomeEURMinor != 0 || $0.pacInvestedEURMinor != 0 }
    }

    var body: some View {
        DashboardModuleCard {
            VStack(alignment: .leading, spacing: 15) {
                WidgetHeader(title: "Monthly trend", systemImage: "chart.xyaxis.line")
                if hasValues {
                    Chart {
                        ForEach(points) { point in
                            LineMark(x: .value("Month", chartDate(point.month)),
                                     y: .value("Expenses", plotAmount(point.grossExpensesEURMinor)))
                                .foregroundStyle(EasyTrackTheme.coral)
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Month", chartDate(point.month)),
                                      y: .value("Expenses", plotAmount(point.grossExpensesEURMinor)))
                                .foregroundStyle(EasyTrackTheme.coral)
                            LineMark(x: .value("Month", chartDate(point.month)),
                                     y: .value("Income", plotAmount(point.incomeEURMinor)))
                                .foregroundStyle(EasyTrackTheme.accent)
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Month", chartDate(point.month)),
                                      y: .value("Income", plotAmount(point.incomeEURMinor)))
                                .foregroundStyle(EasyTrackTheme.accent)
                            LineMark(x: .value("Month", chartDate(point.month)),
                                     y: .value("PAC", plotAmount(point.pacInvestedEURMinor)))
                                .foregroundStyle(EasyTrackTheme.champagne)
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Month", chartDate(point.month)),
                                      y: .value("PAC", plotAmount(point.pacInvestedEURMinor)))
                                .foregroundStyle(EasyTrackTheme.champagne)
                        }
                    }
                    .chartXAxis { dateAxisMarks() }
                    .chartYAxis { currencyAxisMarks() }
                    .chartXSelection(value: $selectedDate)
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 250 : 205)
                    .accessibilityRepresentation { monthlyAccessibility }
                    .onChange(of: selectedDate) { _, value in
                        guard let value, let snapshot else { return }
                        let selected = LocalDay(date: value, timeZone: .current)
                        let month = LocalDay(isoString: String(format: "%04d-%02d-01",
                                                              selected.year, selected.month))!
                        let index = snapshot.chartSelectionIndex
                        let ids = (index.monthlyExpenses[month] ?? [])
                            .union(index.monthlyIncome[month] ?? [])
                            .union(index.monthlyPAC[month] ?? [])
                        openActivity(ids: ids, label: "Monthly trend · \(monthLabel(month))",
                                     snapshot: snapshot, navigation: navigation)
                        selectedDate = nil
                    }

                    HStack(spacing: 14) {
                        ChartLegendKey(title: "Expenses", color: EasyTrackTheme.coral)
                        ChartLegendKey(title: "Income", color: EasyTrackTheme.accent)
                        ChartLegendKey(title: "PAC", color: EasyTrackTheme.champagne)
                    }
                } else {
                    ChartEmptyState("No expenses, income or PAC in this period.")
                }
            }
        }
        .accessibilityIdentifier("homeMonthlyTrendWidget")
    }

    private var monthlyAccessibility: some View {
        VStack(alignment: .leading) {
            Text("Monthly trend")
            ForEach(points) { point in
                Text("\(monthLabel(point.month)): expenses \(Money.format(point.grossExpensesEURMinor)), income \(Money.format(point.incomeEURMinor)), PAC \(Money.format(point.pacInvestedEURMinor))")
            }
        }
    }
}

private enum CategoryChartMode: String, CaseIterable, Identifiable {
    case ring, bars
    var id: String { rawValue }
    var title: String { self == .ring ? "Ring" : "Bars" }
}

private struct CategoryChartValue: Identifiable {
    let id: String
    let name: String
    let amountMinor: Int64
}

struct CategoryBreakdownWidget: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var navigation: AppNavigationModel
    @State private var mode: CategoryChartMode = .ring
    @State private var selectedAngle: Double?
    @State private var selectedCategory: String?
    let snapshot: FinancialAnalyticsSnapshot?

    private var positive: [FinancialCategoryAggregate] { snapshot?.positiveCategories ?? [] }
    private var bars: [CategoryChartValue] {
        guard let snapshot else { return [] }
        var values = snapshot.categories.map {
            CategoryChartValue(id: $0.key, name: $0.name, amountMinor: $0.personalNetExpensesEURMinor)
        }
        if snapshot.unallocatedPersonalAdjustmentEURMinor != 0 {
            values.append(CategoryChartValue(id: "unallocated", name: "Unallocated adjustment",
                                             amountMinor: snapshot.unallocatedPersonalAdjustmentEURMinor))
        }
        return values.sorted {
            if $0.amountMinor != $1.amountMinor { return $0.amountMinor > $1.amountMinor }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    private var hasExcludedRingValues: Bool {
        guard let snapshot else { return false }
        return snapshot.categories.contains { $0.personalNetExpensesEURMinor <= 0 } ||
            snapshot.unallocatedPersonalAdjustmentEURMinor != 0
    }
    private var colors: [Color] {
        let palette = [EasyTrackTheme.accent, EasyTrackTheme.champagne, EasyTrackTheme.coral,
                       Color.indigo, Color.orange, Color.mint, Color.purple, Color.blue]
        return positive.indices.map { palette[$0 % palette.count] }
    }

    var body: some View {
        DashboardModuleCard {
            VStack(alignment: .leading, spacing: 15) {
                WidgetHeader(title: "Categories", systemImage: "chart.pie")
                Picker("Category chart", selection: $mode) {
                    ForEach(CategoryChartMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if bars.isEmpty {
                    ChartEmptyState("No categorized personal spending in this period.")
                } else if mode == .ring {
                    ringContent
                } else {
                    barsContent
                }

                if let snapshot {
                    Text("Net personal spending: \(Money.format(snapshot.totals.personalNetExpensesEURMinor))")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                    if hasExcludedRingValues && mode == .ring {
                        Text("The ring includes positive categories only. Non-positive categories: \(Money.format(snapshot.nonPositiveCategoryAdjustmentEURMinor)); unallocated adjustment: \(Money.format(snapshot.unallocatedPersonalAdjustmentEURMinor)).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityIdentifier("homeCategoryBreakdownWidget")
    }

    @ViewBuilder
    private var ringContent: some View {
        if positive.isEmpty {
            ChartEmptyState("No positive category amounts for the ring chart.")
        } else {
            Chart(positive) { category in
                SectorMark(angle: .value("Amount", plotAmount(category.personalNetExpensesEURMinor)),
                           innerRadius: .ratio(0.62), angularInset: 1.5)
                    .foregroundStyle(by: .value("Category", category.name))
                    .cornerRadius(4)
            }
            .chartForegroundStyleScale(domain: positive.map(\.name), range: colors)
            .chartLegend(.hidden)
            .chartAngleSelection(value: $selectedAngle)
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 260 : 210)
            .accessibilityRepresentation { categoryAccessibility(positive.map {
                CategoryChartValue(id: $0.key, name: $0.name,
                                   amountMinor: $0.personalNetExpensesEURMinor)
            }) }
            .onChange(of: selectedAngle) { _, value in
                guard let value, let snapshot else { return }
                var cumulative = 0.0
                guard let category = positive.first(where: {
                    cumulative += plotAmount($0.personalNetExpensesEURMinor)
                    return value <= cumulative
                }) else { return }
                let ids = snapshot.chartSelectionIndex.categories[category.key] ?? []
                openActivity(ids: ids, label: "Category · \(category.name)",
                             snapshot: snapshot, navigation: navigation)
                selectedAngle = nil
            }

            VStack(spacing: 8) {
                ForEach(Array(positive.enumerated()), id: \.element.key) { index, category in
                    HStack {
                        Circle().fill(colors[index]).frame(width: 8, height: 8).accessibilityHidden(true)
                        Text(category.name).font(.caption).lineLimit(1)
                        Spacer()
                        Text(Money.format(category.personalNetExpensesEURMinor))
                            .font(.caption.weight(.semibold)).monospacedDigit()
                    }
                }
            }
        }
    }

    private var barsContent: some View {
        let height = max(180, CGFloat(bars.count) * 38)
        return ScrollView(.vertical, showsIndicators: bars.count > 7) {
            Chart {
                RuleMark(x: .value("Zero", 0)).foregroundStyle(.secondary.opacity(0.45))
                ForEach(bars) { category in
                    BarMark(x: .value("Net amount", plotAmount(category.amountMinor)),
                            y: .value("Category", category.name))
                        .foregroundStyle(category.amountMinor < 0 ? EasyTrackTheme.coral : EasyTrackTheme.accent)
                        .cornerRadius(4)
                }
            }
            .chartXAxis { currencyAxisMarks() }
            .chartYAxis { AxisMarks(position: .leading) }
            .chartYSelection(value: $selectedCategory)
            .frame(height: height)
            .accessibilityRepresentation { categoryAccessibility(bars) }
            .onChange(of: selectedCategory) { _, value in
                guard let value, let snapshot,
                      let category = bars.first(where: { $0.name == value }) else { return }
                let ids = category.id == "unallocated"
                    ? snapshot.chartSelectionIndex.unallocated
                    : snapshot.chartSelectionIndex.categories[category.id] ?? []
                openActivity(ids: ids, label: "Category · \(category.name)",
                             snapshot: snapshot, navigation: navigation)
                selectedCategory = nil
            }
        }
        .frame(height: min(height, 285))
    }

    private func categoryAccessibility(_ values: [CategoryChartValue]) -> some View {
        VStack(alignment: .leading) {
            Text("Category breakdown")
            ForEach(values) { value in
                Text("\(value.name): \(Money.format(value.amountMinor))")
            }
        }
    }
}

struct DailySpendingWidget: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var navigation: AppNavigationModel
    @State private var selectedDate: Date?
    let snapshot: FinancialAnalyticsSnapshot?

    private var points: [FinancialDailyAggregate] { snapshot?.dailySpending ?? [] }
    private var hasValues: Bool { points.contains { $0.personalNetExpensesEURMinor != 0 } }

    var body: some View {
        DashboardModuleCard {
            VStack(alignment: .leading, spacing: 15) {
                WidgetHeader(title: "Daily spending", systemImage: "chart.bar")
                if hasValues {
                    Chart {
                        RuleMark(y: .value("Zero", 0)).foregroundStyle(.secondary.opacity(0.4))
                        ForEach(points) { point in
                            BarMark(x: .value("Day", chartDate(point.day)),
                                    y: .value("Net personal spending",
                                              plotAmount(point.personalNetExpensesEURMinor)))
                                .foregroundStyle(point.personalNetExpensesEURMinor < 0
                                    ? EasyTrackTheme.coral : EasyTrackTheme.accent)
                                .cornerRadius(3)
                        }
                    }
                    .chartXAxis { dateAxisMarks() }
                    .chartYAxis { currencyAxisMarks() }
                    .chartXSelection(value: $selectedDate)
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 260 : 210)
                    .accessibilityRepresentation { dailyAccessibility }
                    .onChange(of: selectedDate) { _, value in
                        guard let value, let snapshot else { return }
                        let day = LocalDay(date: value, timeZone: .current)
                        let ids = snapshot.chartSelectionIndex.dailySpending[day] ?? []
                        openActivity(ids: ids, label: "Daily spending · \(day.isoString)",
                                     snapshot: snapshot, navigation: navigation)
                        selectedDate = nil
                    }
                    Text("Includes zero-spend days and signed personal adjustments.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ChartEmptyState("No personal spending in this period.")
                }
            }
        }
        .accessibilityIdentifier("homeDailySpendingWidget")
    }

    private var dailyAccessibility: some View {
        VStack(alignment: .leading) {
            Text("Daily personal spending")
            ForEach(points) { point in
                Text("\(point.day.isoString): \(Money.format(point.personalNetExpensesEURMinor))")
            }
        }
    }
}

struct TopMerchantsWidget: View {
    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var navigation: AppNavigationModel
    @State private var selectedMerchant: String?
    @State private var rejectedSuggestions: Set<String> = []
    let snapshot: FinancialAnalyticsSnapshot?

    private var merchants: [FinancialMerchantAggregate] {
        guard let snapshot else { return [] }
        return (try? MerchantAnalytics.grouped(snapshot.merchants, aliases: store.merchantAliasGroups))
            ?? snapshot.merchants
    }
    private var displayed: [FinancialMerchantAggregate] { Array(merchants.prefix(5)) }
    private var suggestion: MerchantGroupingSuggestion? {
        guard let snapshot else { return nil }
        return MerchantAnalytics.suggestions(from: snapshot.merchants, aliases: store.merchantAliasGroups)
            .first { !rejectedSuggestions.contains($0.id) }
    }

    var body: some View {
        DashboardModuleCard {
            VStack(alignment: .leading, spacing: 15) {
                WidgetHeader(title: "Top merchants", systemImage: "building.2")
                if displayed.isEmpty {
                    ChartEmptyState("No personal spending descriptions in this period.")
                } else {
                    Chart(displayed) { merchant in
                        BarMark(x: .value("Net amount", plotAmount(merchant.personalNetExpensesEURMinor)),
                                y: .value("Merchant", merchant.name))
                            .foregroundStyle(merchant.personalNetExpensesEURMinor < 0
                                ? EasyTrackTheme.coral : EasyTrackTheme.accent)
                            .cornerRadius(4)
                    }
                    .chartXAxis { currencyAxisMarks() }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .chartYSelection(value: $selectedMerchant)
                    .frame(height: max(170, CGFloat(displayed.count) * 38))
                    .accessibilityRepresentation { merchantAccessibility }
                    .onChange(of: selectedMerchant) { _, value in
                        guard let value, let snapshot,
                              let merchant = displayed.first(where: { $0.name == value }) else { return }
                        openActivity(ids: Set(merchant.transactionIDs), label: "Merchant · \(merchant.name)",
                                     snapshot: snapshot, navigation: navigation)
                        selectedMerchant = nil
                    }
                }

                if let suggestion {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Suggested group: \(suggestion.canonicalName)").font(.subheadline.weight(.semibold))
                        Text(suggestion.memberNames.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Group") { approve(suggestion) }.buttonStyle(.borderedProminent)
                            Button("Not now") { rejectedSuggestions.insert(suggestion.id) }.buttonStyle(.bordered)
                        }
                    }
                    .padding(12)
                    .background(EasyTrackTheme.jadeWash,
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }

                ForEach(store.merchantAliasGroups) { group in
                    HStack {
                        Label(group.canonicalName, systemImage: "link")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Button("Undo") { undo(group) }.font(.caption.weight(.semibold))
                    }
                }
            }
        }
        .accessibilityIdentifier("homeTopMerchantsWidget")
    }

    private var merchantAccessibility: some View {
        VStack(alignment: .leading) {
            Text("Top merchants")
            ForEach(displayed) { merchant in
                Text("\(merchant.name): \(Money.format(merchant.personalNetExpensesEURMinor)), \(merchant.transactionCount) movements")
            }
        }
    }

    private func approve(_ suggestion: MerchantGroupingSuggestion) {
        let now = Date()
        do {
            try store.saveMerchantAliasGroup(MerchantAliasGroup(id: UUID(),
                canonicalName: suggestion.canonicalName, memberKeys: suggestion.memberKeys,
                createdAt: now, updatedAt: now))
        } catch { store.errorMessage = error.localizedDescription }
    }

    private func undo(_ group: MerchantAliasGroup) {
        do { try store.deleteMerchantAliasGroup(group.id) }
        catch { store.errorMessage = error.localizedDescription }
    }
}

private struct WidgetHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.title3.bold())
            .foregroundStyle(EasyTrackTheme.primaryText)
    }
}

private struct ChartLegendKey: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ChartEmptyState: View {
    let message: String

    init(_ message: String) { self.message = message }

    var body: some View {
        Label(message, systemImage: "chart.bar.xaxis")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
            .multilineTextAlignment(.center)
    }
}

private func plotAmount(_ minor: Int64) -> Double {
    Double(minor) / 100
}

private func chartDate(_ day: LocalDay) -> Date {
    day.noon(in: .current) ?? .distantPast
}

private func monthLabel(_ day: LocalDay) -> String {
    chartDate(day).formatted(.dateTime.month(.wide).year())
}

@MainActor
private func openActivity(ids: Set<UUID>, label: String, snapshot: FinancialAnalyticsSnapshot,
                          navigation: AppNavigationModel) {
    var filter = snapshot.appliedFilter
    filter.transactionIDs = ids
    navigation.showActivity(label: label, filter: filter)
}

@AxisContentBuilder
private func currencyAxisMarks() -> some AxisContent {
    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
        AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
        AxisValueLabel {
            if let amount = value.as(Double.self) {
                Text(amount, format: .currency(code: "EUR").precision(.fractionLength(0)))
            }
        }
    }
}

@AxisContentBuilder
private func dateAxisMarks() -> some AxisContent {
    AxisMarks(values: .automatic(desiredCount: 5)) { value in
        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
        AxisValueLabel {
            if let date = value.as(Date.self) {
                Text(date, format: .dateTime.day().month(.abbreviated))
            }
        }
    }
}
