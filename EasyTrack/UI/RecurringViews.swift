import SwiftUI

private func recurringLinkEffect(actual: Transaction, replacing old: Transaction?) -> String {
    guard let old, old.id != actual.id else {
        return AppLanguage.localized("The existing transaction stays counted; linking changes no totals.")
    }
    let removed = LedgerTotals(transactions: [old])
    return AppLanguage.formatted("The existing actual transaction stays counted. The old estimate is removed: personal spending −%@, expenses −%@, income −%@, PAC −%@.",
        Money.format(removed.personalSpendingEURMinor), Money.format(removed.totalExpensesEURMinor),
        Money.format(removed.incomeEURMinor), Money.format(removed.pacInvestedEURMinor))
}

struct UpcomingRecurringRow: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.easyTrackTheme) private var theme
    let item: UpcomingRecurringItem

    private var accountName: String {
        store.localAccounts.first(where: { $0.id == item.rule.accountID })?.name ?? "Account unavailable"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.rule.type.symbolName)
                .font(.headline)
                .foregroundStyle(item.rule.type == .income ? .green : theme.accent)
                .frame(width: 42, height: 42)
                .background((item.rule.type == .income ? Color.green : theme.accent).opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.rule.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(item.rule.type == .pacInvestment ? AppLanguage.localized("Planned PAC investment") : AppLanguage.localized(item.rule.type.title)) · \(accountName)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(displayDate).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 5)
            Text(Money.format(item.rule.amountMinor)).font(.subheadline.weight(.semibold))
                .monospacedDigit().lineLimit(1)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.rule.name), \(AppLanguage.localized(item.rule.type.title)), \(Money.format(item.rule.amountMinor)), \(accountName), expected \(displayDate)")
    }

    private var displayDate: String {
        let zone = TimeZone(identifier: item.rule.timeZoneIdentifier) ?? .current
        return item.day.noon(in: zone)?.easyTrackFormatted(date: .abbreviated, time: .omitted) ?? item.day.isoString
    }
}

struct RecurringListView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.easyTrackTheme) private var theme
    @State private var showingNew = false
    @State private var selected: RecurringRule?
    @State private var adopting: HistoricalRecurringRule?
    @State private var toArchive: RecurringRule?
    @State private var toSkip: RecurringRule?
    @State private var toRecord: RecurringRule?
    @State private var confirmationMessage: String?

    private var active: [RecurringRule] { store.recurringRules.filter { $0.isActive && $0.archivedAt == nil } }
    private var paused: [RecurringRule] { store.recurringRules.filter { !$0.isActive && $0.archivedAt == nil } }
    private var archived: [RecurringRule] { store.recurringRules.filter { $0.archivedAt != nil } }
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
                let pending = store.recurringCandidates.filter { $0.status == .pending }
                if !pending.isEmpty {
                    sectionHeader("\(AppLanguage.localized("Needs review")) · \(pending.count)", systemImage: "exclamationmark.circle")
                    ForEach(Array(Set(pending.map(\.occurrenceID))).sorted(), id: \.self) { id in
                        if let occurrence = store.recurringOccurrences.first(where: { $0.id == id }),
                           let rule = store.recurringRules.first(where: { $0.id == occurrence.ruleID }) {
                            NavigationLink { RecurringOccurrenceDetailView(occurrenceID: id) } label: {
                                Label("\(rule.name) · \(occurrence.scheduledDay.localizedString)",
                                      systemImage: "arrow.right.circle")
                            }
                            .padding(13)
                            .background(Color(uiColor: .secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
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
                if !archived.isEmpty {
                    sectionHeader("Archived history", systemImage: "archivebox")
                    ForEach(archived) { rule in
                        NavigationLink { RecurringRuleDetailView(ruleID: rule.id) } label: {
                            Label(rule.name, systemImage: "clock.arrow.circlepath")
                        }
                        .padding(13)
                        .background(Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 14))
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
        .confirmationDialog("Record this payment manually?", isPresented: Binding(
            get: { toRecord != nil }, set: { if !$0 { toRecord = nil } }), titleVisibility: .visible) {
                Button("Record paid manually") {
                    guard let rule = toRecord else { return }
                    do {
                        let transaction = try store.createNextRecurringNow(rule.id)
                        confirmationMessage = AppLanguage.formatted("%@ added to Activity.",
                            Money.format(transaction.amountMinor))
                    } catch { store.errorMessage = error.localizedDescription }
                    toRecord = nil
                }
            } message: { Text("This creates one counted transaction. Use it only when the payment happened and no bank movement was captured.") }
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
            } message: { Text(AppLanguage.localized(confirmationMessage ?? "")) }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(AppLanguage.localized(title), systemImage: systemImage).font(.title3.bold())
    }

    private func emptyCard(_ message: String) -> some View {
        Text(AppLanguage.localized(message)).font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 17))
    }

    private func ruleCard(_ rule: RecurringRule) -> some View {
        let next = (try? RecurringSchedule.nextDay(for: rule)) ?? nil
        let account = store.localAccounts.first(where: { $0.id == rule.accountID })?.name ?? "Account unavailable"
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: rule.type.symbolName).font(.title3).foregroundStyle(theme.accent)
                    .frame(width: 42, height: 42)
                    .background(theme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(rule.name).font(.headline).lineLimit(1)
                    Text("\(AppLanguage.localized(rule.type.title)) · \(AppLanguage.localized(rule.frequency.title))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Money.format(rule.amountMinor)).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            Text("\(account) · \(next.map { expectedDate($0, for: rule) } ?? "Schedule complete")")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Edit") { selected = rule }.accessibilityLabel("Edit \(rule.name)")
                NavigationLink("History") { RecurringRuleDetailView(ruleID: rule.id) }
                    .accessibilityLabel("Occurrence history for \(rule.name)")
                Spacer()
                if rule.isActive && next != nil {
                    Button("Record paid manually") { toRecord = rule }
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
            .tint(theme.accent)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 19))
    }

    private func expectedDate(_ day: LocalDay, for rule: RecurringRule) -> String {
        let zone = TimeZone(identifier: rule.timeZoneIdentifier) ?? .current
        return day.noon(in: zone)?.easyTrackFormatted(date: .abbreviated, time: .omitted) ?? day.isoString
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
    @State private var reviewWindowDays: Int

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
        _reviewWindowDays = State(initialValue: rule?.reviewWindowDays ?? 3)
    }

    var body: some View {
        Form {
            Section("Payment") {
                TextField("Name or merchant", text: $name)
                    .accessibilityIdentifier("recurringNameField")
                LabeledContent("Kind") {
                    Button(AppLanguage.localized(type.title)) { choosingType = true }
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
                    Button(AppLanguage.localized(frequency.title)) { choosingFrequency = true }
                        .accessibilityIdentifier("recurringFrequencyPicker")
                }
                DatePicker("Schedule starts",
                           selection: $startDate, displayedComponents: .date)
                Toggle("End on a date", isOn: $hasEndDate)
                if hasEndDate { DatePicker("Ends", selection: $endDate, displayedComponents: .date) }
                Toggle("Active", isOn: $isActive)
                Stepper("Review window: ±\(reviewWindowDays) days", value: $reviewWindowDays, in: 0...14)
                    .accessibilityIdentifier("recurringReviewWindowStepper")
                if original == nil {
                    Text("Past dates become expected entries. They do not change totals until a real payment is linked or recorded manually.")
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
            if let errorMessage { Section { Text(AppLanguage.localized(errorMessage)).foregroundStyle(.red) } }
        }
        .navigationTitle(AppLanguage.localized(original == nil ? "New repeating payment" : "Edit repeating payment"))
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
                    Button(AppLanguage.localized(option.title)) { type = option; choosingType = false }
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
                    Button(AppLanguage.localized(option.title)) { frequency = option; choosingFrequency = false }
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
        item.reviewWindowDays = reviewWindowDays
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

struct RecurringRuleDetailView: View {
    @EnvironmentObject private var store: FinanceStore
    let ruleID: UUID

    private var rule: RecurringRule? { store.recurringRules.first { $0.id == ruleID } }
    private var occurrences: [RecurringOccurrence] {
        store.recurringOccurrences.filter { $0.ruleID == ruleID }
            .sorted { $0.scheduledDay > $1.scheduledDay }
    }

    var body: some View {
        List {
            if let rule {
                Section("Rule") {
                    LabeledContent("Payment", value: rule.name)
                    LabeledContent("Expected amount", value: Money.format(rule.amountMinor))
                    LabeledContent("Review window", value: "±\(rule.reviewWindowDays) local days")
                    Text("Expected dates do not enter your totals. A paid transaction appears in Activity.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Occurrence history") {
                if occurrences.isEmpty { Text("No due dates recorded yet.").foregroundStyle(.secondary) }
                ForEach(occurrences) { occurrence in
                    NavigationLink { RecurringOccurrenceDetailView(occurrenceID: occurrence.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(occurrence.scheduledDay.localizedString).font(.headline)
                            Text(AppLanguage.localized(occurrence.status.title))
                                .font(.subheadline).foregroundStyle(.secondary)
                            if store.recurringCandidates.contains(where: { $0.occurrenceID == occurrence.id && $0.status == .pending }) {
                                Label("Needs review", systemImage: "exclamationmark.circle")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                    .accessibilityLabel("\(occurrence.scheduledDay.localizedString), \(AppLanguage.localized(occurrence.status.title)), \(store.recurringCandidates.contains(where: { $0.occurrenceID == occurrence.id && $0.status == .pending }) ? AppLanguage.localized("needs review") : AppLanguage.localized("no review needed"))")
                    .accessibilityIdentifier("recurringOccurrence-\(occurrence.id)")
                }
            }
        }
        .navigationTitle(rule?.name ?? "Recurring payment")
    }
}

struct RecurringOccurrenceDetailView: View {
    @EnvironmentObject private var store: FinanceStore
    let occurrenceID: String
    @State private var pendingAction: Action?
    @State private var resultMessage: String?

    private enum Action {
        case record, skip, missed, countedMissed, unlink
        case confirm(UUID), reject(UUID), separate(UUID), approve(UUID)
    }

    private var occurrence: RecurringOccurrence? {
        store.recurringOccurrences.first { $0.id == occurrenceID }
    }
    private var rule: RecurringRule? {
        store.recurringRules.first { $0.id == occurrence?.ruleID }
    }
    private var candidates: [RecurringCandidate] {
        store.recurringCandidates.filter { $0.occurrenceID == occurrenceID && $0.status == .pending }
    }
    private var actual: Transaction? {
        store.transactions.first { $0.id == occurrence?.transactionID }
    }

    var body: some View {
        List {
            if let occurrence, let rule {
                Section("Scheduled payment") {
                    LabeledContent("Rule", value: rule.name)
                    LabeledContent("Kind", value: AppLanguage.localized(rule.type.title))
                    LabeledContent("Account", value: store.localAccounts.first(where: {
                        $0.id == rule.accountID
                    })?.name ?? "Account unavailable")
                    LabeledContent("Scheduled", value: occurrence.scheduledDay.localizedString)
                    LabeledContent("Expected", value: Money.format(rule.amountMinor))
                    LabeledContent("Status", value: AppLanguage.localized(occurrence.status.title))
                    if occurrence.status == .expected,
                       occurrence.scheduledDay < LocalDay(date: .now,
                           timeZone: TimeZone(identifier: rule.timeZoneIdentifier) ?? .current) {
                        Label("Overdue · not marked missed", systemImage: "clock")
                            .foregroundStyle(.orange)
                    }
                    if let reason = occurrence.reviewReason { Text(reason).font(.footnote) }
                }
                if let actual {
                    Section("Counted transaction") {
                        NavigationLink { TransactionEditor(item: actual) } label: {
                            LabeledContent(actual.merchant, value: Money.format(actual.eurMinor ?? actual.amountMinor))
                        }
                        Text("Linking does not add a second movement. This Activity record holds the actual amount and source details.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if !candidates.isEmpty {
                    Section("Needs review") {
                        ForEach(candidates) { candidate in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(candidate.reason).font(.subheadline)
                                if let transaction = store.transactions.first(where: { $0.id == candidate.transactionID }) {
                                    Text("Actual: \(transaction.merchant) · \(Money.format(transaction.eurMinor ?? transaction.amountMinor)) · \(transaction.occurredAt.easyTrackFormatted(date: .abbreviated, time: .omitted))")
                                        .font(.footnote)
                                    NavigationLink("Open actual transaction") { TransactionEditor(item: transaction) }
                                } else if let attempt = store.parserAttempts.first(where: { $0.event.id == candidate.eventID }) {
                                    Text("Captured: \(attempt.event.title) · \((attempt.event.receivedAt ?? attempt.event.capturedAt).easyTrackFormatted(date: .abbreviated, time: .omitted))")
                                        .font(.footnote)
                                    if let extracted = candidateCapture(candidate),
                                       let amount = extracted.amount, let merchant = extracted.merchant {
                                        Text("Actual: \(merchant) · \(Money.format(amount.cents)) · \(extracted.occurredAt.easyTrackFormatted(date: .abbreviated, time: .omitted))")
                                            .font(.footnote)
                                    }
                                }
                                HStack {
                                    Button("Confirm payment") { pendingAction = .confirm(candidate.id) }
                                        .disabled(candidate.transactionID == nil && candidateCapture(candidate) == nil)
                                    if let eventID = candidate.eventID {
                                        Button("Separate payment") { pendingAction = .separate(eventID) }
                                    } else {
                                        Button("Reject suggestion") { pendingAction = .reject(candidate.id) }
                                    }
                                }
                                .buttonStyle(.bordered)
                                if candidatePayee(candidate) != nil {
                                    Button("Approve payee for future exact matches") { pendingAction = .approve(candidate.id) }
                                        .font(.footnote)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                }
                Section("Actions") {
                    if occurrence.status == .expected {
                        Button("Record paid manually") { pendingAction = .record }
                            .accessibilityIdentifier("recordExpectedRecurringButton")
                        Button("Skip this payment") { pendingAction = .skip }
                        if occurrence.scheduledDay < LocalDay(date: .now,
                            timeZone: TimeZone(identifier: rule.timeZoneIdentifier) ?? .current) {
                            Button("Mark missed") { pendingAction = .missed }
                        }
                    }
                    if occurrence.status == .legacyCounted || occurrence.status == .recordedManual {
                        Button("Mark missed and remove counted payment", role: .destructive) {
                            pendingAction = .countedMissed
                        }
                    }
                    if occurrence.status == .confirmed {
                        Button("Unlink actual transaction") { pendingAction = .unlink }
                    }
                    if occurrence.status == .expected || occurrence.status == .skipped ||
                        occurrence.status == .missed || occurrence.status == .legacyCounted ||
                        occurrence.status == .recordedManual {
                        NavigationLink("Choose an existing transaction") {
                            RecurringManualLinkView(occurrenceID: occurrenceID)
                        }
                    }
                }
            } else {
                ContentUnavailableView("Occurrence unavailable", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .navigationTitle("Recurring occurrence")
        .confirmationDialog(AppLanguage.localized(actionTitle), isPresented: Binding(
            get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
            titleVisibility: .visible) {
                Button(AppLanguage.localized(confirmationButtonTitle), role: isDestructive ? .destructive : nil) { performAction() }
                Button("Cancel", role: .cancel) { pendingAction = nil }
            } message: { Text(AppLanguage.localized(actionExplanation)) }
        .alert("Recurring payment", isPresented: Binding(
            get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
                Button("OK") { resultMessage = nil }
            } message: { Text(AppLanguage.localized(resultMessage ?? "")) }
    }

    private func candidatePayee(_ candidate: RecurringCandidate) -> String? {
        if let transaction = store.transactions.first(where: { $0.id == candidate.transactionID }) {
            return transaction.merchant
        }
        return candidateCapture(candidate)?.merchant
    }

    private func candidateCapture(_ candidate: RecurringCandidate) -> ParserPreview? {
        guard let attempt = store.parserAttempts.first(where: { $0.event.id == candidate.eventID }),
              let ruleID = attempt.ruleID, let version = attempt.ruleVersion,
              let source = store.parserSources.first(where: { $0.id == attempt.sourceID }),
              let database = try? SQLiteDatabase.openReadOnly(),
              let revision = try? database.parserRuleHistory(ruleID).first(where: {
                  $0.version == version
              }) else { return nil }
        let preview = NotificationParser.preview(attempt.event, config: revision.config,
                                                 mappedAccount: source.accountName)
        return preview.ready ? preview : nil
    }

    private var actionTitle: String {
        switch pendingAction {
        case .record: "Record paid manually"
        case .skip: "Skip payment"
        case .missed, .countedMissed: "Mark missed"
        case .unlink: "Unlink transaction"
        case .confirm: "Confirm this payment"
        case .reject: "Reject suggestion"
        case .separate: "Treat as separate payment"
        case .approve: "Approve payee"
        case nil: "Confirm"
        }
    }

    private var isDestructive: Bool {
        if case .countedMissed = pendingAction { return true }
        return false
    }

    private var confirmationButtonTitle: String {
        if case .record = pendingAction { return "Confirm manual recording" }
        if case .missed = pendingAction { return "Confirm missed" }
        if case .countedMissed = pendingAction { return "Remove counted payment and mark missed" }
        return actionTitle
    }

    private var actionExplanation: String {
        switch pendingAction {
        case .record: return "Creates one counted transaction now. Use only if the payment happened."
        case .skip, .missed: return "No transaction will be created and totals stay unchanged."
        case .countedMissed:
            let value = actual.map { Money.format($0.eurMinor ?? $0.amountMinor) } ?? AppLanguage.localized("the recorded amount")
            return AppLanguage.formatted("The old estimate (%@) will be soft-deleted and removed from totals. Its identity and audit history remain.", value)
        case .unlink: return "The actual transaction remains counted with its source details. The occurrence becomes expected again; no old estimate is recreated."
        case .confirm(let id):
            if let candidate = candidates.first(where: { $0.id == id }),
               let transaction = store.transactions.first(where: { $0.id == candidate.transactionID }),
               let old = actual, old.id != transaction.id {
                return recurringLinkEffect(actual: transaction, replacing: old)
            }
            if let candidate = candidates.first(where: { $0.id == id }),
               let extracted = candidateCapture(candidate), let amount = extracted.amount,
               let old = actual {
                return AppLanguage.formatted("The recorded estimate %@ will be corrected to the captured amount %@. Review the date and payee before confirming; the transaction UUID and user note remain.",
                    Money.format(old.eurMinor ?? old.amountMinor), Money.format(amount.cents))
            }
            return "Confirm the captured payment against this occurrence. Any changed bank amount replaces the old estimate; source identity and user notes are preserved."
        case .reject, .separate: return "The payments remain separate. A held notification can then create its own transaction."
        case .approve: return "Only future unique, exact-cent payments from this payee can be confirmed automatically."
        case nil: return ""
        }
    }

    private func performAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        do {
            switch action {
            case .record: _ = try store.recordExpectedRecurringNow(occurrenceID)
            case .skip: try store.changeExpectedOccurrence(occurrenceID, to: .skipped)
            case .missed: try store.changeExpectedOccurrence(occurrenceID, to: .missed)
            case .countedMissed: try store.markCountedOccurrenceMissed(occurrenceID)
            case .unlink:
                try store.unlinkRecurringTransaction(occurrenceID,
                    occurrenceRevision: occurrence?.revision,
                    transactionRevision: actual?.revision)
            case .confirm(let id):
                guard let candidate = candidates.first(where: { $0.id == id }),
                      let occurrence, let rule else { throw RecurringError.occurrenceChanged }
                let transactionRevision = store.transactions.first(where: {
                    $0.id == candidate.transactionID
                })?.revision
                try store.confirmRecurringCandidate(id,
                    candidateRevision: candidate.revision,
                    occurrenceRevision: occurrence.revision,
                    ruleRevision: rule.revision,
                    transactionRevision: transactionRevision)
            case .reject(let id): try store.rejectRecurringCandidate(id)
            case .separate(let eventID): try store.separateRecurringEvent(eventID)
            case .approve(let id):
                guard let candidate = candidates.first(where: { $0.id == id }),
                      let payee = candidatePayee(candidate), let rule else {
                    throw RecurringError.occurrenceChanged
                }
                try store.approveRecurringPayee(payee, for: rule.id)
            }
        } catch { resultMessage = error.localizedDescription }
    }
}

struct RecurringManualLinkView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let occurrenceID: String
    @State private var selected: Transaction?
    @State private var errorMessage: String?

    private var occurrence: RecurringOccurrence? {
        store.recurringOccurrences.first { $0.id == occurrenceID }
    }
    private var rule: RecurringRule? { store.recurringRules.first { $0.id == occurrence?.ruleID } }
    private var eligible: [Transaction] {
        guard let rule else { return [] }
        return store.transactions.filter { !$0.isDemo && $0.kind == rule.type.transactionKind &&
            $0.accountID == rule.accountID &&
            ($0.recurringOccurrenceID == nil || $0.recurringOccurrenceID == occurrenceID) }
    }

    var body: some View {
        List {
            Section {
                Text("Only transactions from the same managed account and movement kind are shown. Historical account labels must be linked to a managed account first.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Eligible Activity transactions") {
                if eligible.isEmpty { Text("No eligible transaction. Add or edit one in Activity first.") }
                ForEach(eligible) { transaction in
                    Button {
                        selected = transaction
                    } label: {
                        VStack(alignment: .leading) {
                            Text(transaction.merchant)
                            Text("\(Money.format(transaction.eurMinor ?? transaction.amountMinor)) · \(transaction.occurredAt.easyTrackFormatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Link transaction")
        .confirmationDialog("Link this payment?", isPresented: Binding(
            get: { selected != nil }, set: { if !$0 { selected = nil } }), titleVisibility: .visible) {
                Button("Link payment") {
                    guard let transaction = selected else { return }
                    do {
                        try store.linkRecurringTransaction(transaction.id, to: occurrenceID,
                            occurrenceRevision: occurrence?.revision,
                            transactionRevision: transaction.revision)
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                    selected = nil
                }
            } message: {
                Text(selected.map { transaction in
                    recurringLinkEffect(actual: transaction,
                        replacing: store.transactions.first(where: { $0.id == occurrence?.transactionID }))
                } ?? "Choose a transaction to see its effect on totals.")
            }
        .alert("Could not link", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(AppLanguage.localized(errorMessage ?? "")) }
    }
}

struct RecurringTransactionLinkView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let transactionID: UUID
    @State private var selected: RecurringOccurrence?
    @State private var errorMessage: String?

    private var transaction: Transaction? { store.transactions.first { $0.id == transactionID } }
    private var eligible: [RecurringOccurrence] {
        guard let transaction else { return [] }
        return store.recurringOccurrences.filter { occurrence in
            guard occurrence.status != .confirmed && occurrence.status != .cancelled,
                  let rule = store.recurringRules.first(where: { $0.id == occurrence.ruleID }) else { return false }
            return rule.accountID == transaction.accountID &&
                rule.type.transactionKind == transaction.kind
        }
    }

    var body: some View {
        List {
            Section {
                Text("Only occurrences from this transaction’s managed account and movement kind are shown. Linking keeps the real amount and provenance.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Eligible occurrences") {
                if eligible.isEmpty { Text("No eligible occurrence. Check the transaction’s managed account.") }
                ForEach(eligible) { occurrence in
                    Button {
                        selected = occurrence
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.recurringRules.first(where: { $0.id == occurrence.ruleID })?.name ?? "Recurring payment")
                            Text("\(occurrence.scheduledDay.localizedString) · \(AppLanguage.localized(occurrence.status.title))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Link recurring payment")
        .confirmationDialog("Link to this occurrence?", isPresented: Binding(
            get: { selected != nil }, set: { if !$0 { selected = nil } }), titleVisibility: .visible) {
                Button("Link payment") {
                    guard let occurrence = selected else { return }
                    do {
                        try store.linkRecurringTransaction(transactionID, to: occurrence.id,
                            occurrenceRevision: occurrence.revision,
                            transactionRevision: transaction?.revision)
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                    selected = nil
                }
            } message: {
                Text(transaction.map { actual in
                    recurringLinkEffect(actual: actual,
                        replacing: store.transactions.first(where: { $0.id == selected?.transactionID }))
                } ?? "Choose an occurrence to see its effect on totals.")
            }
        .alert("Could not link", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(AppLanguage.localized(errorMessage ?? "")) }
    }
}
