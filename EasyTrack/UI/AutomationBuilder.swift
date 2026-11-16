import SwiftUI
import UIKit

private enum AutomationStyle {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

struct AutomationsView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.easyTrackTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "bell.and.waves.left.and.right.fill")
                        .font(.title2).foregroundStyle(theme.heroText)
                        .padding(12).background(theme.heroMetricBackground, in: RoundedRectangle(cornerRadius: 14))
                    Text("Make each notification useful").font(.title2.bold())
                    Text("Capture a payment notification with Shortcuts. Build a local rule from its words, test it, then choose when it creates a transaction.")
                        .font(.subheadline).foregroundStyle(theme.heroSecondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .foregroundStyle(theme.heroText)
                .background(LinearGradient(colors: theme.heroColors, startPoint: .topLeading,
                                           endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))

                NavigationLink { NotificationSetupGuideView() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "list.number")
                            .font(.title2).frame(width: 44, height: 44)
                            .background(theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Set up automatic notifications").font(.headline)
                            Text("Account, Shortcuts, field mapping, safe test and diagnostics")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(17)
                    .background(AutomationStyle.card, in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("notificationSetupGuide")

#if DEBUG
                Menu {
                    Button("Northstar Pay sample") { store.captureSyntheticExample(1) }
                    Button("Northstar Pay second purchase") { store.captureSyntheticExample(3) }
                    Button("Northstar Pay different merchant") { store.captureSyntheticExample(4) }
                    Button("Harbor Wallet sample") { store.captureSyntheticExample(2) }
                    Button("Send a demo test payload") { store.captureDemoEvent() }
                } label: { Label("Try fictional notification", systemImage: "sparkles") }
                    .buttonStyle(.bordered).tint(theme.accent)
#endif

                Text("Sources").font(.title3.bold())
                if store.parserSources.isEmpty {
                    ContentUnavailableView("No notifications yet", systemImage: "bell.slash",
                                           description: Text("Start with the guided setup above. EasyTrack cannot read iOS notifications until you create the automation in Shortcuts."))
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
        .task {
            do { _ = try store.purgeExpiredNotificationContents() }
            catch { store.errorMessage = error.localizedDescription }
        }
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

struct NotificationSetupGuideView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.openURL) private var openURL
    @Environment(\.easyTrackTheme) private var theme
    @State private var selectedAccountID: UUID?
    @State private var sourceLabel = ""
    @State private var openStep = 0
    @State private var demoKind = DemoKind.payment
    @State private var simulationRan = false
    @State private var statusMessage: String?

    private enum DemoKind: String, CaseIterable, Identifiable {
        case payment = "Valid payment"
        case security = "OTP / security"
        case promotion = "Promotion"
        var id: String { rawValue }
    }

    private var selectedAccount: LocalAccount? {
        store.activeAccounts.first { $0.id == selectedAccountID }
    }

    private var effectiveSourceLabel: String {
        let clean = sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "Northstar Pay (fictional)" : clean
    }

    private var demoEvent: NotificationEvent {
        let title: String
        let message: String
        switch demoKind {
        case .payment:
            title = "Card purchase"
            message = "Paid €12,34 at Cedar Books"
        case .security:
            title = "Verification code"
            message = "Your OTP code is 482913. Do not share this code."
        case .promotion:
            title = "Special offer"
            message = "Get €10 cashback this weekend. Open the app to discover the offer."
        }
        return NotificationEvent.make(sourceApp: effectiveSourceLabel, title: title, subtitle: "",
                                      message: message, receivedAt: .now)!
    }

    private var demoRejection: String? { NotificationSafetyFilter.rejectionReason(for: demoEvent) }

    private var demoPreview: ParserPreview {
        NotificationParser.preview(demoEvent, config: NotificationParser.suggest(for: demoEvent),
                                   mappedAccount: selectedAccount?.name)
    }

    private var checklist: [(String, String, Bool)] {
        let milestones = store.automationSetupMilestones
        return [
            ("Choose account and source", "An EasyTrack source is mapped to one account.",
             milestones.contains(.sourceMapped) || store.parserSources.contains { $0.accountID != nil }),
            ("Open Shortcuts setup", "The system automation must be created by you.",
             milestones.contains(.shortcutsOpened)),
            ("Review trigger fields", "Source app and notification variables are understood.",
             milestones.contains(.fieldsReviewed)),
            ("Capture a sample", "A real Shortcuts invocation reached EasyTrack.",
             !store.parserAttempts.isEmpty),
            ("Approve a format", "At least one local parsing rule is configured.",
             !store.parserRules.isEmpty),
            ("Verify first payment", "A captured notification created or matched a transaction.",
             store.parserAttempts.contains { [.created, .matchedExisting].contains($0.status) })
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                boundaryCard
                VStack(alignment: .leading, spacing: 10) {
                    Text("Setup progress").font(.title3.bold())
                    ForEach(Array(checklist.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: item.2 ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.2 ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(index + 1). \(item.0)").font(.subheadline.weight(.semibold))
                                Text(item.1).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(item.2 ? "Complete" : "Not complete")
                    }
                }
                .guideCard()

                ForEach(0..<6, id: \.self) { step in
                    stepCard(step)
                }

#if DEBUG
                simulationCard
#endif
                diagnosticStatus
                troubleshooting

                Link(destination: URL(string: "https://support.apple.com/guide/shortcuts/apd932ff833f/10.0/ios/27")!) {
                    Label("Apple Help: Notification event trigger", systemImage: "safari")
                }
                Link(destination: URL(string: "https://support.apple.com/guide/shortcuts/apdfbdbd7123/10.0/ios/27")!) {
                    Label("Apple Help: Add an automation", systemImage: "safari")
                }
                .font(.subheadline)
            }
            .padding(20)
        }
        .background(AutomationStyle.background)
        .navigationTitle("Notification setup")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if selectedAccountID == nil { selectedAccountID = store.activeAccounts.first?.id }
            if sourceLabel.isEmpty { sourceLabel = store.parserSources.first?.name ?? "" }
            do { _ = try store.purgeExpiredNotificationContents() }
            catch { statusMessage = error.localizedDescription }
        }
    }

    private var boundaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Two separate choices", systemImage: "rectangle.2.swap")
                .font(.title3.bold())
            Text("In Shortcuts, Notification → App selects the bank or payment app that sends the notification.")
                .font(.subheadline.weight(.semibold))
            Text("In EasyTrack → Capture Payment Notification, Source app is only a text label. It must exactly match the source label saved below. It is not an app selector.")
                .font(.subheadline)
            Text("EasyTrack cannot list installed banking apps, read notification history, or monitor every iOS notification by itself.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .guideCard(accent: .orange)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func stepCard(_ step: Int) -> some View {
        let titles = [
            "Choose the EasyTrack account", "Create the Notification trigger", "Add the EasyTrack action",
            "Connect the notification fields", "Capture and approve a format", "Verify and diagnose"
        ]
        let symbols = ["building.columns", "bell.badge", "bolt.circle", "arrow.triangle.branch",
                       "wand.and.stars", "checklist"]
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { openStep = openStep == step ? -1 : step }
            } label: {
                HStack {
                    Image(systemName: symbols[step]).frame(width: 28)
                        .foregroundStyle(theme.accent)
                    Text("\(step + 1). \(titles[step])").font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: openStep == step ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityValue(openStep == step ? "Expanded" : "Collapsed")
            if openStep == step {
                stepContent(step)
                HStack {
                    if step > 0 { Button("Back") { openStep = step - 1 } }
                    Spacer()
                    if step < 5 { Button("Next") { openStep = step + 1 } }
                }
                .buttonStyle(.bordered)
            }
        }
        .guideCard()
    }

    @ViewBuilder
    private func stepContent(_ step: Int) -> some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 12) {
                if store.activeAccounts.isEmpty {
                    Text("Create an account first. No banking credentials are requested.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    NavigationLink("Open Accounts") { AccountsView() }
                } else {
                    Picker("EasyTrack account", selection: $selectedAccountID) {
                        Text("Choose an account").tag(UUID?.none)
                        ForEach(store.activeAccounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                    TextField("Source app label", text: $sourceLabel)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("notificationSourceLabel")
                    Text("Use a short stable label, for example “Northstar Bank”. Do not enter a username, password, card number, or OTP.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Save source and account") { saveSource() }
                            .buttonStyle(.borderedProminent)
                            .disabled(selectedAccountID == nil || sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button { copySourceLabel() } label: { Label("Copy name", systemImage: "doc.on.doc") }
                            .buttonStyle(.bordered)
                            .disabled(sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        case 1:
            VStack(alignment: .leading, spacing: 9) {
                Text("Open Comandi Rapidi → Automazione → + or New Automation → Notifica → App, then choose the BANK app in the trigger.")
                Text("Depending on the installed iOS layout, + may first show the shortcut editor; return to the Automation tab or choose Edit → Automation. The trigger and the action are separate.")
                    .foregroundStyle(.secondary)
                Text("Start without narrow Title/Subtitle/Message filters. Add filters only after inspecting a real sample, or a valid payment may be missed.")
                    .foregroundStyle(.secondary)
                Button { openShortcuts() } label: { Label("Open Shortcuts", systemImage: "arrow.up.forward.app") }
                    .buttonStyle(.borderedProminent)
            }.font(.subheadline)
        case 2:
            VStack(alignment: .leading, spacing: 9) {
                Text("Add Action → EasyTrack → Capture Payment Notification.")
                    .font(.subheadline.weight(.semibold))
                Text("Paste “\(effectiveSourceLabel)” into Source app. This text identifies the EasyTrack source; it does not select the bank app.")
                Text("If the EasyTrack action is missing, launch EasyTrack once, reopen Shortcuts, and confirm the installed app is still trusted and available.")
                    .foregroundStyle(.secondary)
                Button { copySourceLabel() } label: { Label("Copy source label", systemImage: "doc.on.doc") }
                    .buttonStyle(.bordered)
            }.font(.subheadline)
        case 3:
            VStack(alignment: .leading, spacing: 8) {
                fieldHelp("Source app", "Required text: paste the exact EasyTrack source label. Never choose an app here.")
                fieldHelp("Title", "Optional: insert the Title variable supplied by the Notification trigger, if your iOS version offers it. Do not type sample prose.")
                fieldHelp("Subtitle", "Optional: insert the trigger's Subtitle variable when available.")
                fieldHelp("Message", "Optional but normally needed: insert the trigger's Message/body variable when available.")
                fieldHelp("Notification date", "Optional: insert the trigger date only when offered. Otherwise EasyTrack safely uses receipt time.")
                Text("Tap a parameter field in Shortcuts and choose the matching variable from the Notification trigger. Available variable names can differ by iOS version; preview only fictional or non-sensitive text.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Apple documents Title, Subtitle and Message as notification FILTERS, but does not guarantee that every field is exposed as an action variable on every iOS build. A dynamic value appears as a blue variable token and changes for each notification. Never type a fixed payment example. If no matching token is offered, leave that field empty and treat capture as unverified; first test with two harmless notifications containing different text.")
                    .font(.caption).foregroundStyle(.orange)
                Button("I reviewed these fields") { mark(.fieldsReviewed) }
                    .buttonStyle(.bordered)
            }
        case 4:
            VStack(alignment: .leading, spacing: 8) {
                Text("Set the automation to run automatically when that option is available, accept the required Shortcuts permissions, and trigger one harmless notification.")
                Text("A received sample appears under its source in EasyTrack. Open it, confirm the account, amount and merchant, test the seven setup blocks, then explicitly activate the format.")
                Text("One source maps to one account and may have several notification-format rules. A simulation below never inserts a transaction.")
                    .foregroundStyle(.secondary)
            }.font(.subheadline)
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("Check three different facts: trigger tested, sample captured, and first real transaction verified. Typing a source label alone is never “connected”.")
                Text("Test on the real bank app later with the phone locked, EasyTrack suspended, after relaunch, and with repeated notifications. Shortcuts delivery can be device-dependent; reconcile missing payments manually.")
                Text("Diagnostics retain raw notification text for \(store.notificationRetentionDays) days by default policy and purge it at the next app open, capture, or diagnostics visit—not while the app stays closed.")
                    .foregroundStyle(.secondary)
            }.font(.subheadline)
        }
    }

    private func fieldHelp(_ name: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var simulationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Safe fictional parser test", systemImage: "testtube.2")
                .font(.title3.bold())
            Text("This checks only EasyTrack's parser and UI. It does not test iOS notification delivery, Shortcuts, background execution, or a bank app.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Fictional sample", selection: $demoKind) {
                ForEach(DemoKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Button { runSimulation() } label: { Label("Run dry test", systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("notificationDryRun")
            if simulationRan {
                LabeledContent("Recognized source", value: demoEvent.sourceApp)
                LabeledContent("Mapped account", value: selectedAccount?.name ?? "Choose an account above")
                if let reason = demoRejection {
                    Label(reason, systemImage: "shield.checkered")
                        .font(.subheadline).foregroundStyle(.orange)
                } else {
                    LabeledContent("Recognized amount", value: demoPreview.amount.map { Money.format($0.cents) } ?? "Not found")
                    LabeledContent("Recognized merchant", value: demoPreview.merchant ?? "Not found")
                    Label(demoPreview.ready ? "Preview ready: a matching real event could create this transaction." :
                            (demoPreview.error ?? "This sample does not match."),
                          systemImage: demoPreview.ready ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.subheadline)
                }
                Text("No financial transaction or captured-notification record was written by this dry test.")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .guideCard(accent: .blue)
    }

    private var diagnosticStatus: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Integration status", systemImage: "waveform.path.ecg")
                .font(.title3.bold())
            statusLine("Shortcuts trigger", store.parserAttempts.isEmpty ? "Not yet observed" : "At least one invocation captured",
                       complete: !store.parserAttempts.isEmpty)
            statusLine("Parser format", store.parserRules.isEmpty ? "Not configured" : "Configured",
                       complete: !store.parserRules.isEmpty)
            statusLine("Real bank payment", "Not verified on the primary phone", complete: false)
            Text("The secondary test phone has no banking apps. A dry test cannot satisfy real-notification acceptance.")
                .font(.caption).foregroundStyle(.secondary)
            if let statusMessage { Text(statusMessage).font(.caption).foregroundStyle(.secondary) }
        }
        .guideCard()
    }

    private func statusLine(_ title: String, _ detail: String, complete: Bool) -> some View {
        HStack(alignment: .top) {
            Image(systemName: complete ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                .foregroundStyle(complete ? .green : .orange)
            VStack(alignment: .leading) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var troubleshooting: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Troubleshooting", systemImage: "wrench.and.screwdriver")
                .font(.title3.bold())
            ForEach([
                "Bank app missing: it cannot be selected until it is installed on this iPhone.",
                "Label mismatch: Source app text must exactly match the EasyTrack source label.",
                "No account mapped: return to step 1 and save one active account.",
                "Sample captured but no format: open the source and set up the captured sample.",
                "Amount or merchant missing: edit the parser blocks; unsupported text stays diagnostic only.",
                "Promotion or OTP rejected: this is intentional and creates no transaction.",
                "Duplicate skipped: inspect the status and existing Activity transaction.",
                "Automation not running: check permissions, automatic execution and trigger filters in Shortcuts.",
                "App unavailable: refresh SideStore signing and trust the developer app again if required.",
                "No lock/background event: retest on the physical phone; iOS delivery is not guaranteed by EasyTrack."
            ], id: \.self) { item in
                Label(item, systemImage: "chevron.right").font(.caption)
            }
        }
        .guideCard()
    }

    private func saveSource() {
        guard let selectedAccountID else { return }
        do {
            let source = try store.configureNotificationSource(label: sourceLabel, accountID: selectedAccountID)
            sourceLabel = source.name
            statusMessage = "Source saved and mapped to \(source.accountName ?? "the selected account")."
        } catch { statusMessage = error.localizedDescription }
    }

    private func copySourceLabel() {
        let value = sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        UIPasteboard.general.string = value
        statusMessage = "Source label copied. Paste it into the Source app text field in the EasyTrack action."
    }

    private func openShortcuts() {
        guard let url = URL(string: "shortcuts://") else { return }
        openURL(url)
        mark(.shortcutsOpened)
    }

    private func runSimulation() {
        simulationRan = true
        mark(.simulationCompleted)
        UINotificationFeedbackGenerator().notificationOccurred(demoRejection == nil && demoPreview.ready ? .success : .warning)
    }

    private func mark(_ milestone: AutomationSetupMilestone) {
        do { try store.markAutomationSetupMilestone(milestone) }
        catch { statusMessage = error.localizedDescription }
    }
}

private extension View {
    func guideCard(accent: Color? = nil) -> some View {
        padding(17).frame(maxWidth: .infinity, alignment: .leading)
            .background(AutomationStyle.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                if let accent {
                    RoundedRectangle(cornerRadius: 20).stroke(accent.opacity(0.28), lineWidth: 1)
                }
            }
    }
}

private struct AutomationSourceView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.easyTrackTheme) private var theme
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
                    .buttonStyle(.bordered).tint(theme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(17).background(AutomationStyle.card, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityIdentifier("sourceAccountCard")
                sectionHeader("Notification formats", symbol: "square.stack.3d.up")
                if rules.isEmpty { hint("No format yet. Open a captured notification and choose Set up.") }
                ForEach(rules) { rule in ruleCard(rule) }
                if let sample = attempts.first {
                    Button { setupAttempt = sample } label: { Label("Add another format", systemImage: "plus.circle.fill") }
                        .buttonStyle(.bordered).tint(theme.accent)
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
            .tint(theme.accent)
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
            } else if attempt.event.title.isEmpty && attempt.event.subtitle.isEmpty {
                Label("Raw notification text removed by the retention policy", systemImage: "eye.slash")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let detail = attempt.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            if let ruleID = attempt.ruleID,
               let matchedRule = rules.first(where: { $0.id == ruleID }) {
                Label("Format: \(matchedRule.name)", systemImage: "doc.text.magnifyingglass")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
                if [.setupRequired, .unmatched, .ambiguous, .failed].contains(attempt.status) {
                    Button(attempt.status == .unmatched ? "Add notification format" : "Set up format") {
                        setupAttempt = attempt
                    }
                        .buttonStyle(.borderedProminent).tint(theme.accent)
                }
                if [.failed, .unmatched, .ambiguous, .ready, .setupRequired].contains(attempt.status) && !rules.isEmpty {
                    Button("Retry") {
                        do { try store.processAttempt(attempt.id) }
                        catch { store.errorMessage = error.localizedDescription }
                    }.buttonStyle(.bordered)
                }
                if attempt.transactionID == nil && attempt.status != .duplicateIgnored &&
                   attempt.status != .recurringReview && attempt.status != .rejected {
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
        case .rejected: "shield.checkered"
        case .failed, .ambiguous: "exclamationmark.triangle.fill"
        case .setupRequired, .unmatched: "wand.and.stars"
        case .captured, .ready: "bell.badge"
        }
    }

    private func color(for status: ParserAttemptStatus) -> Color {
        switch status {
        case .created, .matchedExisting: .green
        case .recurringReview: .orange
        case .rejected: .orange
        case .failed, .ambiguous: .red
        case .setupRequired, .unmatched: .orange
        case .duplicateIgnored, .captured, .ready: theme.accent
        }
    }
}

private struct SourceAccountMappingView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.easyTrackTheme) private var theme
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
                    .font(.largeTitle).foregroundStyle(theme.accent)
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
    @Environment(\.easyTrackTheme) private var theme
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
    private var competingRules: [ParserRule] {
        store.parserRules.filter { $0.sourceID == source.id && $0.enabled &&
            $0.id != draftRuleID && NotificationParser.preview(sample.event,
                config: $0.config, mappedAccount: mappedAccount).ready }
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
                    TextField("Required words or phrase", text: $config.conditionText)
                        .textInputAutocapitalization(.never)
                    Text("Choose wording that identifies this movement, such as “paid” or “received”. A shared title alone may match both formats.")
                        .font(.caption).foregroundStyle(.secondary)
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
                    Picker("Amount sign", selection: $config.requiredAmountSign) {
                        Text("Any sign").tag(AmountSign?.none)
                        ForEach(AmountSign.allCases) { sign in
                            Text(sign.title).tag(Optional(sign))
                        }
                    }
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
                    Label(testResultText,
                          systemImage: preview.ready && competingRules.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle")
                        .font(.subheadline).foregroundStyle(preview.ready && competingRules.isEmpty ? .green : .orange)
                        .accessibilityIdentifier("parserTestResult")
                }
                if let errorMessage { Text(errorMessage).font(.subheadline).foregroundStyle(.red) }
                Button(existingRule == nil ? "Activate automation" : "Save automation") {
                    if existingRule == nil { choosingFirstTransaction = true }
                    else { saveRule(createFirst: false) }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!tested || !preview.ready || !competingRules.isEmpty || saving)
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

    private var testResultText: String {
        guard preview.ready else {
            let existing = competingRules.map(\.name).joined(separator: ", ")
            return existing.isEmpty ? (preview.error ?? "This notification does not match the rule.") :
                "This draft does not match. Existing format: \(existing). \(preview.error ?? "")"
        }
        guard competingRules.isEmpty else {
            return "Also matches \(competingRules.map(\.name).joined(separator: ", ")). Refine the required wording or sign in the rules before activating."
        }
        return "Only \(name.isEmpty ? "this format" : name) matches this notification. Review the transaction below."
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
                        .foregroundStyle(index <= animatedStep ? .green : theme.accent)
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
            UINotificationFeedbackGenerator().notificationOccurred(preview.ready && competingRules.isEmpty ? .success : .warning)
        }
    }

    private func saveRule(createFirst: Bool) {
        guard tested && preview.ready && competingRules.isEmpty && !saving else { return }
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
