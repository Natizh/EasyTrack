import SwiftUI
import UniformTypeIdentifiers

private enum Palette {
    static let ink = EasyTrackTheme.primaryText
    static let heroInk = EasyTrackTheme.midnightPine
    static let heroTeal = EasyTrackTheme.deepTeal
    static let teal = EasyTrackTheme.accent
    static let mint = EasyTrackTheme.jadeWash
    static let canvas = EasyTrackTheme.canvas
    static let surface = EasyTrackTheme.surface
}

struct RootView: View {
    @EnvironmentObject private var store: FinanceStore

    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }
            NavigationStack { TransactionsView() }
                .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }
            NavigationStack { AutomationsView() }
                .tabItem { Label("Automations", systemImage: "bolt.badge.clock") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Palette.teal)
        .alert("EasyTrack", isPresented: Binding(get: { store.errorMessage != nil },
                                                  set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}

private struct DemoBanner: View {
    let hasDemo: Bool
    var body: some View {
        Label(hasDemo ? "Demo entries are marked · History not imported" : "Historical seed not imported",
              systemImage: "info.circle")
            .font(.caption.weight(.medium))
            .foregroundStyle(Palette.teal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Palette.mint, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct TransactionRow: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: Transaction

    private var displayedEURMinor: Int64? {
        item.eurMinor ?? (item.currency == "EUR" ? item.amountMinor : nil)
    }
    private var categoryName: String {
        if let id = item.categoryID,
           let managed = store.ledgerCategories.first(where: { $0.id == id }) { return managed.name }
        return item.category.isEmpty ? "Uncategorized" : item.category
    }

    private var movementIcon: some View {
        Image(systemName: item.kind.isOutflow ? "arrow.up.right" : "arrow.down.left")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(item.kind.isOutflow ? Palette.ink : Palette.teal)
            .frame(width: 42, height: 42)
            .background(item.kind.isOutflow ? Palette.canvas : Palette.mint, in: RoundedRectangle(cornerRadius: 13))
            .accessibilityHidden(true)
    }

    private var movementLabels: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.merchant).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            Text("\(item.kind.title) · \(categoryName)")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
        }
    }

    private var movementAmount: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(displayedEURMinor.map { "\(item.kind.isOutflow ? "−" : "+")\(Money.format($0))" } ?? "EUR amount unavailable")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(item.kind.isOutflow ? Palette.ink : Palette.teal)
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
                        .font(.title3.bold()).foregroundStyle(Palette.ink)
                    Spacer()
                    NavigationLink("Manage") { RecurringListView() }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.teal)
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
                            .font(.title3.bold()).foregroundStyle(Palette.ink)
                        Spacer()
                        Text("\(uncategorized.count)")
                            .font(.caption.weight(.bold)).foregroundStyle(Palette.teal)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Palette.mint, in: Capsule())
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
                    if uncategorized.count > 2 {
                        NavigationLink("See all") { UncategorizedTransactionsView() }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.teal)
                            .padding(.top, 3)
                    }
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
                        Text("Recent activity").font(.title3.bold()).foregroundStyle(Palette.ink)
                        Spacer()
                        NavigationLink("See all") { TransactionsView() }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.teal)
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
        .background(Palette.canvas)
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
    @EnvironmentObject private var store: FinanceStore

    private var items: [Transaction] {
        store.transactions.filter { !$0.isDemo && $0.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        List(items) { item in
            NavigationLink { TransactionEditor(item: item) } label: { TransactionRow(item: item) }
        }
        .navigationTitle("Uncategorized")
        .overlay { if items.isEmpty { ContentUnavailableView("All categorized", systemImage: "checkmark.circle") } }
    }
}

private struct TransactionsView: View {
    private struct ExportRequest: Identifiable {
        let id = UUID()
        let filter: TransactionFilter
    }

    @EnvironmentObject private var store: FinanceStore
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @State private var kind: TransactionKind?
    @State private var category = "All categories"
    @State private var accountFilter: String?
    @State private var tripFilter: String?
    @State private var currencyFilter: String?
    @State private var showingNew = false
    @State private var exportRequest: ExportRequest?
    @State private var selectedTransactionID: UUID?

    private var categories: [String] { ["All categories"] + Array(Set(store.transactions.map(\.category))).sorted() }
    private var accounts: [String] { Array(Set(store.transactions.map(\.account))).sorted() }
    private var currencies: [String] { Array(Set(store.transactions.map(\.currency))).sorted() }
    private var currentActivityFilter: TransactionFilter {
        TransactionFilter(query: search, kind: kind,
                          category: category == "All categories" ? nil : category,
                          account: accountFilter, tripID: tripFilter, currency: currencyFilter)
    }
    private var filtered: [Transaction] {
        currentActivityFilter
            .apply(to: store.transactions,
                   tripNames: Dictionary(uniqueKeysWithValues: store.historicalTrips.map { ($0.id, $0.name) }))
    }

    var body: some View {
        VStack(spacing: 0) {
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
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20).padding(.top, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("All", selected: kind == nil) { kind = nil }
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
                            .background(Palette.surface, in: Capsule())
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
                    ContentUnavailableView.search(text: search)
                }
            }
        }
        .background(Palette.canvas)
        .navigationTitle("Activity")
        .onDisappear { searchFocused = false }
        .toolbar { ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                searchFocused = false
                exportRequest = ExportRequest(filter: currentActivityFilter)
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
            .foregroundStyle(selected ? .white : Palette.ink)
            .background(selected ? Palette.heroTeal : Palette.surface, in: Capsule())
    }

    private func filterMenuLabel(_ title: String) -> some View {
        Label(title, systemImage: "line.3.horizontal.decrease")
            .font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 9)
            .background(Palette.surface, in: Capsule())
    }
}

struct TransactionEditor: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
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
    }

    var body: some View {
        Form {
            if original?.isDemo == true { Section { Label("Demonstration record", systemImage: "info.circle").foregroundStyle(Palette.teal) } }
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
            Section("Details") {
                LabeledContent("Account") {
                    Button { choosingAccount = true } label: {
                        HStack {
                            Text(store.localAccounts.first(where: { $0.id == accountID })?.name ??
                                 (account.isEmpty ? "Choose account" : account))
                                .lineLimit(1).foregroundStyle(Palette.teal)
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
                            Image(systemName: "chevron.down.circle").foregroundStyle(Palette.teal)
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
        .onChange(of: amount) { _, _ in validation = nil }
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
                }
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
        isSaving = true
        do {
            try store.save(item)
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
}

struct AccountSelectionView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
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
                            if selectedID == option.id { Image(systemName: "checkmark").foregroundStyle(Palette.teal) }
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
                            if selectedID == option.id { Image(systemName: "checkmark").foregroundStyle(Palette.teal) }
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

    var body: some View {
        Form {
            Section("Everyday") {
                NavigationLink { AccountsView() } label: {
                    Label("Accounts", systemImage: "creditcard")
                }
                .accessibilityIdentifier("settingsAccountsLink")
                NavigationLink { CategoriesView() } label: {
                    Label("Categories", systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("settingsCategoriesLink")
                NavigationLink { RecurringListView() } label: {
                    Label("Recurring payments", systemImage: "repeat")
                }
                .accessibilityIdentifier("settingsRecurringLink")
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
                Button("Export local data as JSON") {
                    do {
                        backupDocument = try BackupDocument(store.backup())
                        backupFilename = "EasyTrack-backup-\(Int(Date().timeIntervalSince1970))"
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
                Text("Keep backups private. They include raw notification text, imported history, and source rows.")
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
            case .success(let url): backupStatus = "Exported \(url.lastPathComponent)"
            case .failure(let error): store.errorMessage = error.localizedDescription
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
