import SwiftUI

struct UpcomingRecurringRow: View {
    @EnvironmentObject private var store: FinanceStore
    let item: UpcomingRecurringItem

    private var accountName: String {
        store.localAccounts.first(where: { $0.id == item.rule.accountID })?.name ?? "Account unavailable"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.rule.type.symbolName)
                .font(.headline)
                .foregroundStyle(item.rule.type == .income ? .green : .teal)
                .frame(width: 42, height: 42)
                .background((item.rule.type == .income ? Color.green : Color.teal).opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.rule.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(item.rule.type.title) · \(accountName)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(displayDate).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 5)
            Text(Money.format(item.rule.amountMinor)).font(.subheadline.weight(.semibold))
                .monospacedDigit().lineLimit(1)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.rule.name), \(item.rule.type.title), \(Money.format(item.rule.amountMinor)), \(accountName), expected \(displayDate)")
    }

    private var displayDate: String {
        let zone = TimeZone(identifier: item.rule.timeZoneIdentifier) ?? .current
        return item.day.noon(in: zone)?.formatted(date: .abbreviated, time: .omitted) ?? item.day.isoString
    }
}

struct RecurringListView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var showingNew = false
    @State private var selected: RecurringRule?
    @State private var adopting: HistoricalRecurringRule?
    @State private var toArchive: RecurringRule?
    @State private var toSkip: RecurringRule?
    @State private var confirmationMessage: String?

    private var active: [RecurringRule] { store.recurringRules.filter(\.isActive) }
    private var paused: [RecurringRule] { store.recurringRules.filter { !$0.isActive } }
    private var upcoming: [UpcomingRecurringItem] { store.upcomingRecurring() }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Plan what comes next").font(.title2.bold())
                    Text("Rules are templates. Upcoming dates do not enter your totals until a transaction is created.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                sectionHeader("Next 30 days", systemImage: "calendar")
                if upcoming.isEmpty { emptyCard("No payments expected in the next 30 days.") }
                ForEach(upcoming.prefix(2)) { item in
                    UpcomingRecurringRow(item: item)
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 16))
                }
                if upcoming.count > 2 {
                    Text("\(upcoming.count - 2) more dates in the next 30 days")
                        .font(.caption).foregroundStyle(.secondary)
                }
                sectionHeader("Active rules", systemImage: "repeat")
                if active.isEmpty { emptyCard("Add a subscription, repeating payment, income, or PAC plan.") }
                ForEach(active) { rule in
                    ruleCard(rule).id("\(rule.id.uuidString)-\(rule.revision)-\(rule.isActive)")
                }
                if !paused.isEmpty {
                    sectionHeader("Paused", systemImage: "pause.circle")
                    ForEach(paused) { rule in
                        ruleCard(rule).id("\(rule.id.uuidString)-\(rule.revision)-\(rule.isActive)")
                    }
                }
                if !store.historicalRules.isEmpty {
                    sectionHeader("Imported plans", systemImage: "tray.full")
                    Text("Historical definitions stay separate. Choose one to start a new local rule from a date you confirm.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(store.historicalRules) { sourceRule in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(sourceRule.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(sourceRule.currency == "EUR" ? "Ready to set up" : "EUR-only setup")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Set up") { adopting = sourceRule }
                                .buttonStyle(.bordered)
                                .disabled(sourceRule.currency != "EUR" ||
                                          store.recurringRules.contains { $0.historicalSourceID == sourceRule.id })
                        }
                        .padding(14)
                        .background(Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Recurring")
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { showingNew = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add recurring rule")
                .accessibilityIdentifier("addRecurringRuleButton")
        } }
        .sheet(isPresented: $showingNew) { NavigationStack { RecurringRuleEditorView() } }
        .sheet(item: $selected) { rule in NavigationStack { RecurringRuleEditorView(rule: rule) } }
        .sheet(item: $adopting) { source in NavigationStack { RecurringRuleEditorView(imported: source) } }
        .confirmationDialog("Skip this occurrence?", isPresented: Binding(
            get: { toSkip != nil }, set: { if !$0 { toSkip = nil } }), titleVisibility: .visible) {
                Button("Skip once") {
                    guard let rule = toSkip else { return }
                    do { try store.skipNextRecurring(rule.id) }
                    catch { store.errorMessage = error.localizedDescription }
                    toSkip = nil
                }
            } message: { Text("The rule will continue on its following date.") }
        .confirmationDialog("Archive this rule?", isPresented: Binding(
            get: { toArchive != nil }, set: { if !$0 { toArchive = nil } }), titleVisibility: .visible) {
                Button("Archive rule", role: .destructive) {
                    guard var rule = toArchive else { return }
                    rule.archivedAt = .now
                    rule.isActive = false
                    do { try store.saveRecurringRule(rule) }
                    catch { store.errorMessage = error.localizedDescription }
                    toArchive = nil
                }
            } message: { Text("Transactions already created by this rule will remain in Activity.") }
        .alert("Recurring payment", isPresented: Binding(
            get: { confirmationMessage != nil }, set: { if !$0 { confirmationMessage = nil } })) {
                Button("OK") { confirmationMessage = nil }
            } message: { Text(confirmationMessage ?? "") }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage).font(.title3.bold())
    }

    private func emptyCard(_ message: String) -> some View {
        Text(message).font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 17))
    }

    private func ruleCard(_ rule: RecurringRule) -> some View {
        let next = (try? RecurringSchedule.nextDay(for: rule)) ?? nil
        let account = store.localAccounts.first(where: { $0.id == rule.accountID })?.name ?? "Account unavailable"
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: rule.type.symbolName).font(.title3).foregroundStyle(.teal)
                    .frame(width: 42, height: 42)
                    .background(Color.teal.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(rule.name).font(.headline).lineLimit(1)
                    Text("\(rule.type.title) · \(rule.frequency.title)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Money.format(rule.amountMinor)).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            Text("\(account) · \(next.map { expectedDate($0, for: rule) } ?? "Schedule complete")")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Edit") { selected = rule }.accessibilityLabel("Edit \(rule.name)")
                Spacer()
                if rule.isActive && next != nil {
                    Button("Create now") {
                        do {
                            let transaction = try store.createNextRecurringNow(rule.id)
                            confirmationMessage = "\(Money.format(transaction.amountMinor)) added to Activity."
                        } catch { store.errorMessage = error.localizedDescription }
                    }
                    Button("Skip") { toSkip = rule }
                } else if !rule.isActive {
                    Button("Resume") {
                        var updated = rule; updated.isActive = true
                        do { try store.saveRecurringRule(updated) }
                        catch { store.errorMessage = error.localizedDescription }
                    }
                }
                Menu {
                    if rule.isActive {
                        Button("Pause", systemImage: "pause") {
                            var updated = rule; updated.isActive = false
                            do { try store.saveRecurringRule(updated) }
                            catch { store.errorMessage = error.localizedDescription }
                        }
                    }
                    Button("Archive", systemImage: "archivebox", role: .destructive) { toArchive = rule }
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("More options for \(rule.name)")
            }
            .font(.subheadline.weight(.medium))
            .buttonStyle(.borderless)
            .tint(.teal)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 19))
    }

    private func expectedDate(_ day: LocalDay, for rule: RecurringRule) -> String {
        let zone = TimeZone(identifier: rule.timeZoneIdentifier) ?? .current
        return day.noon(in: zone)?.formatted(date: .abbreviated, time: .omitted) ?? day.isoString
    }
}

private struct RecurringRuleEditorView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let original: RecurringRule?
    let imported: HistoricalRecurringRule?
    @State private var name: String
    @State private var amount: String
    @State private var type: RecurringType
    @State private var frequency: RecurringFrequency
    @State private var accountID: UUID?
    @State private var categoryID: UUID?
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var hasEndDate: Bool
    @State private var isActive: Bool
    @State private var note: String
    @State private var errorMessage: String?
    @State private var saving = false
    @State private var choosingType = false
    @State private var choosingAccount = false
    @State private var choosingCategory = false
    @State private var choosingFrequency = false

    init(rule: RecurringRule? = nil, imported: HistoricalRecurringRule? = nil) {
        original = rule
        self.imported = imported
        _name = State(initialValue: rule?.name ?? imported?.name ?? "")
        _amount = State(initialValue: rule.map { Money.editString($0.amountMinor) } ??
                        imported.map { Money.editString($0.amountMinor) } ?? "")
        _type = State(initialValue: rule?.type ?? (imported?.ruleKind == "investment" ? .pacInvestment : .subscription))
        _frequency = State(initialValue: rule?.frequency ?? .monthly)
        _accountID = State(initialValue: rule?.accountID)
        _categoryID = State(initialValue: rule?.categoryID)
        _startDate = State(initialValue: rule?.startDay.noon(in: .current) ?? .now)
        _endDate = State(initialValue: rule?.endDay?.noon(in: .current) ?? .now)
        _hasEndDate = State(initialValue: rule?.endDay != nil)
        _isActive = State(initialValue: rule?.isActive ?? true)
        _note = State(initialValue: rule?.note ?? "")
    }

    var body: some View {
        Form {
            Section("Payment") {
                TextField("Name or merchant", text: $name)
                    .accessibilityIdentifier("recurringNameField")
                LabeledContent("Kind") {
                    Button(type.title) { choosingType = true }
                        .accessibilityIdentifier("recurringTypePicker")
                }
                LabeledContent("Amount (EUR)") {
                    TextField("0,00", text: $amount).keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("recurringAmountField")
                }
                LabeledContent("Account") {
                    Button(store.localAccounts.first(where: { $0.id == accountID })?.name ?? "Choose account") {
                        choosingAccount = true
                    }
                    .accessibilityIdentifier("recurringAccountPicker")
                }
                LabeledContent("Category") {
                    Button(store.ledgerCategories.first(where: { $0.id == categoryID })?.name ?? "Uncategorized") {
                        choosingCategory = true
                    }
                    .accessibilityIdentifier("recurringCategoryPicker")
                }
            }
            Section("Schedule") {
                LabeledContent("Repeats") {
                    Button(frequency.title) { choosingFrequency = true }
                        .accessibilityIdentifier("recurringFrequencyPicker")
                }
                DatePicker("Schedule starts",
                           selection: $startDate, displayedComponents: .date)
                Toggle("End on a date", isOn: $hasEndDate)
                if hasEndDate { DatePicker("Ends", selection: $endDate, displayedComponents: .date) }
                Toggle("Active", isOn: $isActive)
                if original == nil {
                    Text("If the start date is in the past, missed payments are added once when you save.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Changes apply only to future occurrences. Past transactions keep their original values.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Note") {
                TextField("Optional note", text: $note, axis: .vertical).lineLimit(2...5)
            }
            if let imported {
                Section {
                    Text("Based on an imported \(imported.ruleKind == "investment" ? "investment plan" : "subscription") definition. Its historical data stays unchanged.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle(original == nil ? "New repeating payment" : "Edit repeating payment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }.fontWeight(.semibold).disabled(saving)
                    .accessibilityIdentifier("saveRecurringRuleButton")
            }
        }
        .sheet(isPresented: $choosingType) {
            NavigationStack {
                List(RecurringType.allCases) { option in
                    Button(option.title) { type = option; choosingType = false }
                }
                .navigationTitle("Movement kind")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { choosingType = false } } }
            }
        }
        .sheet(isPresented: $choosingAccount) {
            NavigationStack { AccountSelectionView(selectedID: accountID) { accountID = $0.id } }
        }
        .sheet(isPresented: $choosingCategory) {
            NavigationStack { CategorySelectionView(selectedID: categoryID) { categoryID = $0?.id } }
        }
        .sheet(isPresented: $choosingFrequency) {
            NavigationStack {
                List(RecurringFrequency.allCases) { option in
                    Button(option.title) { frequency = option; choosingFrequency = false }
                }
                .navigationTitle("Repeat")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { choosingFrequency = false } } }
            }
        }
    }

    private func save() {
        guard !saving else { return }
        errorMessage = nil
        let cents: Int64
        switch Money.validatedPositiveAmount(amount) {
        case .success(let value): cents = value
        case .failure(let error): errorMessage = error.message; return
        }
        guard let accountID else { errorMessage = "Choose an account."; return }
        saving = true
        let currentZone = TimeZone.current
        let start = LocalDay(date: startDate, timeZone: currentZone)
        let end = hasEndDate ? LocalDay(date: endDate, timeZone: currentZone) : nil
        var item = original ?? RecurringRule(id: UUID(), name: name, type: type,
            amountMinor: cents, accountID: accountID, categoryID: categoryID,
            startDay: start, frequency: frequency, nextIndex: 0, endDay: end,
            timeZoneIdentifier: currentZone.identifier, isActive: isActive, note: note,
            createdAt: .now, updatedAt: .now, archivedAt: nil, revision: 0)
        item.name = name
        item.type = type
        item.amountMinor = cents
        item.accountID = accountID
        item.categoryID = categoryID
        item.startDay = start
        item.frequency = frequency
        item.endDay = end
        item.isActive = isActive
        item.note = note
        if let imported { item.historicalSourceID = imported.id }
        do {
            try store.saveRecurringRule(item)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            saving = false
        }
    }
}
