import SwiftUI
import UIKit

private enum AutomationStyle {
    static let accent = Color.teal
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

struct AutomationsView: View {
    @EnvironmentObject private var store: FinanceStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "bell.and.waves.left.and.right.fill")
                        .font(.title2).foregroundStyle(.white)
                        .padding(12).background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                    Text("Make each notification useful").font(.title2.bold())
                    Text("Capture a payment notification with Shortcuts. Build a local rule from its words, test it, then choose when it creates a transaction.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .foregroundStyle(.white)
                .background(LinearGradient(colors: [.teal, .blue], startPoint: .topLeading,
                                           endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))

#if DEBUG
                Menu {
                    Button("Northstar Pay sample") { store.captureSyntheticExample(1) }
                    Button("Northstar Pay second purchase") { store.captureSyntheticExample(3) }
                    Button("Northstar Pay different merchant") { store.captureSyntheticExample(4) }
                    Button("Harbor Wallet sample") { store.captureSyntheticExample(2) }
                    Button("Send a demo test payload") { store.captureDemoEvent() }
                } label: { Label("Try fictional notification", systemImage: "sparkles") }
                    .buttonStyle(.bordered).tint(AutomationStyle.accent)
#endif

                Text("Sources").font(.title3.bold())
                if store.parserSources.isEmpty {
                    ContentUnavailableView("No notifications yet", systemImage: "bell.slash",
                                           description: Text("Use the Capture Payment Notification action in Shortcuts to start."))
                }
                ForEach(store.parserSources) { source in
                    NavigationLink { AutomationSourceView(source: source) } label: {
                        sourceCard(source)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("automationSource-\(source.name)")
                }
            }
            .padding(20)
        }
        .background(AutomationStyle.background)
        .navigationTitle("Automations")
    }

    private func sourceCard(_ source: ParserSource) -> some View {
        let attempts = store.parserAttempts.filter { $0.sourceID == source.id }
        let active = store.parserRules.filter { $0.sourceID == source.id && $0.enabled }.count
        let latest = attempts.first
        let lastSuccess = attempts.first { $0.status == .created }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: active > 0 ? "bolt.fill" : "wand.and.stars")
                    .font(.headline).foregroundStyle(active > 0 ? .green : .orange)
                    .frame(width: 42, height: 42)
                    .background((active > 0 ? Color.green : Color.orange).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.name).font(.headline).foregroundStyle(.primary)
                    Text(source.accountName.map { "Account · \($0)" } ?? "Map an account")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(active > 0 ? "\(active) active format\(active == 1 ? "" : "s")" : "Add notification format")
                        .font(.caption2).foregroundStyle(active > 0 ? .green : .orange)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            HStack {
                Label("\(attempts.count) captured", systemImage: "tray")
                Spacer()
                Text(latest?.status.title ?? "Awaiting first capture")
            }
            .font(.caption).foregroundStyle(.secondary)
            if let lastSuccess {
                Text("Last added \(lastSuccess.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(17)
        .background(AutomationStyle.card, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

private struct AutomationSourceView: View {
    @EnvironmentObject private var store: FinanceStore
    let source: ParserSource
    @State private var setupAttempt: ParserAttempt?
    @State private var editingRule: ParserRule?
    @State private var ruleToDelete: ParserRule?
    @State private var manualEvent: NotificationEvent?
    @State private var showingAccountMapping = false

    private var currentSource: ParserSource { store.parserSources.first(where: { $0.id == source.id }) ?? source }
    private var attempts: [ParserAttempt] { store.parserAttempts.filter { $0.sourceID == source.id } }
    private var rules: [ParserRule] { store.parserRules.filter { $0.sourceID == source.id } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("On this iPhone").font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(.secondary)
                    Text("\(attempts.count) captured · \(rules.filter(\.enabled).count) active")
                        .font(.title2.bold())
                    Text("Raw notifications stay here so you can check what happened. A rule creates a transaction only when every required value is found.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 9) {
                    Label("Source account", systemImage: "building.columns.circle")
                        .font(.subheadline.weight(.semibold))
                    Text(currentSource.accountName ?? "No account mapped yet")
                        .font(.headline)
                    Text("Every notification format from this app uses this account. Changing it affects future transactions only.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(currentSource.accountName == nil ? "Map account" : "Change account") {
                        showingAccountMapping = true
                    }
                    .buttonStyle(.bordered).tint(AutomationStyle.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(17).background(AutomationStyle.card, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityIdentifier("sourceAccountCard")
                sectionHeader("Notification formats", symbol: "square.stack.3d.up")
                if rules.isEmpty { hint("No format yet. Open a captured notification and choose Set up.") }
                ForEach(rules) { rule in ruleCard(rule) }
                if let sample = attempts.first {
                    Button { setupAttempt = sample } label: { Label("Add another format", systemImage: "plus.circle.fill") }
                        .buttonStyle(.bordered).tint(AutomationStyle.accent)
                }
                sectionHeader("Captured notifications", symbol: "tray.full")
                if attempts.isEmpty { hint("A Shortcuts capture will appear here.") }
                ForEach(attempts) { attempt in sampleCard(attempt) }
            }
            .padding(20)
        }
        .background(AutomationStyle.background)
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $setupAttempt) { attempt in
            NavigationStack { ParserBuilderView(source: currentSource, sample: attempt, existingRule: nil) }
        }
        .sheet(item: $editingRule) { rule in
            if let sample = attempts.first {
                NavigationStack { ParserBuilderView(source: currentSource, sample: sample, existingRule: rule) }
            }
        }
        .sheet(isPresented: $showingAccountMapping) {
            NavigationStack { SourceAccountMappingView(source: currentSource) }
        }
        .sheet(item: $manualEvent) { event in
            NavigationStack { TransactionEditor(prefillEvent: event) }
        }
        .confirmationDialog("Delete this automation?", isPresented: Binding(
            get: { ruleToDelete != nil }, set: { if !$0 { ruleToDelete = nil } }),
            titleVisibility: .visible) {
                Button("Delete automation", role: .destructive) {
                    guard var rule = ruleToDelete else { return }
                    rule.deletedAt = .now
                    do { try store.saveRule(rule) } catch { store.errorMessage = error.localizedDescription }
                    ruleToDelete = nil
                }
            } message: { Text("Transactions it already created will stay in Activity.") }
    }

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.title3.bold()).foregroundStyle(.primary)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18).background(AutomationStyle.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func ruleCard(_ rule: ParserRule) -> some View {
        let preview = attempts.first.map {
            NotificationParser.preview($0.event, config: rule.config,
                                       mappedAccount: currentSource.accountName)
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: rule.enabled ? "bolt.circle.fill" : "pause.circle.fill")
                    .foregroundStyle(rule.enabled ? .green : .secondary)
                Text(rule.name).font(.headline)
                Spacer()
                Text("#\(rule.priority)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(preview?.ready == true ?
                 "\(Money.format(preview!.amount!.cents)) · \(preview!.merchant!)" :
                 "Test this format with a captured notification")
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                Toggle("Enabled", isOn: Binding(get: { rule.enabled }, set: { enabled in
                    var updated = rule; updated.enabled = enabled
                    do { try store.saveRule(updated) } catch { store.errorMessage = error.localizedDescription }
                })).labelsHidden()
                Text(rule.enabled ? "On" : "Off").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { move(rule, by: -1) } label: { Image(systemName: "arrow.up") }
                    .accessibilityLabel("Move \(rule.name) earlier")
                    .disabled(rule.priority <= 1)
                Button { move(rule, by: 1) } label: { Image(systemName: "arrow.down") }
                    .accessibilityLabel("Move \(rule.name) later")
                    .disabled(rule.priority >= rules.count)
                Button { editingRule = rule } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Edit \(rule.name)")
                Button(role: .destructive) { ruleToDelete = rule } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Delete \(rule.name)")
            }
            .buttonStyle(.borderless)
            .tint(AutomationStyle.accent)
            Text("Version \(rule.version) · Earlier transactions keep their original rule version")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(17)
        .background(AutomationStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func move(_ rule: ParserRule, by offset: Int) {
        guard let other = rules.first(where: { $0.priority == rule.priority + offset }) else { return }
        do {
            try store.swapRulePriorities(rule, other)
        } catch { store.errorMessage = error.localizedDescription }
    }

    private func sampleCard(_ attempt: ParserAttempt) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Image(systemName: symbol(for: attempt.status))
                    .foregroundStyle(color(for: attempt.status))
                Text(attempt.status.title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(attempt.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(attempt.event.title.isEmpty ? "Untitled notification" : attempt.event.title)
                .font(.headline)
            if !attempt.event.subtitle.isEmpty { Text(attempt.event.subtitle).font(.subheadline) }
            if !attempt.event.message.isEmpty {
                Text(attempt.event.message).font(.subheadline).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let detail = attempt.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            if attempt.status == .recurringReview,
               let candidate = store.recurringCandidates.first(where: {
                   $0.eventID == attempt.event.id && $0.status == .pending
               }) {
                NavigationLink("Review recurring payment") {
                    RecurringOccurrenceDetailView(occurrenceID: candidate.occurrenceID)
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("reviewRecurringMatch")
            }
            HStack {
                if [.setupRequired, .unmatched, .failed].contains(attempt.status) {
                    Button(attempt.status == .unmatched ? "Add notification format" : "Set up format") {
                        setupAttempt = attempt
                    }
                        .buttonStyle(.borderedProminent).tint(AutomationStyle.accent)
                }
                if [.failed, .unmatched, .ready, .setupRequired].contains(attempt.status) && !rules.isEmpty {
                    Button("Retry") {
                        do { try store.processAttempt(attempt.id) }
                        catch { store.errorMessage = error.localizedDescription }
                    }.buttonStyle(.bordered)
                }
                if attempt.transactionID == nil && attempt.status != .duplicateIgnored &&
                   attempt.status != .recurringReview {
                    Button("Create manually") { manualEvent = attempt.event }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(17)
        .background(AutomationStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func symbol(for status: ParserAttemptStatus) -> String {
        switch status {
        case .created: "checkmark.circle.fill"
        case .matchedExisting: "checkmark.circle.fill"
        case .recurringReview: "exclamationmark.circle.fill"
        case .duplicateIgnored: "square.on.square"
        case .failed: "exclamationmark.triangle.fill"
        case .setupRequired, .unmatched: "wand.and.stars"
        case .captured, .ready: "bell.badge"
        }
    }

    private func color(for status: ParserAttemptStatus) -> Color {
        switch status {
        case .created, .matchedExisting: .green
        case .recurringReview: .orange
        case .failed: .red
        case .setupRequired, .unmatched: .orange
        case .duplicateIgnored, .captured, .ready: .teal
        }
    }
}

private struct SourceAccountMappingView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let source: ParserSource
    @State private var accountName: String
    @State private var errorMessage: String?

    init(source: ParserSource) {
        self.source = source
        _accountName = State(initialValue: source.accountName ?? source.name)
    }

    private var isExisting: Bool {
        store.availableAccountNames.contains {
            NotificationParser.normalize($0) == NotificationParser.normalize(accountName)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "building.columns.circle.fill")
                    .font(.largeTitle).foregroundStyle(AutomationStyle.accent)
                Text("One account for this source").font(.title2.bold())
                Text("All notification formats from \(source.name) will use this EasyTrack account. Existing transactions keep their account if you change this later.")
                    .font(.subheadline).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    Text("EasyTrack account").font(.subheadline.weight(.semibold))
                    TextField("Account name", text: $accountName)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("sourceAccountField")
                    if !store.availableAccountNames.isEmpty {
                        Menu("Choose an existing account") {
                            ForEach(store.availableAccountNames, id: \.self) { name in
                                Button(name) { accountName = name }
                            }
                        }
                    }
                }
                .padding(17).background(AutomationStyle.card, in: RoundedRectangle(cornerRadius: 18))
                Text(isExisting ? "Use this existing account" : "Create this account in EasyTrack")
                    .font(.caption).foregroundStyle(.secondary)
                if let errorMessage { Text(errorMessage).font(.subheadline).foregroundStyle(.red) }
                Button("Save source account") {
                    do {
                        try store.mapSourceAccount(source.id, to: accountName)
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("saveSourceAccountButton")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(AutomationStyle.background)
        .navigationTitle("Source account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        .task { if source.accountName == nil { accountName = store.proposedAccountName(for: source) } }
    }
}

private struct ParserBuilderView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let source: ParserSource
    let sample: ParserAttempt
    let existingRule: ParserRule?

    @State private var config: ParserRuleConfig
    @State private var name: String
    @State private var accountName: String
    @State private var draftRuleID: UUID
    @State private var draftRuleVersion: Int
    @State private var savedRule: ParserRule?
    @State private var openStep: Int? = 0
    @State private var tested = false
    @State private var animatedStep = -1
    @State private var showAdvanced = false
    @State private var choosingFirstTransaction = false
    @State private var saving = false
    @State private var errorMessage: String?

    init(source: ParserSource, sample: ParserAttempt, existingRule: ParserRule?) {
        self.source = source; self.sample = sample; self.existingRule = existingRule
        _config = State(initialValue: existingRule?.config ?? NotificationParser.suggest(for: sample.event))
        _name = State(initialValue: existingRule?.name ?? "Payment notification format")
        _accountName = State(initialValue: source.accountName ?? source.name)
        _draftRuleID = State(initialValue: existingRule?.id ?? UUID())
        _draftRuleVersion = State(initialValue: existingRule?.version ?? 0)
        _savedRule = State(initialValue: nil)
    }

    private var currentSource: ParserSource { store.parserSources.first(where: { $0.id == source.id }) ?? source }
    private var mappedAccount: String { currentSource.accountName ?? accountName }
    private var preview: ParserPreview {
        NotificationParser.preview(sample.event, config: config, mappedAccount: mappedAccount)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(existingRule == nil ? "Build a notification format" : "Refine this format")
                        .font(.title2.bold())
                    Text("This format can handle many merchants. Tap each block to choose what it reads from every notification.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    TextField("Format name", text: $name)
                        .font(.headline).padding(12)
                        .background(AutomationStyle.card, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("parserRuleNameField")
                }
                block(0, "Notification input", "bell.badge.fill",
                      config.inputField.text(in: sample.event).isEmpty ? "No text in selected field" : config.inputField.text(in: sample.event)) {
                    Picker("Read amount from", selection: $config.inputField) {
                        ForEach(NotificationField.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Match text in", selection: $config.conditionField) {
                        ForEach(NotificationField.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Notification matches when", selection: $config.conditionMode) {
                        ForEach(TextMatchMode.allCases.filter { showAdvanced || $0 != .regularExpression }) { Text($0.title).tag($0) }
                    }
                    TextField("Matching words (optional)", text: $config.conditionText)
                        .textInputAutocapitalization(.never)
                    DisclosureGroup("Advanced matching", isExpanded: $showAdvanced) {
                        Text("Short regular expressions are allowed. Complex patterns are rejected before saving.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                block(1, "Source / account", "building.columns.circle.fill", mappedAccount) {
                    Text("\(source.name) notifications use one EasyTrack account across all formats and merchants.")
                        .font(.caption).foregroundStyle(.secondary)
                    if currentSource.accountName == nil {
                        TextField("Account name", text: $accountName)
                            .accessibilityIdentifier("parserAccountField")
                        if !store.availableAccountNames.isEmpty {
                            Menu("Choose an existing account") {
                                ForEach(store.availableAccountNames, id: \.self) { account in
                                    Button(account) { accountName = account }
                                }
                            }
                        }
                        Text(store.availableAccountNames.contains(where: {
                            NotificationParser.normalize($0) == NotificationParser.normalize(accountName)
                        }) ? "Use this existing account" : "Create this account when you activate the format")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("To change this mapping for future transactions, use Change account on the source page.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                block(2, "Direction / movement type", "arrow.left.arrow.right.circle.fill", config.kind.title) {
                    Picker("Type", selection: $config.kind) {
                        ForEach(TransactionKind.allCases) { Text($0.title).tag($0) }
                    }
                    Text("Use fixed wording such as “paid” or “received” above to identify this format. Different wording can have another format rule.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                block(3, "Amount", "eurosign.circle.fill",
                      preview.amount.map { Money.format($0.cents) } ?? "No EUR amount found") {
                    TextField("Text immediately before amount (optional)", text: $config.amountPrefix)
                    TextField("Text immediately after amount (optional)", text: $config.amountSuffix)
                    Text("The number is captured anew for each notification.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                block(4, "Merchant / description", "text.quote",
                      preview.merchant ?? "Choose the words to use") {
                    Picker("Read description from", selection: $config.merchantField) {
                        ForEach(NotificationField.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Select text", selection: $config.merchantMode) {
                        ForEach(MerchantMode.allCases.filter { showAdvanced || $0 != .regularExpression }) { Text($0.title).tag($0) }
                    }
                    if config.merchantMode == .betweenAnchors {
                        TextField("Text before merchant", text: $config.merchantPrefix)
                        TextField("Text after merchant", text: $config.merchantSuffix)
                    }
                    if config.merchantMode == .regularExpression {
                        TextField("Advanced pattern", text: $config.merchantPattern)
                            .textInputAutocapitalization(.never)
                    }
                    Text("“\(preview.merchant ?? "Merchant")” is a live sample, not a fixed match.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                block(5, "Duplicate protection", "square.on.square",
                      "Same payment within \(config.duplicateWindowSeconds / 60) minutes") {
                    Picker("Time window", selection: $config.duplicateWindowSeconds) {
                        Text("5 minutes").tag(300)
                        Text("10 minutes").tag(600)
                        Text("30 minutes").tag(1_800)
                    }
                    Text("Exact replays and similar payments in this window are ignored. The amount must also match.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                block(6, "Create transaction", "checkmark.circle.fill",
                      preview.ready ? "Ready to add to Activity" : "Finish the steps above") {
                    transactionPreview
                }

                Button {
                    testAutomation()
                } label: { Label("Test automation", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).controlSize(.large)
                    .accessibilityIdentifier("testAutomationButton")
                if tested {
                    Label(preview.ready ? "Every step passed. Review the transaction below." :
                            (preview.error ?? "This notification does not match the rule."),
                          systemImage: preview.ready ? "checkmark.seal.fill" : "exclamationmark.triangle")
                        .font(.subheadline).foregroundStyle(preview.ready ? .green : .orange)
                        .accessibilityIdentifier("parserTestResult")
                }
                if let errorMessage { Text(errorMessage).font(.subheadline).foregroundStyle(.red) }
                Button(existingRule == nil ? "Activate automation" : "Save automation") {
                    if existingRule == nil { choosingFirstTransaction = true }
                    else { saveRule(createFirst: false) }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!tested || !preview.ready || saving)
                .accessibilityIdentifier("activateAutomationButton")
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(AutomationStyle.background)
        .navigationTitle("Automation setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        .onChange(of: config) { _, _ in tested = false; animatedStep = -1 }
        .onChange(of: accountName) { _, _ in tested = false; animatedStep = -1 }
        .confirmationDialog("Add this first payment?", isPresented: $choosingFirstTransaction,
                            titleVisibility: .visible) {
            Button("Create first transaction") { saveRule(createFirst: true) }
            Button("Activate without adding sample") { saveRule(createFirst: false) }
        } message: {
            Text("The source account mapping is confirmed once. This format will handle later merchants, and the sample can be added exactly once without a category.")
        }
    }

    private var transactionPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let amount = preview.amount { Text(Money.format(amount.cents)).font(.title3.bold()) }
            Text(preview.merchant ?? "Description needed").font(.headline)
            Text("\(config.kind.title) · \(mappedAccount.isEmpty ? "Account needed" : mappedAccount) · Uncategorized")
                .font(.subheadline).foregroundStyle(.secondary)
            Text(preview.occurredAt.formatted(date: .abbreviated, time: .shortened) +
                 (sample.event.receivedAt == nil ? " · receipt time" : " · notification date"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func block<Content: View>(_ index: Int, _ title: String, _ symbol: String,
                                      _ result: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    openStep = openStep == index ? nil : index
                }
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: symbol).font(.title3)
                        .foregroundStyle(index <= animatedStep ? .green : AutomationStyle.accent)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text(result).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: index <= animatedStep ? "checkmark.circle.fill" :
                            (openStep == index ? "chevron.up" : "chevron.down"))
                        .foregroundStyle(index <= animatedStep ? .green : .secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title): \(result)")
            .accessibilityValue(openStep == index ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("parserStep-\(index)")
            if openStep == index {
                VStack(alignment: .leading, spacing: 11) { content() }
                    .font(.subheadline)
                    .padding(.leading, 43)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(AutomationStyle.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func testAutomation() {
        tested = false
        animatedStep = -1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { @MainActor in
            for step in 0..<7 {
                try? await Task.sleep(nanoseconds: 140_000_000)
                withAnimation(.easeInOut(duration: 0.2)) { animatedStep = step }
            }
            tested = true
            UINotificationFeedbackGenerator().notificationOccurred(preview.ready ? .success : .warning)
        }
    }

    private func saveRule(createFirst: Bool) {
        guard tested && preview.ready && !saving else { return }
        saving = true
        errorMessage = nil
        var cleanConfig = config
        cleanConfig.account = ""
        cleanConfig.category = ""
        let rule = ParserRule(id: draftRuleID, sourceID: source.id, name: name, enabled: true,
                              priority: existingRule?.priority ?? store.parserRules.filter { $0.sourceID == source.id }.count + 1,
                              version: draftRuleVersion, config: cleanConfig,
                              createdAt: existingRule?.createdAt ?? .now, updatedAt: .now, deletedAt: nil)
        do {
            if currentSource.accountName == nil {
                _ = try store.mapSourceAccount(source.id, to: accountName)
            }
            let saved: ParserRule
            if let previous = savedRule, previous.config == cleanConfig && previous.name == name {
                saved = previous
            } else {
                saved = try store.saveRule(rule)
                savedRule = saved
                draftRuleVersion = saved.version
            }
            if existingRule == nil {
                if createFirst {
                    let result = try store.processAttempt(sample.id, preferredRuleID: saved.id)
                    guard [.created, .duplicateIgnored].contains(result.status) else {
                        throw ParserValidationError.invalidRule(result.detail ?? "This sample could not be added. Retry it here.")
                    }
                }
                else { try store.leaveSampleReady(sample.id) }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            saving = false
        }
    }
}
