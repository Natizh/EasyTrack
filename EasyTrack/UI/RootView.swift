import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var store: FinanceStore
    @StateObject private var navigation = AppNavigationModel()
    private var theme: EasyTrackTheme { EasyTrackTheme(preferences: store.appearancePreferences) }

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(EasyTrackTab.home)
            NavigationStack { TransactionsView() }
                .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }
                .tag(EasyTrackTab.activity)
            NavigationStack { AutomationsView() }
                .tabItem { Label("Automations", systemImage: "bolt.badge.clock") }
                .tag(EasyTrackTab.automations)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(EasyTrackTab.settings)
        }
        .environmentObject(navigation)
        .environment(\.easyTrackTheme, theme)
        .tint(theme.accent)
        .preferredColorScheme(store.appearancePreferences.colorScheme.preferredColorScheme)
        .alert("EasyTrack", isPresented: Binding(get: { store.errorMessage != nil },
                                                  set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .fullScreenCover(isPresented: Binding(
            get: { store.shouldPresentOnboarding }, set: { _ in })) {
                NavigationStack {
                    OnboardingView {
                        do { try store.completeOnboarding(); return true }
                        catch { store.errorMessage = error.localizedDescription; return false }
                    }
                }
            }
    }
}

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.easyTrackTheme) private var theme
    @State private var page = 0
    let onFinish: () -> Bool

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                onboardingPage(symbol: "chart.line.uptrend.xyaxis", title: "Welcome to EasyTrack",
                    message: "Record income and expenses, understand spending, manage budgets and reimbursements, and—where supported—import movements from notifications through Shortcuts.") {
                    Label("No bank account, login, or permission is required to begin.", systemImage: "checkmark.shield")
                }
                .tag(0)

                onboardingPage(symbol: "lock.shield", title: "Private ledger, manual backups",
                    message: "The working database stays in EasyTrack private storage. JSON backup export is manual: you choose and safeguard the file in Files, iCloud Drive, or another provider.") {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("A file in iCloud Drive is a snapshot, not live device synchronization.", systemImage: "icloud.slash")
                        Label("Deleting the app without an external backup can remove the local ledger.", systemImage: "externaldrive.badge.exclamationmark")
                        Label("EasyTrack cannot indiscriminately read every notification from other apps.", systemImage: "bell.slash")
                    }
                }
                .tag(1)

                onboardingPage(symbol: "slider.horizontal.3", title: "Optional setup",
                    message: "Set up only what you need now. You can skip everything and return from Settings at any time.") {
                    VStack(alignment: .leading, spacing: 10) {
                        NavigationLink { AccountsView() } label: {
                            Label("Accounts", systemImage: "creditcard")
                        }
                        NavigationLink { CategoriesView() } label: {
                            Label("Categories", systemImage: "square.grid.2x2")
                        }
                        NavigationLink { NotificationSetupGuideView() } label: {
                            Label("Automatic notification setup", systemImage: "list.number")
                        }
                        Text("The notification link opens the same complete guide used in Automations; it does not request permission or create a transaction.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.bordered)
                }
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            HStack {
                Button("Back") { withAnimation { page -= 1 } }
                    .disabled(page == 0)
                Spacer()
                Button(page == 2 ? "Finish" : "Continue") {
                    if page == 2 { finish() }
                    else { withAnimation { page += 1 } }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .background(.bar)
        }
        .navigationTitle("Getting started")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Skip") { finish() }.accessibilityIdentifier("skipOnboarding")
            }
        }
        .interactiveDismissDisabled()
        .accessibilityIdentifier("onboardingPage-\(page + 1)")
    }

    private func finish() {
        if onFinish() { dismiss() }
    }

    private func onboardingPage<Content: View>(symbol: String, title: String, message: String,
                                                @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: symbol)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 82, height: 82)
                    .background(theme.accentWash, in: RoundedRectangle(cornerRadius: 24))
                    .accessibilityHidden(true)
                Text(title).font(.largeTitle.bold())
                Text(message).font(.title3).foregroundStyle(.secondary)
                content().font(.subheadline)
                Spacer(minLength: 20)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(28)
        }
        .background(theme.canvas)
    }
}

private struct DemoBanner: View {
    @Environment(\.easyTrackTheme) private var theme
    let hasDemo: Bool
    var body: some View {
        Label(hasDemo ? "Demo entries are marked · History not imported" : "Historical seed not imported",
              systemImage: "info.circle")
            .font(.caption.weight(.medium))
            .foregroundStyle(theme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(theme.accentWash, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct TransactionRow: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.easyTrackTheme) private var theme
    let item: Transaction

    private var displayedEURMinor: Int64? {
        item.eurMinor ?? (item.currency == "EUR" ? item.amountMinor : nil)
    }
    private var categoryName: String {
        if let id = item.categoryID,
           let managed = store.ledgerCategories.first(where: { $0.id == id }) { return managed.name }
        return item.category.isEmpty ? "Uncategorized" : item.category
    }
    private var managedCategory: LedgerCategory? {
        item.categoryID.flatMap { id in store.ledgerCategories.first { $0.id == id } }
    }
    private var reimbursementStatus: ExpenseReimbursementStatus? {
        store.reimbursementStatuses.first { $0.expenseID == item.id }
    }

    private var movementIcon: some View {
        let fallback = MovementIconResolver.fallback(description: item.merchant, kind: item.kind)
        let symbol = managedCategory?.symbolName ?? fallback.symbolName
        let color = LedgerColor.color(managedCategory?.colorName ?? fallback.colorName)
        return Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 42, height: 42)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
            .accessibilityHidden(true)
    }

    private var movementLabels: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.merchant).font(.subheadline.weight(.semibold)).foregroundStyle(theme.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            Text("\(item.kind.title) · \(categoryName)")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
            if let reimbursementStatus {
                Text(reimbursementStatus.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(reimbursementStatus.outstandingEURMinor > 0 ? theme.accent : .secondary)
            }
        }
    }

    private var movementAmount: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(displayedEURMinor.map { "\(item.kind.isOutflow ? "−" : "+")\(Money.format($0))" } ?? "EUR amount unavailable")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(item.kind.isOutflow ? theme.primaryText : theme.accent)
            Text(item.occurredAt.formatted(.dateTime.day().month(.abbreviated)))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 13) {
                        movementIcon
                        movementLabels
                        Spacer(minLength: 0)
                    }
                    HStack {
                        Spacer(minLength: 0)
                        movementAmount
                    }
                }
            } else {
                HStack(spacing: 13) {
                    movementIcon
                    movementLabels
                    Spacer(minLength: 4)
                    movementAmount
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HomeView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.easyTrackTheme) private var theme
    @State private var showingNew = false
    @State private var showingDashboardEditor = false

    private var homeTransactions: [Transaction] {
        let active = store.transactions.filter { $0.deletedAt == nil }
        let real = active.filter { !$0.isDemo }
        return real.isEmpty ? active : real
    }
    private var currentMonthSnapshot: FinancialAnalyticsSnapshot? {
        try? FinancialAnalytics.snapshot(transactions: homeTransactions,
            period: .month(containing: .now, timeZone: .current),
            categoryNames: Dictionary(uniqueKeysWithValues: store.ledgerCategories.map { ($0.id, $0.name) }),
            tripNames: Dictionary(uniqueKeysWithValues: store.historicalTrips.map { ($0.id, $0.name) }))
    }
    private var recentTransactions: ArraySlice<Transaction> { homeTransactions.prefix(3) }
    private var uncategorized: [Transaction] {
        store.transactions.filter { !$0.isDemo && $0.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    private var upcoming: [UpcomingRecurringItem] { store.upcomingRecurring() }
    private var dueExpected: [RecurringOccurrence] {
        store.recurringOccurrences.filter { occurrence in
            guard occurrence.status == .expected,
                  let rule = store.recurringRules.first(where: { $0.id == occurrence.ruleID }) else { return false }
            return occurrence.scheduledDay <= LocalDay(date: .now,
                timeZone: TimeZone(identifier: rule.timeZoneIdentifier) ?? .current)
        }
    }
    private var needsReview: Int { store.recurringCandidates.filter { $0.status == .pending }.count }
    private var recentPaid: RecurringOccurrence? {
        store.recurringOccurrences.first { $0.status == .confirmed && $0.transactionID != nil }
    }

    private var recurringWidget: some View {
        DashboardModuleCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Label("Upcoming", systemImage: "calendar")
                        .font(.title3.bold()).foregroundStyle(theme.primaryText)
                    Spacer()
                    NavigationLink("Manage") { RecurringListView() }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(theme.accent)
                }
                if upcoming.isEmpty {
                    Text("No repeating payments expected in the next 30 days.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(upcoming.prefix(1)) { item in
                        UpcomingRecurringRow(item: item)
                    }
                    if upcoming.count > 1 {
                        Text("\(upcoming.count - 1) more expected in the next 30 days")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !dueExpected.isEmpty {
                    if let due = dueExpected.first,
                       let rule = store.recurringRules.first(where: { $0.id == due.ruleID }) {
                        let today = LocalDay(date: .now,
                            timeZone: TimeZone(identifier: rule.timeZoneIdentifier) ?? .current)
                        let dueStatus = due.scheduledDay < today ? "Overdue" : "Expected today"
                        NavigationLink { RecurringOccurrenceDetailView(occurrenceID: due.id) } label: {
                            Label("\(dueStatus) · \(rule.name)", systemImage: "clock")
                        }
                        .font(.subheadline.weight(.medium))
                        .accessibilityIdentifier("homeRecurringDueStatus")
                    }
                    Text("\(dueExpected.count) expected payment(s) are not included in totals.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let paid = recentPaid, let id = paid.transactionID,
                   let transaction = store.transactions.first(where: { $0.id == id }),
                   let rule = store.recurringRules.first(where: { $0.id == paid.ruleID }) {
                    NavigationLink { TransactionEditor(item: transaction) } label: {
                        Label("Paid · \(rule.name) · \(Money.format(transaction.eurMinor ?? transaction.amountMinor))",
                              systemImage: "checkmark.circle")
                    }
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("homeRecurringPaidStatus")
                }
                if needsReview > 0 {
                    NavigationLink { RecurringListView() } label: {
                        Label("\(needsReview) recurring match(es) need review",
                              systemImage: "exclamationmark.circle")
                    }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("homeRecurringNeedsReview")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeUpcomingSection")
    }

    @ViewBuilder
    private var uncategorizedWidget: some View {
        if !uncategorized.isEmpty {
            DashboardModuleCard {
                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        Label("Uncategorized", systemImage: "tag")
                            .font(.title3.bold()).foregroundStyle(theme.primaryText)
                        Spacer()
                        Text("\(uncategorized.count)")
                            .font(.caption.weight(.bold)).foregroundStyle(theme.accent)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(theme.accentWash, in: Capsule())
                    }
                    Text("Complete transactions waiting for an optional category.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(uncategorized.prefix(2)) { item in
                        NavigationLink { TransactionEditor(item: item) } label: { TransactionRow(item: item) }
                            .buttonStyle(.plain)
                        if item.id != uncategorized.prefix(2).last?.id {
                            Divider().padding(.leading, 55)
                        }
                    }
                    NavigationLink("Review and categorize") { UncategorizedTransactionsView() }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(theme.accent)
                        .padding(.top, 3)
                }
            }
            .accessibilityIdentifier("homeUncategorizedSection")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                FinancialHeroCard(snapshot: currentMonthSnapshot, periodTitle: "Current month")

                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        Text("Recent activity").font(.title3.bold()).foregroundStyle(theme.primaryText)
                        Spacer()
                        NavigationLink("See all") { TransactionsView() }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(theme.accent)
                    }
                    if recentTransactions.isEmpty {
                        ContentUnavailableView("No transactions", systemImage: "tray")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(recentTransactions) { item in
                            NavigationLink { TransactionEditor(item: item) } label: {
                                RecentTransactionCard(item: item,
                                    category: item.categoryID.flatMap { id in
                                        store.ledgerCategories.first { $0.id == id }
                                    })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !store.hasHistoricalImport {
                        DemoBanner(hasDemo: store.transactions.contains { $0.isDemo })
                    }
                }

                DashboardWidgetLayout(snapshot: currentMonthSnapshot,
                    widgets: DashboardWidgetRegistry.visible(preferences: store.dashboardWidgetPreferences)) {
                    recurringWidget
                } uncategorized: {
                    uncategorizedWidget
                }
            }
            .padding(20)
        }
        .background(theme.canvas)
        .navigationTitle("EasyTrack")
        .toolbar { ToolbarItemGroup(placement: .topBarTrailing) {
            Button { showingDashboardEditor = true } label: { Image(systemName: "slider.horizontal.3") }
                .accessibilityLabel("Customize Home")
                .accessibilityIdentifier("customizeHomeButton")
            Button { showingNew = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add transaction")
                .accessibilityIdentifier("homeAddTransactionButton")
        } }
        .sheet(isPresented: $showingNew) { NavigationStack { TransactionEditor() } }
        .sheet(isPresented: $showingDashboardEditor) {
            NavigationStack { DashboardWidgetEditorView() }
        }
    }
}

private struct UncategorizedTransactionsView: View {
    private struct UndoChange {
        let persisted: Transaction
        let categoryID: UUID?
        let categoryName: String
    }
    private struct RuleProposal {
        let description: String
        let categoryID: UUID
    }

    @EnvironmentObject private var store: FinanceStore
    @State private var undoChange: UndoChange?
    @State private var skippedIDs: Set<UUID> = []
    @State private var ruleProposal: RuleProposal?
    @State private var showingRuleProposal = false

    private var items: [Transaction] {
        store.transactions.filter { !$0.isDemo && $0.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    private var visibleItems: [Transaction] { items.filter { !skippedIDs.contains($0.id) } }

    var body: some View {
        List(visibleItems) { item in
            VStack(alignment: .leading, spacing: 10) {
                NavigationLink { TransactionEditor(item: item) } label: { TransactionRow(item: item) }
                CategorySuggestionsView(description: item.merchant, kind: item.kind) { category in
                    assign(category, to: item)
                }
                HStack {
                    Menu {
                        ForEach(store.ledgerCategories.filter { $0.archivedAt == nil }) { category in
                            Button {
                                assign(category, to: item)
                            } label: {
                                Label(category.name, systemImage: category.symbolName)
                            }
                        }
                    } label: {
                        Label("All categories", systemImage: "tag.circle.fill")
                    }
                    .accessibilityLabel("Assign category to \(item.merchant)")
                    Spacer()
                    Button("Skip") { skippedIDs.insert(item.id) }
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Uncategorized")
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("All categorized", systemImage: "checkmark.circle")
            } else if visibleItems.isEmpty {
                ContentUnavailableView {
                    Label("Review complete", systemImage: "checkmark.circle")
                } description: {
                    Text("Skipped movements were not changed.")
                } actions: {
                    Button("Review skipped") { skippedIDs.removeAll() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if undoChange != nil {
                HStack {
                    Text("Category saved").font(.subheadline.weight(.semibold))
                    Spacer()
                    if ruleProposal != nil {
                        Button("Save rule") { showingRuleProposal = true }
                            .font(.subheadline.weight(.bold))
                    }
                    Button("Undo") { undo() }.font(.subheadline.weight(.bold))
                }
                .padding()
                .background(.bar, in: Capsule())
                .padding(.horizontal)
                .accessibilityIdentifier("uncategorizedUndoCategory")
            }
        }
        .sheet(isPresented: $showingRuleProposal) {
            if let ruleProposal {
                NavigationStack { SaveCategoryRuleView(description: ruleProposal.description,
                                                       categoryID: ruleProposal.categoryID) }
            }
        }
    }

    private func assign(_ category: LedgerCategory, to item: Transaction) {
        var updated = item
        updated.categoryID = category.id
        updated.category = category.name
        do {
            let persisted = try store.save(updated)
            undoChange = UndoChange(persisted: persisted, categoryID: item.categoryID,
                                    categoryName: item.category)
            ruleProposal = RuleProposal(description: item.merchant, categoryID: category.id)
        } catch { store.errorMessage = error.localizedDescription }
    }

    private func undo() {
        guard let change = undoChange else { return }
        var restored = change.persisted
        restored.categoryID = change.categoryID
        restored.category = change.categoryName
        do {
            _ = try store.save(restored)
            undoChange = nil
            ruleProposal = nil
        } catch { store.errorMessage = error.localizedDescription }
    }
}

private struct TransactionsView: View {
    private struct ExportRequest: Identifiable {
        let id = UUID()
        let filter: TransactionFilter
    }

    @EnvironmentObject private var store: FinanceStore
    @EnvironmentObject private var navigation: AppNavigationModel
    @Environment(\.easyTrackTheme) private var theme
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @State private var kind: TransactionKind?
    @State private var category = "All categories"
    @State private var accountFilter: String?
    @State private var tripFilter: String?
    @State private var currencyFilter: String?
    @State private var pendingReimbursementsOnly = false
    @State private var showingNew = false
    @State private var exportRequest: ExportRequest?
    @State private var selectedTransactionID: UUID?

    private var categories: [String] { ["All categories"] + Array(Set(store.transactions.map(\.category))).sorted() }
    private var accounts: [String] { Array(Set(store.transactions.map(\.account))).sorted() }
    private var currencies: [String] { Array(Set(store.transactions.map(\.currency))).sorted() }
    private var currentActivityFilter: TransactionFilter {
        var filter = TransactionFilter(query: search, kind: kind,
                                       category: category == "All categories" ? nil : category,
                                       account: accountFilter, tripID: tripFilter, currency: currencyFilter)
        if pendingReimbursementsOnly {
            filter.transactionIDs = Set(store.reimbursementStatuses
                .filter { $0.outstandingEURMinor > 0 }.map(\.expenseID))
        }
        return filter
    }
    private var activityFiltered: [Transaction] {
        currentActivityFilter
            .apply(to: store.transactions,
                   tripNames: Dictionary(uniqueKeysWithValues: store.historicalTrips.map { ($0.id, $0.name) }))
    }
    private var filtered: [Transaction] {
        guard let scope = navigation.activityChartScope else { return activityFiltered }
        return scope.filter.apply(to: activityFiltered,
            tripNames: Dictionary(uniqueKeysWithValues: store.historicalTrips.map { ($0.id, $0.name) }))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let scope = navigation.activityChartScope {
                HStack(spacing: 10) {
                    Label(scope.label, systemImage: "chart.bar.xaxis")
                        .font(.subheadline.weight(.semibold)).lineLimit(2)
                    Spacer()
                    Button("Remove") { navigation.clearChartScope() }
                        .font(.subheadline.weight(.semibold))
                }
                .padding(12)
                .background(theme.accentWash, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20).padding(.top, 8)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("activityChartFilter")
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search transactions", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { searchFocused = false }
                    .accessibilityIdentifier("transactionSearchField")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20).padding(.top, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("All", selected: kind == nil) { kind = nil }
                    filterChip("Pending reimbursements", selected: pendingReimbursementsOnly) {
                        pendingReimbursementsOnly.toggle()
                    }
                    ForEach(TransactionKind.allCases) { option in
                        filterChip(option.title, selected: kind == option) { kind = option }
                    }
                    Menu {
                        ForEach(categories, id: \.self) { value in
                            Button(value.isEmpty ? "Uncategorized" : value) { category = value }
                        }
                    } label: {
                        Label(category.isEmpty ? "Uncategorized" : category,
                              systemImage: "line.3.horizontal.decrease")
                            .font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 9)
                            .background(theme.surface, in: Capsule())
                    }
                    Menu {
                        Button("All accounts") { accountFilter = nil }
                        ForEach(accounts, id: \.self) { value in Button(value.isEmpty ? "Unspecified" : value) { accountFilter = value } }
                    } label: { filterMenuLabel(accountFilter?.isEmpty == true ? "Unspecified" : accountFilter ?? "All accounts") }
                    Menu {
                        Button("All trips") { tripFilter = nil }
                        ForEach(store.historicalTrips) { trip in Button(trip.name) { tripFilter = trip.id } }
                    } label: { filterMenuLabel(store.historicalTrips.first(where: { $0.id == tripFilter })?.name ?? "All trips") }
                    Menu {
                        Button("All currencies") { currencyFilter = nil }
                        ForEach(currencies, id: \.self) { value in Button(value) { currencyFilter = value } }
                    } label: { filterMenuLabel(currencyFilter ?? "All currencies") }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
            List {
                if !store.hasHistoricalImport {
                    Section { DemoBanner(hasDemo: store.transactions.contains { $0.isDemo })
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                }
                Section("Transactions · \(filtered.count)") {
                    ForEach(filtered) { item in
                        Button {
                            searchFocused = false
                            selectedTransactionID = item.id
                        } label: {
                            HStack {
                                TransactionRow(item: item)
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Edit transaction")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if filtered.isEmpty {
                    if navigation.activityChartScope != nil {
                        ContentUnavailableView("No matching transactions", systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("The chart selection and current Activity filters do not overlap."))
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
        }
        .background(theme.canvas)
        .navigationTitle("Activity")
        .onDisappear { searchFocused = false }
        .toolbar { ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                searchFocused = false
                exportRequest = ExportRequest(filter: navigation.activityChartScope == nil
                    ? currentActivityFilter
                    : TransactionFilter(transactionIDs: Set(filtered.map(\.id))))
            } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Export filtered transactions")
                .accessibilityIdentifier("activityExportTransactions")
            Button { showingNew = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add transaction")
        } }
        .sheet(isPresented: $showingNew) { NavigationStack { TransactionEditor() } }
        .sheet(item: $exportRequest) { request in
            NavigationStack { TransactionExportView(activityFilter: request.filter) }
        }
        .navigationDestination(item: $selectedTransactionID) { id in
            if let item = store.transactions.first(where: { $0.id == id }) {
                TransactionEditor(item: item)
            }
        }
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.subheadline.weight(.medium)).padding(.horizontal, 15).padding(.vertical, 9) }
            .foregroundStyle(selected ? .white : theme.primaryText)
            .background(selected ? theme.accent : theme.surface, in: Capsule())
    }

    private func filterMenuLabel(_ title: String) -> some View {
        Label(title, systemImage: "line.3.horizontal.decrease")
            .font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 9)
            .background(theme.surface, in: Capsule())
    }
}

struct TransactionEditor: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.easyTrackTheme) private var theme
    private let original: Transaction?
    private let sourceEventID: UUID?
    @State private var kind: TransactionKind
    @State private var amount: String
    @State private var merchant: String
    @State private var account: String
    @State private var accountID: UUID?
    @State private var category: String
    @State private var categoryID: UUID?
    @State private var subcategory: String
    @State private var tripID: String
    @State private var paidBy: String
    @State private var affectsMyAccounts: Bool
    @State private var note: String
    @State private var occurredAt: Date
    @State private var showDelete = false
    @State private var showUnlink = false
    @State private var isSaving = false
    @State private var validation: String?
    @State private var choosingAccount = false
    @State private var choosingCategory = false
    @State private var expectsReimbursement: Bool
    @State private var expectedReimbursementAmount: String
    @State private var showingReimbursementSettlement = false
    @State private var confirmingReimbursementWriteOff = false
    @State private var manualCategoryChanged = false
    @State private var showingCategoryRuleProposal = false

    init(item: Transaction? = nil, prefillEvent: NotificationEvent? = nil) {
        original = item
        sourceEventID = item?.sourceEventID ?? prefillEvent?.id
        _kind = State(initialValue: item?.kind ?? .expense)
        let editableEUR = item.flatMap { $0.currency == "EUR" ? $0.amountMinor : $0.eurMinor }
        _amount = State(initialValue: editableEUR.map { Money.editString($0) } ?? "")
        _merchant = State(initialValue: item?.merchant ?? "")
        _account = State(initialValue: item?.account ?? "")
        _accountID = State(initialValue: item?.accountID)
        _category = State(initialValue: item?.category ?? "")
        _categoryID = State(initialValue: item?.categoryID)
        _subcategory = State(initialValue: item?.subcategory ?? "")
        _tripID = State(initialValue: item?.tripID ?? "")
        _paidBy = State(initialValue: item?.paidBy ?? "")
        _affectsMyAccounts = State(initialValue: item?.affectsMyAccounts ?? true)
        _note = State(initialValue: item?.note ?? prefillEvent.map { [$0.title, $0.subtitle, $0.message].filter { !$0.isEmpty }.joined(separator: " · ") } ?? "")
        _occurredAt = State(initialValue: item?.occurredAt ?? prefillEvent?.receivedAt ?? .now)
        let pending = item?.kind == .expense && (item?.recoverableEURMinor ?? 0) > 0
        _expectsReimbursement = State(initialValue: pending)
        _expectedReimbursementAmount = State(initialValue: pending
            ? Money.editString(item?.recoverableEURMinor ?? 0) : "")
    }

    private var reimbursementStatus: ExpenseReimbursementStatus? {
        guard let id = original?.id else { return nil }
        return store.reimbursementStatuses.first { $0.expenseID == id }
    }
    private var categorySuggestions: [CategorySuggestion] {
        CategorySuggestionEngine.suggestions(description: merchant, kind: kind,
            categories: store.ledgerCategories, userRules: store.categoryKeywordRules,
            isEnabled: store.categorySuggestionsEnabled)
    }

    var body: some View {
        Form {
            if original?.isDemo == true { Section { Label("Demonstration record", systemImage: "info.circle").foregroundStyle(theme.accent) } }
            if sourceEventID != nil && original == nil {
                Section { Text("Only the notification text was prefilled as a note. Enter and verify every transaction field before saving.")
                    .font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Transaction") {
                Picker("Type", selection: $kind) { ForEach(TransactionKind.allCases) { Text($0.title).tag($0) } }
                LabeledContent("Amount (EUR)") {
                    TextField("0,00", text: $amount)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("transactionAmountField")
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text("Description").font(.subheadline)
                    TextField("Merchant or description", text: $merchant, axis: .vertical)
                        .lineLimit(1...3)
                        .accessibilityIdentifier("transactionDescriptionField")
                }
                DatePicker("Date", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
                if let original, original.currency != "EUR" {
                    Text("Editing uses EUR. The original \(original.currency) amount stays in import data.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if let original, TransactionEditPolicy.hasSeparatePersonalShare(original) {
                    Text("This imported expense has a separate personal share. Changing its amount keeps that share unchanged.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let validation {
                    Text(validation).font(.footnote).foregroundStyle(.red)
                        .accessibilityIdentifier("transactionValidationMessage")
                }
            }
            if !categorySuggestions.isEmpty {
                Section {
                    CategorySuggestionsView(description: merchant, kind: kind) { selected in
                        categoryID = selected.id
                        category = selected.name
                        manualCategoryChanged = true
                    }
                }
            }
            Section("Details") {
                LabeledContent("Account") {
                    Button { choosingAccount = true } label: {
                        HStack {
                            Text(store.localAccounts.first(where: { $0.id == accountID })?.name ??
                                 (account.isEmpty ? "Choose account" : account))
                                .lineLimit(1).foregroundStyle(theme.accent)
                            Image(systemName: "chevron.up.chevron.down").font(.caption)
                        }
                    }
                    .accessibilityIdentifier("transactionAccountPicker")
                }
                LabeledContent("Category") {
                    HStack {
                        TextField("Uncategorized", text: $category).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("transactionCategoryField")
                        Button { choosingCategory = true } label: {
                            Image(systemName: "chevron.down.circle").foregroundStyle(theme.accent)
                        }
                            .accessibilityLabel("Choose category")
                            .accessibilityIdentifier("transactionCategoryPicker")
                    }
                }
                LabeledContent("Subcategory") {
                    TextField("Optional", text: $subcategory).multilineTextAlignment(.trailing)
                }
                if !store.historicalTrips.isEmpty {
                    Picker("Trip", selection: $tripID) {
                        Text("None").tag("")
                        ForEach(store.historicalTrips) { Text($0.name).tag($0.id) }
                    }
                }
                if original?.sourceMovementID != nil {
                    LabeledContent("Paid by") {
                        TextField("Optional", text: $paidBy).multilineTextAlignment(.trailing)
                    }
                    Toggle("Affects my accounts", isOn: $affectsMyAccounts)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Note").font(.subheadline)
                    TextField("Optional note", text: $note, axis: .vertical).lineLimit(2...5)
                }
            }
            if kind == .expense {
                Section("Reimbursement") {
                    Toggle("Mi aspetto un rimborso", isOn: $expectsReimbursement)
                        .disabled(reimbursementStatus != nil)
                        .accessibilityIdentifier("expectsReimbursementToggle")
                    if expectsReimbursement {
                        DisclosureGroup("Partial expected amount") {
                            LabeledContent("Expected (EUR)") {
                                TextField("0,00", text: $expectedReimbursementAmount)
                                    .keyboardType(.numbersAndPunctuation)
                                    .multilineTextAlignment(.trailing)
                                    .accessibilityIdentifier("expectedReimbursementAmountField")
                            }
                        }
                    }
                    if let status = reimbursementStatus {
                        LabeledContent("Status", value: status.title)
                        LabeledContent("Still expected", value: Money.format(status.outstandingEURMinor))
                        if status.outstandingEURMinor > 0 {
                            Button("Rimborso ricevuto") { showingReimbursementSettlement = true }
                                .accessibilityIdentifier("receiveReimbursementButton")
                            Button("Non riceverò il rimborso", role: .destructive) {
                                confirmingReimbursementWriteOff = true
                            }
                        }
                        if status.writtenOffEURMinor > 0 {
                            Button("Undo not-received adjustment") { undoReimbursementWriteOff() }
                        }
                        ForEach(status.linkedTransactionIDs, id: \.self) { reimbursementID in
                            Button("Unlink reimbursement \(shortID(reimbursementID))", role: .destructive) {
                                unlinkReimbursement(reimbursementID)
                            }
                        }
                    }
                }
            }
            if manualCategoryChanged, let categoryID,
               !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    Button("Salva questa regola") { showingCategoryRuleProposal = true }
                        .accessibilityIdentifier("saveCategoryRuleProposal")
                } footer: {
                    Text("Optional. Review the word or phrase before saving; this never categorizes automatically.")
                }
            }
            if let original, !original.isDemo {
                Section("Recurring payment") {
                    if let occurrenceID = original.recurringOccurrenceID,
                       let occurrence = store.recurringOccurrences.first(where: { $0.id == occurrenceID }) {
                        NavigationLink {
                            RecurringOccurrenceDetailView(occurrenceID: occurrenceID)
                        } label: {
                            LabeledContent("Scheduled \(occurrence.scheduledDay.isoString)",
                                           value: occurrence.status.title)
                        }
                        if occurrence.status == .confirmed {
                            Button("Unlink recurring payment") { showUnlink = true }
                        }
                    } else {
                        NavigationLink("Link to a recurring occurrence") {
                            RecurringTransactionLinkView(transactionID: original.id)
                        }
                    }
                }
            }
            if original != nil { Section { Button("Delete transaction", role: .destructive) { showDelete = true } } }
        }
        .navigationTitle(original == nil ? "New transaction" : "Edit transaction")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Save", action: save).fontWeight(.semibold).disabled(isSaving) }
            if original == nil { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        }
        .confirmationDialog("Delete this transaction?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
        }
        .confirmationDialog("Unlink recurring payment?", isPresented: $showUnlink,
                            titleVisibility: .visible) {
            Button("Unlink payment") {
                guard let id = original?.recurringOccurrenceID else { return }
                let occurrenceRevision = store.recurringOccurrences.first(where: { $0.id == id })?.revision
                do { try store.unlinkRecurringTransaction(id,
                    occurrenceRevision: occurrenceRevision,
                    transactionRevision: original?.revision) }
                catch { validation = error.localizedDescription }
            }
        } message: { Text("The actual transaction remains counted. The scheduled occurrence becomes expected; no old estimate is restored.") }
        .confirmationDialog("Mark the outstanding reimbursement as not received?",
                            isPresented: $confirmingReimbursementWriteOff,
                            titleVisibility: .visible) {
            Button("Mark as not received", role: .destructive) { writeOffReimbursement() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The unpaid amount becomes personal spending on the original expense date. No bank movement is created.")
        }
        .onChange(of: amount) { _, _ in validation = nil }
        .onChange(of: expectsReimbursement) { _, enabled in
            if enabled && expectedReimbursementAmount.isEmpty { expectedReimbursementAmount = amount }
        }
        .onChange(of: category) { _, value in
            categoryID = store.ledgerCategories.first {
                ($0.archivedAt == nil || $0.id == categoryID) &&
                    NotificationParser.normalize($0.name) == NotificationParser.normalize(value)
            }?.id
        }
        .sheet(isPresented: $choosingAccount) {
            NavigationStack {
                AccountSelectionView(selectedID: accountID) { selected in
                    accountID = selected.id
                    account = selected.name
                }
            }
        }
        .sheet(isPresented: $choosingCategory) {
            NavigationStack {
                CategorySelectionView(selectedID: categoryID) { selected in
                    categoryID = selected?.id
                    category = selected?.name ?? ""
                    manualCategoryChanged = selected != nil
                }
            }
        }
        .sheet(isPresented: $showingReimbursementSettlement) {
            if let id = original?.id {
                NavigationStack { ReimbursementSettlementView(expenseID: id) }
            }
        }
        .sheet(isPresented: $showingCategoryRuleProposal) {
            if let categoryID {
                NavigationStack { SaveCategoryRuleView(description: merchant, categoryID: categoryID) }
            }
        }
        .onAppear {
            if let status = reimbursementStatus {
                expectsReimbursement = true
                expectedReimbursementAmount = Money.editString(status.expectedEURMinor)
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        validation = nil
        let cents: Int64
        switch Money.validatedPositiveAmount(amount) {
        case .success(let parsed): cents = parsed
        case .failure(let error): validation = error.message; return
        }
        guard !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validation = "Enter a description."; return
        }
        if accountID == nil && (original == nil || account != original?.account) {
            validation = "Choose an account or add one in Accounts."; return
        }
        let normalizedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedCategory.isEmpty && categoryID == nil &&
            (original == nil || normalizedCategory != original?.category) {
            validation = "Choose an existing category or leave it uncategorized."; return
        }
        let values = TransactionEditPolicy.values(original: original, kind: kind, newEURMinor: cents)
        var item = original ?? Transaction(id: UUID(), kind: kind, amountMinor: cents, currency: "EUR",
                                           merchant: merchant, account: account, category: category,
                                           note: note, occurredAt: occurredAt, updatedAt: .now,
                                           deletedAt: nil, isDemo: false, revision: 0, sourceEventID: sourceEventID)
        item.kind = kind
        item.amountMinor = cents
        item.currency = "EUR"
        item.eurMinor = cents
        item.personalExpenseEURMinor = values.personal
        item.recoverableEURMinor = values.recoverable
        item.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        item.accountID = accountID
        item.account = store.localAccounts.first(where: { $0.id == accountID })?.name ??
            account.trimmingCharacters(in: .whitespacesAndNewlines)
        item.categoryID = categoryID
        item.category = store.ledgerCategories.first(where: { $0.id == categoryID })?.name ?? normalizedCategory
        item.subcategory = subcategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : subcategory.trimmingCharacters(in: .whitespacesAndNewlines)
        item.tripID = tripID.isEmpty ? nil : tripID
        item.paidBy = paidBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : paidBy.trimmingCharacters(in: .whitespacesAndNewlines)
        item.affectsMyAccounts = affectsMyAccounts
        item.note = note
        item.occurredAt = occurredAt
        let expectedReimbursement: Int64?
        if kind == .expense && expectsReimbursement {
            let text = expectedReimbursementAmount.isEmpty ? amount : expectedReimbursementAmount
            switch Money.validatedPositiveAmount(text) {
            case .success(let expected) where expected <= cents: expectedReimbursement = expected
            case .success: validation = "Expected reimbursement cannot exceed the expense."; return
            case .failure(let error): validation = error.message; return
            }
        } else { expectedReimbursement = nil }
        isSaving = true
        do {
            if let expectedReimbursement {
                try store.save(item, expectedReimbursementEURMinor: expectedReimbursement)
            } else {
                try store.save(item)
            }
            dismiss()
        } catch {
            validation = "Couldn’t save transaction. \(error.localizedDescription)"
            isSaving = false
        }
    }

    private func delete() {
        guard !isSaving, let original else { return }
        isSaving = true
        do {
            try store.delete(original)
            dismiss()
        } catch {
            validation = "Couldn’t delete transaction. \(error.localizedDescription)"
            isSaving = false
        }
    }

    private func writeOffReimbursement() {
        guard let id = original?.id else { return }
        do { try store.writeOffOutstandingReimbursement(id) }
        catch { validation = error.localizedDescription }
    }

    private func undoReimbursementWriteOff() {
        guard let id = original?.id else { return }
        do { try store.undoReimbursementWriteOff(id) }
        catch { validation = error.localizedDescription }
    }

    private func unlinkReimbursement(_ id: UUID) {
        do { try store.unlinkReimbursement(id) }
        catch { validation = error.localizedDescription }
    }

    private func shortID(_ id: UUID) -> String { String(id.uuidString.prefix(8)) }
}

private struct ReimbursementSettlementView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let expenseID: UUID
    @State private var amount = ""
    @State private var description = "Reimbursement received"
    @State private var occurredAt = Date()
    @State private var validation: String?

    private var expense: Transaction? { store.transactions.first { $0.id == expenseID } }
    private var status: ExpenseReimbursementStatus? {
        store.reimbursementStatuses.first { $0.expenseID == expenseID }
    }
    private var linkedIDs: Set<UUID> {
        Set(store.reimbursementStatuses.flatMap(\.linkedTransactionIDs))
    }
    private var candidates: [Transaction] {
        store.transactions.filter {
            $0.kind == .reimbursement && !linkedIDs.contains($0.id) && $0.deletedAt == nil
        }
    }

    var body: some View {
        Form {
            Section("Link an existing reimbursement") {
                if candidates.isEmpty {
                    Text("No unlinked reimbursement transactions are available.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(candidates) { candidate in
                    Button {
                        link(candidate)
                    } label: {
                        LabeledContent(candidate.merchant,
                            value: Money.format(candidate.eurMinor ?? candidate.amountMinor))
                    }
                }
            }
            Section("Record a new real reimbursement") {
                LabeledContent("Amount (EUR)") {
                    TextField("0,00", text: $amount).keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                }
                TextField("Description", text: $description)
                DatePicker("Received", selection: $occurredAt)
                Button("Record and link") { createAndLink() }
                    .disabled(expense == nil || status?.outstandingEURMinor == 0)
            }
            if let validation { Section { Text(validation).foregroundStyle(.red) } }
        }
        .navigationTitle("Rimborso ricevuto")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onAppear {
            if let outstanding = status?.outstandingEURMinor { amount = Money.editString(outstanding) }
        }
    }

    private func link(_ reimbursement: Transaction) {
        do {
            try store.linkReimbursement(expenseID: expenseID, reimbursementID: reimbursement.id)
            dismiss()
        } catch { validation = error.localizedDescription }
    }

    private func createAndLink() {
        guard let expense else { return }
        let cents: Int64
        switch Money.validatedPositiveAmount(amount) {
        case .success(let value): cents = value
        case .failure(let error): validation = error.message; return
        }
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validation = "Enter a description."; return
        }
        var reimbursement = Transaction(id: UUID(), kind: .reimbursement, amountMinor: cents,
            currency: "EUR", merchant: description.trimmingCharacters(in: .whitespacesAndNewlines),
            account: expense.account, category: "", note: "Linked reimbursement",
            occurredAt: occurredAt, updatedAt: .now, deletedAt: nil, isDemo: false,
            revision: 0, sourceEventID: nil)
        reimbursement.eurMinor = cents
        reimbursement.personalExpenseEURMinor = -cents
        reimbursement.recoverableEURMinor = 0
        reimbursement.accountID = expense.accountID
        do {
            _ = try store.createAndLinkReimbursement(expenseID: expenseID,
                                                     reimbursement: reimbursement)
            dismiss()
        } catch { validation = error.localizedDescription }
    }
}

struct AccountSelectionView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.easyTrackTheme) private var theme
    let selectedID: UUID?
    let onSelect: (LocalAccount) -> Void

    var body: some View {
        List {
            Section("Accounts") {
                ForEach(store.localAccounts.filter { $0.archivedAt == nil || $0.id == selectedID }) { option in
                    Button {
                        onSelect(option)
                        dismiss()
                    } label: {
                        HStack {
                            Label(option.name, systemImage: option.symbolName)
                            Spacer()
                            if selectedID == option.id { Image(systemName: "checkmark").foregroundStyle(theme.accent) }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            Section {
                NavigationLink { AccountsView() } label: { Label("Manage accounts", systemImage: "plus.circle") }
            }
        }
        .navigationTitle("Choose account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
    }
}

struct CategorySelectionView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.easyTrackTheme) private var theme
    let selectedID: UUID?
    let onSelect: (LedgerCategory?) -> Void

    var body: some View {
        List {
            Section("Category") {
                Button("Uncategorized") { onSelect(nil); dismiss() }
                ForEach(store.ledgerCategories.filter { $0.archivedAt == nil || $0.id == selectedID }) { option in
                    Button {
                        onSelect(option)
                        dismiss()
                    } label: {
                        HStack {
                            Label(option.name, systemImage: option.symbolName)
                            Spacer()
                            if selectedID == option.id { Image(systemName: "checkmark").foregroundStyle(theme.accent) }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            Section {
                NavigationLink { CategoriesView() } label: { Label("Manage categories", systemImage: "plus.circle") }
            }
        }
        .navigationTitle("Choose category")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
    }
}

private struct AppearanceSettingsView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.easyTrackTheme) private var theme
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("Preview") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Monthly overview").font(.caption.weight(.semibold))
                        .foregroundStyle(theme.heroSecondaryText)
                    Text(Money.format(123_456)).font(.title.bold()).monospacedDigit()
                        .foregroundStyle(theme.heroText)
                    HStack {
                        Label("Income", systemImage: "arrow.down.left")
                        Spacer()
                        Text(Money.format(250_000)).monospacedDigit()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.heroText)
                    .padding(10).background(theme.heroMetricBackground,
                                            in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: theme.heroColors,
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 22))
                .overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.heroBorder) }
            }

            Section("Theme") {
                ForEach(AppThemeStyle.allCases) { option in
                    Button { update { $0.theme = option } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.title).foregroundStyle(.primary)
                                Text(themeDescription(option)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.appearancePreferences.theme == option {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent)
                            }
                        }
                    }
                    .accessibilityValue(store.appearancePreferences.theme == option ? "Selected" : "Not selected")
                }
            }

            Section("Primary accent") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(AppAccentChoice.allCases) { option in
                        let selected = store.appearancePreferences.accent == option
                        Button { update { $0.accent = option } } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle().fill(option.color).frame(width: 30, height: 30)
                                    Circle().strokeBorder(selected ? Color.primary : Color.clear, lineWidth: 2)
                                        .frame(width: 38, height: 38)
                                    if selected { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) }
                                }
                                Text(option.title).font(.caption2).foregroundStyle(.primary).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(option.title) primary accent")
                        .accessibilityValue(selected ? "Selected" : "Not selected")
                    }
                }
                if store.appearancePreferences.theme == .graphite {
                    Text("Graphite stays monochrome. Your chosen accent is retained and becomes active again in Classic or Neutral.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Light and dark mode") {
                Picker("Appearance", selection: Binding(
                    get: { store.appearancePreferences.colorScheme },
                    set: { option in update { $0.colorScheme = option } })) {
                    ForEach(AppColorSchemePreference.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Text("Theme and accent update immediately and are included in Replace backups. Account colors, category colors, income/expense meaning and chart distinctions remain independent.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let statusMessage { Text(statusMessage).font(.footnote).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func update(_ change: (inout AppearancePreferences) -> Void) {
        var preferences = store.appearancePreferences
        change(&preferences)
        do {
            try store.saveAppearancePreferences(preferences)
            statusMessage = nil
        } catch { statusMessage = error.localizedDescription }
    }

    private func themeDescription(_ option: AppThemeStyle) -> String {
        switch option {
        case .classic: "The original Pine & Jade surfaces and hero."
        case .neutral: "System-like neutral surfaces with color only in details."
        case .graphite: "A restrained monochrome interface."
        }
    }
}

private struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(_ envelope: BackupArchive) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        data = try encoder.encode(envelope)
    }

    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct SettingsView: View {
    @EnvironmentObject private var store: FinanceStore
    private enum PickerPurpose { case seed, folder, backup }
    @State private var showingFilePicker = false
    @State private var pickerPurpose: PickerPurpose = .seed
    @State private var selectedSeedFile: URL?
    @State private var folderSelected = false
    @State private var probeStatus = "No folder selected"
    @State private var probing = false
    @State private var backupDocument: BackupDocument?
    @State private var showingExporter = false
    @State private var backupStatus: String?
    @State private var backupFilename = "EasyTrack-backup"
    @State private var restorePreview: BackupRestorePreview?
    @State private var restoreBusy = false
    @State private var restoreStatus: String?
    @State private var pendingRestoreMode: BackupRestoreMode?
    @State private var confirmingRestore = false
    @State private var confirmingDiagnosticClear = false
    @State private var notificationStatus: String?

    var body: some View {
        Form {
            Section("Everyday") {
                NavigationLink {
                    OnboardingView {
                        do { try store.completeOnboarding(); return true }
                        catch { store.errorMessage = error.localizedDescription; return false }
                    }
                } label: {
                    Label("Getting started", systemImage: "hand.wave")
                }
                .accessibilityIdentifier("settingsOnboardingLink")
                NavigationLink { AppearanceSettingsView() } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }
                .accessibilityIdentifier("settingsAppearanceLink")
                NavigationLink { AccountsView() } label: {
                    Label("Accounts", systemImage: "creditcard")
                }
                .accessibilityIdentifier("settingsAccountsLink")
                NavigationLink { CategoriesView() } label: {
                    Label("Categories", systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("settingsCategoriesLink")
                NavigationLink { CategorySuggestionSettingsView() } label: {
                    Label("Category suggestions", systemImage: "lightbulb")
                }
                .accessibilityIdentifier("settingsCategorySuggestionsLink")
                NavigationLink { BudgetsAndGoalsView() } label: {
                    Label("Budgets & goals", systemImage: "target")
                }
                .accessibilityIdentifier("settingsBudgetsGoalsLink")
                NavigationLink { RecurringListView() } label: {
                    Label("Recurring payments", systemImage: "repeat")
                }
                .accessibilityIdentifier("settingsRecurringLink")
            }
            Section("Notification automation") {
                NavigationLink { NotificationSetupGuideView() } label: {
                    Label("Setup guide", systemImage: "list.number")
                }
                .accessibilityIdentifier("settingsNotificationGuide")
                Picker("Raw diagnostic text", selection: Binding(
                    get: { store.notificationRetentionDays },
                    set: { days in
                        do {
                            let changed = try store.setNotificationRetentionDays(days)
                            notificationStatus = changed == 0 ? "Retention updated." :
                                "Retention updated; removed text from \(changed) diagnostic record\(changed == 1 ? "" : "s")."
                        } catch { notificationStatus = error.localizedDescription }
                    })) {
                    Text("Do not retain").tag(0)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                Button("Remove retained notification text now", role: .destructive) {
                    confirmingDiagnosticClear = true
                }
                Text("Only raw Title, Subtitle and Message text is removed. Source identity, diagnostic status and saved financial transactions remain. Expired text is purged at the next app open, capture or diagnostics visit.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let notificationStatus { Text(notificationStatus).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Storage") {
                Label("Local database · available offline", systemImage: "internaldrive")
                Text("EasyTrack.sqlite stays in this app’s private storage. Updates should keep it; deleting the app removes it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            HistoricalImportSection(selectedFile: $selectedSeedFile) {
                pickerPurpose = .seed
                showingFilePicker = true
            }
            HistoricalReferenceSection()
            Section("Folder access prototype") {
                Text("Select a folder in Files, then write and reread a small JSON test file. This does not synchronize transactions.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Choose folder in Files") {
                    pickerPurpose = .folder
                    showingFilePicker = true
                }
                Button(probing ? "Testing…" : "Write and read test file") { runProbe() }
                    .disabled(!folderSelected || probing)
                Text(probeStatus).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Section("Backup") {
                Toggle("Backup reminder", isOn: Binding(
                    get: { store.backupReminderPreferences.isEnabled },
                    set: { enabled in
                        do { try store.setBackupReminderEnabled(enabled) }
                        catch { backupStatus = error.localizedDescription }
                    }))
                if store.backupReminderPreferences.isDue() {
                    Label("A fresh manual backup is recommended", systemImage: "externaldrive.badge.exclamationmark")
                        .font(.subheadline).foregroundStyle(.orange)
                        .accessibilityIdentifier("backupReminderDue")
                }
                LabeledContent("Last successful export",
                    value: store.backupReminderPreferences.lastSuccessfulExportAt?.formatted(
                        date: .abbreviated, time: .shortened) ?? "Never recorded")
                Button("Export local data as JSON") {
                    do {
                        backupDocument = try BackupDocument(store.backup())
                        backupFilename = BackupFilename.make()
                        backupStatus = nil
                        showingExporter = true
                    }
                    catch { store.errorMessage = error.localizedDescription }
                }
                if let backupStatus { Text(backupStatus).font(.footnote).foregroundStyle(.secondary) }
                Button(restoreBusy ? "Checking backup…" : "Choose JSON backup to restore") {
                    pickerPurpose = .backup
                    showingFilePicker = true
                }
                .disabled(restoreBusy)
                .accessibilityIdentifier("chooseBackupToRestore")
                if let preview = restorePreview {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Backup preview · \(preview.exportedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.headline)
                        LabeledContent("Transactions", value: "\(preview.incomingTransactions)")
                        LabeledContent("Notification events", value: "\(preview.incomingEvents)")
                        LabeledContent("Parser and recurring rules", value: "\(preview.incomingRules)")
                        LabeledContent("Recurring occurrences", value: "\(preview.incomingOccurrences)")
                        LabeledContent("Historical identities", value: "\(preview.incomingHistoricalMovements)")
                        LabeledContent("Operation logs", value: "\(preview.incomingOperations)")
                        LabeledContent("Matching suggestions", value: "\(preview.incomingCandidates)")
                        LabeledContent("Approved payees", value: "\(preview.incomingApprovedPayees)")
                        LabeledContent("Reconciliation audit", value: "\(preview.incomingReconciliationAudit)")
                        if let source = preview.sourceFormatVersion {
                            Text(source == 5 ?
                                 "Format 5 omitted duplicate protection rows and historical expected links. Duplicate keys are rebuilt from attempts; omitted links cannot be recovered." :
                                 "Format 6 predates recurring reconciliation. Its active recurring estimates remain counted; deleted ones remain deleted. The file cannot restore newer matching decisions.")
                                .font(.footnote).foregroundStyle(.orange)
                            Text("Replacing current data with this older backup removes any newer recurring matches, aliases, candidates and audit decisions now on this phone (\(preview.existingReconciliationRows) local reconciliation rows). Review before confirming.")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                        Text("This phone currently has \(preview.existingTransactions) transactions. Replace removes its current ledger and installs the backup. Merge adds only new records with no conflicting identities.")
                            .font(.footnote)
                        if let conflict = preview.mergeConflict {
                            Text("Merge unavailable: conflicting \(conflict) records.")
                                .font(.footnote).foregroundStyle(.orange)
                        } else if let added = preview.newRowsForMerge {
                            Text("Merge would add \(added) records across all tables.")
                                .font(.footnote)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("backupRestorePreview")
                    Button("Replace local data", role: .destructive) {
                        pendingRestoreMode = .replace
                        confirmingRestore = true
                    }
                    .disabled(restoreBusy)
                    .accessibilityIdentifier("replaceFromBackup")
                    Button("Merge new records") {
                        pendingRestoreMode = .merge
                        confirmingRestore = true
                    }
                    .disabled(restoreBusy || preview.mergeConflict != nil)
                    .accessibilityIdentifier("mergeFromBackup")
                    Button("Discard backup preview", role: .cancel) {
                        restorePreview = nil
                        Task { await BackupRestoreCoordinator.shared.discard() }
                    }
                }
                if let restoreStatus { Text(restoreStatus).font(.footnote).accessibilityIdentifier("backupRestoreStatus") }
                Text("Export is always manual. Files lets you choose On My iPhone, iCloud Drive, or another available provider. An iCloud Drive backup is a snapshot file, not live synchronization between devices.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Keep backup files private: JSON may include imported history and retained notification diagnostics. Deleting EasyTrack without an external backup can permanently remove the local ledger; restoring later requires choosing the JSON file manually.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Transaction export") {
                NavigationLink { TransactionExportView(activityFilter: nil) } label: {
                    Label("Export transactions", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("settingsTransactionExport")
                Text("Save filtered CSV or Excel files. Backups are exported separately above.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("Version", value: "0.5 · everyday finances")
                LabeledContent("Currency in editor", value: "EUR")
            }
        }
        .navigationTitle("Settings")
        .task { folderSelected = await FolderProbe.shared.hasSavedFolder(); if folderSelected { probeStatus = "Folder bookmark saved" } }
        .sheet(isPresented: $showingFilePicker) {
            SystemDocumentPicker(contentTypes: pickerPurpose == .folder ? [.folder] :
                                 pickerPurpose == .backup ? [.json] : [.data]) { url in
                showingFilePicker = false
                if pickerPurpose == .seed { selectedSeedFile = url }
                else if pickerPurpose == .backup { stageBackup(url) }
                else {
                    Task {
                        do { try await FolderProbe.shared.select(url); folderSelected = true; probeStatus = "Folder bookmark saved" }
                        catch { probeStatus = error.localizedDescription }
                    }
                }
            } onCancel: {
                showingFilePicker = false
            }
        }
        .fileExporter(isPresented: $showingExporter, document: backupDocument, contentType: .json,
                      defaultFilename: backupFilename) { result in
            switch result {
            case .success(let url):
                do {
                    try store.recordSuccessfulBackupExport()
                    backupStatus = "Exported \(url.lastPathComponent)"
                } catch {
                    backupStatus = "The file was exported, but EasyTrack could not record the reminder date: \(error.localizedDescription)"
                }
            case .failure(let error):
                if (error as NSError).code == NSUserCancelledError { backupStatus = "Export cancelled." }
                else { store.errorMessage = error.localizedDescription }
            }
        }
        .confirmationDialog(pendingRestoreMode == .replace ? "Replace the local ledger?" : "Merge backup records?",
                            isPresented: $confirmingRestore, titleVisibility: .visible) {
            if pendingRestoreMode == .replace {
                Button("Replace local ledger", role: .destructive) { confirmBackup(.replace) }
            } else {
                Button("Merge new records") { confirmBackup(.merge) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let preview = restorePreview {
                Text(pendingRestoreMode == .replace
                     ? "Replace \(preview.existingTransactions) current transactions with \(preview.incomingTransactions) backed-up transactions and all related records? This cannot be undone here."
                     : "Add \(preview.newRowsForMerge ?? 0) new backed-up records? Existing records stay unchanged; any conflict cancels the whole merge.")
            }
        }
        .confirmationDialog("Remove retained notification text?", isPresented: $confirmingDiagnosticClear,
                            titleVisibility: .visible) {
            Button("Remove diagnostic text", role: .destructive) {
                do {
                    let changed = try store.clearNotificationDiagnosticContents()
                    notificationStatus = "Removed text from \(changed) diagnostic record\(changed == 1 ? "" : "s"). Saved transactions were unchanged."
                } catch { notificationStatus = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot restore the raw notification wording. Financial transactions, source mappings, rule history and aggregate statuses stay in EasyTrack.")
        }
    }

    private func stageBackup(_ url: URL) {
        restoreBusy = true
        restorePreview = nil
        restoreStatus = "Validating backup and checking local data…"
        Task {
            do {
                restorePreview = try await BackupRestoreCoordinator.shared.stage(url)
                restoreStatus = "Ready. No local records have changed."
            } catch { restoreStatus = error.localizedDescription }
            restoreBusy = false
        }
    }

    private func confirmBackup(_ mode: BackupRestoreMode) {
        restoreBusy = true
        restoreStatus = "Restoring and checking database integrity…"
        Task {
            do {
                let added = try await BackupRestoreCoordinator.shared.confirm(mode)
                store.reload()
                restorePreview = nil
                restoreStatus = mode == .replace
                    ? "Restore complete. Database integrity and reopen checks passed."
                    : "Merge complete. Added \(added) records; database integrity and reopen checks passed."
            } catch { restoreStatus = error.localizedDescription }
            restoreBusy = false
        }
    }

    private func runProbe() {
        probing = true
        probeStatus = "Writing and rereading…"
        Task {
            do {
                let operation = try await FolderProbe.shared.writeAndRead()
                probeStatus = "Read back OK · operation \(operation.operationID.uuidString)"
            } catch { probeStatus = error.localizedDescription }
            probing = false
        }
    }
}
