import Charts
import SwiftUI

enum LedgerColor {
    static func color(_ name: String) -> Color {
        switch name {
        case "blue": .blue
        case "green": .green
        case "orange": .orange
        case "red": .red
        case "purple": .purple
        case "indigo": .indigo
        case "gray": .gray
        default: .teal
        }
    }
}

private struct LedgerColorPalette: View {
    @Binding var selection: String
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(LedgerAppearance.colors, id: \.self) { value in
                let selected = selection == value
                Button { selection = value } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(LedgerColor.color(value))
                                .frame(width: 30, height: 30)
                            Circle()
                                .strokeBorder(selected ? Color.primary : Color.clear, lineWidth: 2)
                                .frame(width: 38, height: 38)
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold()).foregroundStyle(.white)
                            }
                        }
                        Text(value.capitalized)
                            .font(.caption2).foregroundStyle(.primary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(value.capitalized) color")
                .accessibilityValue(selected ? "Selected" : "Not selected")
            }
        }
        .accessibilityIdentifier("ledgerColorPalette")
    }
}

struct AccountsView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.easyTrackTheme) private var theme
    @State private var selected: LocalAccount?
    @State private var showingNew = false

    private var active: [LocalAccount] { store.localAccounts.filter { $0.archivedAt == nil } }
    private var archived: [LocalAccount] { store.localAccounts.filter { $0.archivedAt != nil } }

    var body: some View {
        List {
            Section("New expenses") {
                Picker("Default for new expenses", selection: Binding(
                    get: { store.defaultExpenseAccountID },
                    set: { id in
                        do { try store.setDefaultExpenseAccountID(id) }
                        catch { store.errorMessage = error.localizedDescription }
                    })) {
                    Text("None").tag(UUID?.none)
                    ForEach(active) { account in Text(account.name).tag(Optional(account.id)) }
                }
                .accessibilityIdentifier("defaultExpenseAccountPicker")
                if let selected = active.first(where: { $0.id == store.defaultExpenseAccountID }) {
                    LabeledContent("Selected", value: selected.name)
                } else {
                    Text("Without a default, every new expense asks you to choose an account.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Active accounts") {
                if active.isEmpty { Text("Add an account to start recording transactions.").foregroundStyle(.secondary) }
                ForEach(active) { account in accountRow(account) }
            }
            if !archived.isEmpty {
                Section("Archived") { ForEach(archived) { account in accountRow(account) } }
            }
            Section {
                Text("Balances are shown only after opening balances and transfers can be represented accurately. Archiving keeps past transactions and notification mappings intact.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .listRowSpacing(theme.listRowSpacing)
        .navigationTitle("Accounts")
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { showingNew = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add account")
                .accessibilityIdentifier("addAccountButton")
        } }
        .sheet(isPresented: $showingNew) { NavigationStack { AccountEditorView() } }
        .sheet(item: $selected) { account in NavigationStack { AccountEditorView(account: account) } }
    }

    private func accountRow(_ account: LocalAccount) -> some View {
        Button { selected = account } label: {
            HStack(spacing: 12) {
                Image(systemName: account.symbolName)
                    .font(.headline).foregroundStyle(LedgerColor.color(account.colorName))
                    .frame(width: 44, height: 44)
                    .background(LedgerColor.color(account.colorName).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(account.nativeCurrency).font(.caption).foregroundStyle(.secondary)
                    if account.archivedAt != nil { Text("Archived").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(account.archivedAt == nil ? account.name : "\(account.name), archived")
        .accessibilityHint("Edit account")
        .accessibilityIdentifier("accountRow-\(account.name)")
    }
}

struct TripsView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.easyTrackTheme) private var theme
    @State private var showingNew = false

    var body: some View {
        List {
            Section("Trips") {
                if store.historicalTrips.isEmpty {
                    ContentUnavailableView("No trips", systemImage: "airplane",
                        description: Text("Create a trip, then assign expenses explicitly from the transaction editor."))
                }
                ForEach(store.historicalTrips) { trip in
                    NavigationLink { TripDetailView(tripID: trip.id) } label: {
                        Label(trip.name, systemImage: "airplane")
                    }
                    .accessibilityIdentifier("tripRow-\(trip.id)")
                }
            }
            Section {
                Text("Trip membership is explicit. Dates never add or remove transactions automatically, so advance bookings remain included.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .listRowSpacing(theme.listRowSpacing)
        .navigationTitle("Trips")
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { showingNew = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Create trip")
                .accessibilityIdentifier("addTripButton")
        } }
        .sheet(isPresented: $showingNew) { NavigationStack { TripEditorView() } }
    }
}

struct TripEditorView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let tripID: String?
    let onSave: ((HistoricalTrip) -> Void)?
    @State private var name: String
    @State private var validation: String?

    init(trip: HistoricalTrip? = nil, onSave: ((HistoricalTrip) -> Void)? = nil) {
        tripID = trip?.id
        self.onSave = onSave
        _name = State(initialValue: trip?.name ?? "")
    }

    var body: some View {
        Form {
            Section("Trip") {
                TextField("Name", text: $name).textInputAutocapitalization(.words)
                    .accessibilityIdentifier("tripNameField")
            }
            if let validation { Section { Text(validation).foregroundStyle(.red) } }
        }
        .navigationTitle(tripID == nil ? "New trip" : "Rename trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold) }
        }
    }

    private func save() {
        do {
            let saved = try store.saveTrip(id: tripID, name: name)
            onSave?(saved); dismiss()
        } catch { validation = error.localizedDescription }
    }
}

struct TripDetailView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.easyTrackTheme) private var theme
    let tripID: String
    @State private var editingTrip: HistoricalTrip?

    private var trip: HistoricalTrip? { store.historicalTrips.first { $0.id == tripID } }
    private var categoryNames: [UUID: String] {
        Dictionary(uniqueKeysWithValues: store.ledgerCategories.map { ($0.id, $0.name) })
    }
    private var snapshot: TripAnalyticsSnapshot? {
        try? FinancialAnalytics.tripSnapshot(transactions: store.transactions, tripID: tripID,
                                              categoryNames: categoryNames)
    }
    private var transactions: [Transaction] {
        let ids = Set(snapshot?.transactionIDs ?? [])
        return store.transactions.filter { ids.contains($0.id) }.sorted { $0.occurredAt > $1.occurredAt }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Net personal trip spending").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(Money.format(snapshot?.personalNetEURMinor ?? 0))
                        .font(.largeTitle.bold()).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Net personal trip spending, \(Money.format(snapshot?.personalNetEURMinor ?? 0))")
                if let missing = snapshot?.missingEURTransactionCount, missing > 0 {
                    Label("\(missing) linked movement(s) excluded because no EUR value is available",
                          systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
            if let snapshot, !snapshot.positiveCategories.isEmpty {
                Section("Positive category share") {
                    Chart(snapshot.positiveCategories) { category in
                        SectorMark(angle: .value("Amount", category.personalNetEURMinor), innerRadius: .ratio(0.58),
                                   angularInset: 1.5)
                            .foregroundStyle(categoryColor(category))
                    }
                    .frame(height: 220)
                    .chartLegend(.hidden)
                    .accessibilityLabel("Positive trip spending by category")
                    ForEach(snapshot.positiveCategories) { category in
                        HStack {
                            Circle().fill(categoryColor(category)).frame(width: 10, height: 10)
                            Text(category.name)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(Money.format(category.personalNetEURMinor)).monospacedDigit()
                                Text(percent(category, total: snapshot.positiveCategoryTotalEURMinor))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Text("Percentages use positive category spending only. Refunds and other non-positive adjustments are listed separately below.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let adjustments = snapshot?.nonPositiveCategories, !adjustments.isEmpty {
                Section("Refunds and non-positive adjustments") {
                    ForEach(adjustments) { category in
                        LabeledContent(category.name, value: Money.format(category.personalNetEURMinor))
                    }
                }
            }
            Section("Linked expenses") {
                if transactions.isEmpty {
                    ContentUnavailableView("No linked expenses", systemImage: "tray",
                        description: Text("Assign a trip explicitly from a transaction."))
                }
                ForEach(transactions) { item in
                    NavigationLink { TransactionEditor(item: item) } label: { TransactionRow(item: item) }
                }
            }
        }
        .listRowSpacing(theme.listRowSpacing)
        .navigationTitle(trip?.name ?? "Trip")
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button("Rename") { editingTrip = trip }.disabled(trip == nil)
        } }
        .sheet(item: $editingTrip) { trip in NavigationStack { TripEditorView(trip: trip) } }
    }

    private func categoryColor(_ category: TripCategoryAggregate) -> Color {
        category.categoryID.flatMap { id in store.ledgerCategories.first { $0.id == id } }
            .map { LedgerColor.color($0.colorName) } ?? .gray
    }

    private func percent(_ category: TripCategoryAggregate, total: Int64) -> String {
        guard total > 0 else { return "—" }
        let value = NSDecimalNumber(decimal: Decimal(category.personalNetEURMinor) * 100 / Decimal(total))
        let behavior = NSDecimalNumberHandler(roundingMode: .plain, scale: 1,
            raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false,
            raiseOnDivideByZero: false)
        return "\(value.rounding(accordingToBehavior: behavior))%"
    }
}

private struct AccountEditorView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.easyTrackTheme) private var theme
    let original: LocalAccount?
    @State private var name: String
    @State private var symbol: String
    @State private var color: String
    @State private var archived: Bool
    @State private var nativeCurrency: String
    @State private var errorMessage: String?
    @State private var saving = false

    init(account: LocalAccount? = nil) {
        original = account
        _name = State(initialValue: account?.name ?? "")
        _symbol = State(initialValue: account?.symbolName ?? "creditcard.fill")
        _color = State(initialValue: account?.colorName ?? "teal")
        _archived = State(initialValue: account?.archivedAt != nil)
        _nativeCurrency = State(initialValue: account?.nativeCurrency ?? "EUR")
    }

    var body: some View {
        Form {
            Section("Account") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("accountNameField")
                Picker("Native currency", selection: $nativeCurrency) {
                    ForEach(CurrencyMetadata.supportedCodes, id: \.self) { Text($0).tag($0) }
                }
                if let original, original.nativeCurrency != nativeCurrency {
                    Text("Currency can change only when this account has no recorded movements. Existing amounts are never relabeled or converted automatically.")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
            Section("Appearance") {
                HStack(spacing: 12) {
                    Image(systemName: symbol).font(.title2)
                        .foregroundStyle(LedgerColor.color(color))
                        .frame(width: 50, height: 50)
                        .background(LedgerColor.color(color).opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 15))
                        .accessibilityHidden(true)
                    Text(name.isEmpty ? "New account" : name).font(.headline).lineLimit(1)
                }
                Picker("Icon", selection: $symbol) {
                    ForEach(LedgerAppearance.symbols, id: \.self) { value in
                        Label(LedgerAppearance.symbolTitle(value), systemImage: value).tag(value)
                    }
                }
                .accessibilityIdentifier("accountIconPicker")
                .accessibilityValue(LedgerAppearance.symbolTitle(symbol))
                LedgerColorPalette(selection: $color)
                .accessibilityIdentifier("accountColorPicker")
                .accessibilityValue(color.capitalized)
            }
            if original != nil {
                Section("Availability") {
                    Toggle("Archived", isOn: $archived)
                    Text("Past transactions and notification sources keep this account’s stable identity.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .listRowSpacing(theme.listRowSpacing)
        .navigationTitle(original == nil ? "New account" : "Edit account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }.fontWeight(.semibold).disabled(saving)
                    .accessibilityIdentifier("saveAccountButton")
            }
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        var item = original ?? LocalAccount(id: UUID(), name: name, createdAt: .now)
        item.name = name
        item.symbolName = symbol
        item.colorName = color
        item.nativeCurrency = nativeCurrency
        item.archivedAt = archived ? (item.archivedAt ?? .now) : nil
        do {
            try store.saveAccount(item)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            saving = false
        }
    }
}

struct CategoriesView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.easyTrackTheme) private var theme
    @State private var selected: LedgerCategory?
    @State private var showingNew = false

    private var active: [LedgerCategory] { store.ledgerCategories.filter { $0.archivedAt == nil } }
    private var archived: [LedgerCategory] { store.ledgerCategories.filter { $0.archivedAt != nil } }

    var body: some View {
        List {
            Section("Categories") {
                ForEach(active) { category in categoryRow(category) }
            }
            if !archived.isEmpty {
                Section("Archived") { ForEach(archived) { category in categoryRow(category) } }
            }
            CategorySuggestionSections()
            Section {
                Text("Categories are optional. Archiving a category leaves past transactions untouched. Notification formats never assign one automatically.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .listRowSpacing(theme.listRowSpacing)
        .navigationTitle("Categories")
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { showingNew = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add category")
                .accessibilityIdentifier("addCategoryButton")
        } }
        .sheet(isPresented: $showingNew) { NavigationStack { CategoryEditorView() } }
        .sheet(item: $selected) { category in NavigationStack { CategoryEditorView(category: category) } }
    }

    private func categoryRow(_ category: LedgerCategory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.symbolName)
                .font(.headline).foregroundStyle(LedgerColor.color(category.colorName))
                .frame(width: 42, height: 42)
                .background(LedgerColor.color(category.colorName).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            Button { selected = category } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                    if category.archivedAt != nil { Text("Archived").font(.caption).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(category.archivedAt == nil ? category.name : "\(category.name), archived")
            .accessibilityHint("Edit category")
            .accessibilityIdentifier("categoryRow-\(category.name)")
            if category.archivedAt == nil {
                let position = active.firstIndex(where: { $0.id == category.id }) ?? 0
                Button { move(category, by: -1) } label: { Image(systemName: "arrow.up") }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(position == 0)
                    .accessibilityLabel("Move \(category.name) earlier")
                Button { move(category, by: 1) } label: { Image(systemName: "arrow.down") }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(position >= active.count - 1)
                    .accessibilityLabel("Move \(category.name) later")
            }
        }
        .buttonStyle(.borderless)
    }

    private func move(_ category: LedgerCategory, by offset: Int) {
        guard let position = active.firstIndex(where: { $0.id == category.id }),
              active.indices.contains(position + offset) else { return }
        do { try store.swapCategoryOrder(category, active[position + offset]) }
        catch { store.errorMessage = error.localizedDescription }
    }
}

private struct CategoryEditorView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.easyTrackTheme) private var theme
    let original: LedgerCategory?
    @State private var name: String
    @State private var symbol: String
    @State private var color: String
    @State private var archived: Bool
    @State private var errorMessage: String?
    @State private var saving = false

    init(category: LedgerCategory? = nil) {
        original = category
        _name = State(initialValue: category?.name ?? "")
        _symbol = State(initialValue: category?.symbolName ?? "square.grid.2x2.fill")
        _color = State(initialValue: category?.colorName ?? "teal")
        _archived = State(initialValue: category?.archivedAt != nil)
    }

    var body: some View {
        Form {
            Section("Category") {
                TextField("Name", text: $name).textInputAutocapitalization(.words)
                    .accessibilityIdentifier("categoryNameField")
            }
            Section("Appearance") {
                HStack {
                    Image(systemName: symbol).foregroundStyle(LedgerColor.color(color))
                        .frame(width: 44, height: 44)
                        .background(LedgerColor.color(color).opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                    Text(name.isEmpty ? "New category" : name).font(.headline)
                }
                Picker("Icon", selection: $symbol) {
                    ForEach(LedgerAppearance.symbols, id: \.self) { value in
                        Label(LedgerAppearance.symbolTitle(value), systemImage: value).tag(value)
                    }
                }
                .accessibilityIdentifier("categoryIconPicker")
                .accessibilityValue(LedgerAppearance.symbolTitle(symbol))
                LedgerColorPalette(selection: $color)
                .accessibilityIdentifier("categoryColorPicker")
                .accessibilityValue(color.capitalized)
            }
            if original != nil {
                Section("Availability") {
                    Toggle("Archived", isOn: $archived)
                    Text("Past transactions keep their category. You can restore it later.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .listRowSpacing(theme.listRowSpacing)
        .navigationTitle(original == nil ? "New category" : "Edit category")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }.fontWeight(.semibold).disabled(saving)
                    .accessibilityIdentifier("saveCategoryButton")
            }
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        let position = store.ledgerCategories.map(\.sortIndex).max().map { $0 + 1 } ?? 0
        var item = original ?? LedgerCategory(id: UUID(), name: name, symbolName: symbol,
                                              colorName: color, sortIndex: position,
                                              createdAt: .now, updatedAt: .now,
                                              archivedAt: nil, revision: 0)
        item.name = name
        item.symbolName = symbol
        item.colorName = color
        item.archivedAt = archived ? (item.archivedAt ?? .now) : nil
        do {
            try store.saveCategory(item)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            saving = false
        }
    }
}
