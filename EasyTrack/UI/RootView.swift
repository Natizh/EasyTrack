import SwiftUI
import UniformTypeIdentifiers

private enum Palette {
    static let ink = Color(red: 0.10, green: 0.17, blue: 0.20)
    static let teal = Color(red: 0.08, green: 0.45, blue: 0.43)
    static let mint = Color(red: 0.85, green: 0.95, blue: 0.91)
    static let canvas = Color(red: 0.96, green: 0.97, blue: 0.96)
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
    let item: Transaction

    private var displayedEURMinor: Int64? {
        item.eurMinor ?? (item.currency == "EUR" ? item.amountMinor : nil)
    }

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: item.kind.isOutflow ? "arrow.up.right" : "arrow.down.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(item.kind.isOutflow ? Palette.ink : Palette.teal)
                .frame(width: 42, height: 42)
                .background(item.kind.isOutflow ? Palette.canvas : Palette.mint, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.merchant).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                Text("\(item.kind.title) · \(item.category.isEmpty ? "Uncategorized" : item.category) · \(item.occurredAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text(displayedEURMinor.map { "\(item.kind.isOutflow ? "−" : "+")\(Money.format($0))" } ?? "EUR amount unavailable")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(item.kind.isOutflow ? Palette.ink : Palette.teal)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct HomeView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var showingNew = false

    private var totals: LedgerTotals { LedgerTotals(transactions: store.transactions) }
    private var uncategorized: [Transaction] {
        store.transactions.filter { !$0.isDemo && $0.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !store.hasHistoricalImport { DemoBanner(hasDemo: store.transactions.contains { $0.isDemo }) }
                VStack(alignment: .leading, spacing: 18) {
                    Text("ALL-TIME PERSONAL SPENDING · EUR").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.white.opacity(0.72))
                    Text(Money.format(totals.personalSpendingEURMinor))
                        .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        .minimumScaleFactor(0.7).lineLimit(1)
                        .accessibilityIdentifier("homePersonalSpendingTotal")
                    HStack(spacing: 22) {
                        metric("All expenses", value: totals.totalExpensesEURMinor, symbol: "arrow.up.right")
                        metric("Income", value: totals.incomeEURMinor, symbol: "arrow.down.left")
                    }
                    if totals.pacInvestedEURMinor > 0 { Text("PAC invested: \(Money.format(totals.pacInvestedEURMinor))").font(.caption).foregroundStyle(.white.opacity(0.75)) }
                }
                .foregroundStyle(.white)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Palette.ink, Palette.teal], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 26))

                if !uncategorized.isEmpty {
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
                        ForEach(uncategorized.prefix(3)) { item in
                            NavigationLink { TransactionEditor(item: item) } label: { TransactionRow(item: item) }
                                .buttonStyle(.plain)
                            if item.id != uncategorized.prefix(3).last?.id { Divider().padding(.leading, 55) }
                        }
                        if uncategorized.count > 3 {
                            NavigationLink("See all") { UncategorizedTransactionsView() }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.teal)
                                .padding(.top, 3)
                        }
                    }
                    .padding(17)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityIdentifier("homeUncategorizedSection")
                }

                HStack {
                    Text("Recent activity").font(.title3.bold()).foregroundStyle(Palette.ink)
                    Spacer()
                    Button { showingNew = true } label: { Label("Add", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).tint(Palette.teal)
                }
                VStack(spacing: 0) {
                    ForEach(store.transactions.prefix(4)) { item in
                        NavigationLink { TransactionEditor(item: item) } label: { TransactionRow(item: item) }
                            .buttonStyle(.plain)
                        if item.id != store.transactions.prefix(4).last?.id { Divider().padding(.leading, 55) }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(.white, in: RoundedRectangle(cornerRadius: 20))
                if store.transactions.isEmpty { ContentUnavailableView("No transactions", systemImage: "tray") }
            }
            .padding(20)
        }
        .background(Palette.canvas)
        .navigationTitle("EasyTrack")
        .sheet(isPresented: $showingNew) { NavigationStack { TransactionEditor() } }
    }

    private func metric(_ title: String, value: Int64, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.white.opacity(0.75))
            Text(Money.format(value)).font(.headline).monospacedDigit()
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
    @EnvironmentObject private var store: FinanceStore
    @State private var search = ""
    @State private var kind: TransactionKind?
    @State private var category = "All categories"
    @State private var accountFilter: String?
    @State private var tripFilter: String?
    @State private var currencyFilter: String?
    @State private var showingNew = false

    private var categories: [String] { ["All categories"] + Array(Set(store.transactions.map(\.category))).sorted() }
    private var accounts: [String] { Array(Set(store.transactions.map(\.account))).sorted() }
    private var currencies: [String] { Array(Set(store.transactions.map(\.currency))).sorted() }
    private var filtered: [Transaction] {
        TransactionFilter(query: search, kind: kind,
                          category: category == "All categories" ? nil : category,
                          account: accountFilter, tripID: tripFilter, currency: currencyFilter)
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
                    .accessibilityIdentifier("transactionSearchField")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
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
                            .background(.white, in: Capsule())
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
                        NavigationLink { TransactionEditor(item: item) } label: { TransactionRow(item: item) }
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
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingNew = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showingNew) { NavigationStack { TransactionEditor() } }
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.subheadline.weight(.medium)).padding(.horizontal, 15).padding(.vertical, 9) }
            .foregroundStyle(selected ? .white : Palette.ink)
            .background(selected ? Palette.teal : .white, in: Capsule())
    }

    private func filterMenuLabel(_ title: String) -> some View {
        Label(title, systemImage: "line.3.horizontal.decrease")
            .font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 9)
            .background(.white, in: Capsule())
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
    @State private var category: String
    @State private var subcategory: String
    @State private var tripID: String
    @State private var paidBy: String
    @State private var affectsMyAccounts: Bool
    @State private var note: String
    @State private var occurredAt: Date
    @State private var showDelete = false
    @State private var isSaving = false
    @State private var validation: String?

    init(item: Transaction? = nil, prefillEvent: NotificationEvent? = nil) {
        original = item
        sourceEventID = item?.sourceEventID ?? prefillEvent?.id
        _kind = State(initialValue: item?.kind ?? .expense)
        let editableEUR = item.flatMap { $0.currency == "EUR" ? $0.amountMinor : $0.eurMinor }
        _amount = State(initialValue: editableEUR.map { Money.editString($0) } ?? "")
        _merchant = State(initialValue: item?.merchant ?? "")
        _account = State(initialValue: item?.account ?? "")
        _category = State(initialValue: item?.category ?? "")
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
                LabeledContent("Description") {
                    TextField("Required", text: $merchant)
                        .multilineTextAlignment(.trailing)
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
                    TextField("Account", text: $account).multilineTextAlignment(.trailing)
                }
                LabeledContent("Category") {
                    HStack {
                        TextField("Uncategorized", text: $category).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("transactionCategoryField")
                        let categories = Array(Set(store.transactions.map(\.category).filter { !$0.isEmpty })).sorted()
                        if !categories.isEmpty {
                            Menu {
                                ForEach(categories, id: \.self) { value in Button(value) { category = value } }
                            } label: { Image(systemName: "chevron.down.circle").foregroundStyle(Palette.teal) }
                                .accessibilityLabel("Choose existing category")
                        }
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
        .onChange(of: amount) { _, _ in validation = nil }
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
        if original == nil && account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validation = "Enter an account for a new transaction."; return
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
        item.account = account.trimmingCharacters(in: .whitespacesAndNewlines)
        item.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
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

private struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(_ envelope: BackupEnvelope) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        data = try encoder.encode(envelope)
    }

    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct SettingsView: View {
    @EnvironmentObject private var store: FinanceStore
    private enum PickerPurpose { case seed, folder }
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

    var body: some View {
        Form {
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
                Text("Keep this file private. It includes imported history and source rows. Backup restore is planned for a later milestone.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("Version", value: "0.4 · notification formats")
                LabeledContent("Currency in editor", value: "EUR")
            }
        }
        .navigationTitle("Settings")
        .task { folderSelected = await FolderProbe.shared.hasSavedFolder(); if folderSelected { probeStatus = "Folder bookmark saved" } }
        .sheet(isPresented: $showingFilePicker) {
            SystemDocumentPicker(contentTypes: pickerPurpose == .folder ? [.folder] : [.data]) { url in
                showingFilePicker = false
                if pickerPurpose == .seed { selectedSeedFile = url }
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
