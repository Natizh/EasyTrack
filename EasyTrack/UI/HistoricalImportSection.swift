import SwiftUI
import UniformTypeIdentifiers

struct HistoricalImportSection: View {
    @EnvironmentObject private var store: FinanceStore
    @Binding var selectedFile: URL?
    let chooseFile: () -> Void
    @State private var busy = false
    @State private var preview: HistoricalImportPreview?
    @State private var decisions: [String: HistoricalImportDecision] = [:]
    @State private var status: String?

    var body: some View {
        Section("Historical import") {
            Text("Choose the external SQLite seed in Files. EasyTrack validates a temporary copy before showing counts; the live database changes only when you confirm.")
                .font(.footnote).foregroundStyle(.secondary)
            if store.hasHistoricalImport {
                Label("\(store.historicalCounts["historical_imported_movements"] ?? 0) historical movements imported", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Button(busy ? "Working…" : "Choose SQLite seed", action: chooseFile)
                .disabled(busy)
            if let preview {
                VStack(alignment: .leading, spacing: 7) {
                    count("Movements", preview.movements)
                    count("New movements", preview.newMovements)
                    count("Already imported", preview.alreadyImported)
                    count("Changed source rows", preview.changedIdentities)
                    count("Missing from this file", preview.missingFromSource)
                    count("Accounts", preview.accounts)
                    count("Trips", preview.trips)
                    count("Recurring rules", preview.recurringRules)
                    count("Exchange rates", preview.exchangeRates)
                    Text("\(preview.migrationWarnings) legacy warnings are preserved as import metadata.")
                        .font(.caption).foregroundStyle(.secondary)
                    if preview.unmatchedAccountLabels > 0 {
                        Text("\(preview.unmatchedAccountLabels) movement account labels do not match a master account. Their original labels will be kept.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if preview.missingAccountLabels > 0 {
                        Text("\(preview.missingAccountLabels) movements have no account label. They remain editable.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if preview.sourceChanged {
                        Text("The source file changed. Stable row identities are compared individually; missing rows are never deleted.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !preview.rowConflicts.isEmpty {
                        Divider()
                        Text("Changed imported rows · \(preview.rowConflicts.count)").font(.headline)
                        Text("Keep the EasyTrack version or explicitly apply source changes only when the movement was not edited, deleted, notified, or linked to a recurrence.")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(preview.rowConflicts) { conflict in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(conflict.imported.merchant).font(.subheadline.bold())
                                if conflict.localEdited {
                                    Text("Protected: this movement was edited in EasyTrack.").foregroundStyle(.orange)
                                }
                                if let reason = conflict.protectedReason {
                                    Text("Protected: \(reason)").foregroundStyle(.orange)
                                }
                                Menu(decisionTitle(conflict.id)) {
                                    Button("Keep EasyTrack version") { decisions[conflict.id] = .keepLocal }
                                    Button("Apply source version") { decisions[conflict.id] = .applySource }
                                        .disabled(!conflict.canApplySource)
                                }
                            }
                            .font(.caption).padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    if !preview.duplicateCandidates.isEmpty {
                        Divider()
                        Text("Possible existing duplicates · \(preview.duplicateCandidates.count)").font(.headline)
                        Text("EasyTrack never merges these automatically. Choose whether each incoming row is a separate movement or should be skipped.")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(preview.duplicateCandidates) { candidate in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(candidate.imported.merchant).font(.subheadline.bold())
                                Text("\(candidate.existing.count) similar local movement(s) found.")
                                Menu(decisionTitle(candidate.id)) {
                                    Button("Import separately") { decisions[candidate.id] = .importSeparately }
                                    Button("Skip incoming row") { decisions[candidate.id] = .skipIncoming }
                                }
                            }
                            .font(.caption).padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    if !preview.recurringConflicts.isEmpty {
                        Divider()
                        Text("Recurring overlaps · \(preview.recurringConflicts.count)").font(.headline)
                        Text("Review all possible overlaps together. Each needs a decision before one atomic import. Historical account labels are not trusted automatically.")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(preview.recurringConflicts) { conflict in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(conflict.ruleName).font(.subheadline.bold())
                                Text("Recorded: \(conflict.counted.merchant) · \(Money.format(conflict.counted.eurMinor ?? conflict.counted.amountMinor)) · \(conflict.counted.occurredAt.formatted(date: .abbreviated, time: .omitted))")
                                Text("Import: \(conflict.imported.merchant) · \(Money.format(conflict.imported.eurMinor ?? conflict.imported.amountMinor)) · \(conflict.imported.occurredAt.formatted(date: .abbreviated, time: .omitted))")
                                Text("\(conflict.imported.kind.title) · \(conflict.managedAccountName) ↔ \(conflict.imported.account.isEmpty ? "No source account" : conflict.imported.account)")
                                Text(conflict.reason).foregroundStyle(.secondary)
                                Menu(decisionTitle(conflict.id)) {
                                    Button("Same payment") { decisions[conflict.id] = .samePayment }
                                    Button("Separate payment") { decisions[conflict.id] = .separatePayment }
                                }
                                .accessibilityLabel("Decision for \(conflict.ruleName), \(conflict.imported.merchant)")
                                .accessibilityIdentifier("recurringConflictDecision-\(conflict.id)")
                            }
                            .font(.caption)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 10))
                        }
                        Text("\(unresolvedCount(preview)) unresolved · \(sameCount(preview)) same payment · \(separateCount(preview)) separate")
                            .font(.footnote.bold())
                        if hasAmbiguousSame(preview) {
                            Text("One real payment or recurring date was selected more than once. Choose one Same payment and mark the others Separate payment.")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                        if unresolvedCount(preview) == 0 && !hasAmbiguousSame(preview),
                           let incoming = preview.incomingTotals {
                            let removed = LedgerTotals(transactions: preview.recurringConflicts
                                .filter { decisions[$0.id] == .samePayment }.map(\.counted))
                            Text("Summary: \(preview.newMovements) imported, \(sameCount(preview)) provisional records replaced. Personal spending change: \(Money.format(incoming.personalSpendingEURMinor - removed.personalSpendingEURMinor)). Expense change: \(Money.format(incoming.totalExpensesEURMinor - removed.totalExpensesEURMinor)). Income change: \(Money.format(incoming.incomeEURMinor - removed.incomeEURMinor)). PAC change: \(Money.format(incoming.pacInvestedEURMinor - removed.pacInvestedEURMinor)).")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
                Button(preview.newMovements == 0 ? "Confirm no changes" : "Import \(preview.newMovements) movements") {
                    confirm()
                }
                .disabled(busy || unresolvedCount(preview) > 0 || hasAmbiguousSame(preview))
                Button("Discard preview", role: .cancel) {
                    self.preview = nil
                    decisions = [:]
                    Task { await SeedImportCoordinator.shared.cancel() }
                }
            }
            if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
        }
        .onChange(of: selectedFile) { _, url in
            if let url {
                selectedFile = nil
                stage(url)
            }
        }
    }

    private func count(_ label: String, _ value: Int) -> some View {
        HStack { Text(label); Spacer(); Text(value.formatted()).monospacedDigit() }
            .font(.subheadline)
    }

    private func decisionTitle(_ id: String) -> String {
        switch decisions[id] {
        case .samePayment: "Same payment"
        case .separatePayment: "Separate payment"
        case .keepLocal: "Keep EasyTrack version"
        case .applySource: "Apply source version"
        case .importSeparately: "Import separately"
        case .skipIncoming: "Skip incoming row"
        case nil: "Choose same or separate"
        }
    }

    private func unresolvedCount(_ preview: HistoricalImportPreview) -> Int {
        let ids = preview.recurringConflicts.map(\.id) + preview.rowConflicts.map(\.id) +
            preview.duplicateCandidates.map(\.id)
        return ids.filter { decisions[$0] == nil }.count
    }

    private func sameCount(_ preview: HistoricalImportPreview) -> Int {
        preview.recurringConflicts.filter { decisions[$0.id] == .samePayment }.count
    }

    private func separateCount(_ preview: HistoricalImportPreview) -> Int {
        preview.recurringConflicts.filter { decisions[$0.id] == .separatePayment }.count
    }

    private func hasAmbiguousSame(_ preview: HistoricalImportPreview) -> Bool {
        let same = preview.recurringConflicts.filter { decisions[$0.id] == .samePayment }
        return Set(same.map(\.occurrenceID)).count != same.count ||
            Set(same.map { $0.imported.id }).count != same.count
    }

    private func stage(_ url: URL) {
        busy = true
        status = "Validating selected seed…"
        preview = nil
        decisions = [:]
        Task {
            do {
                preview = try await SeedImportCoordinator.shared.stage(url)
                status = "Ready to import. Existing data remains untouched until confirmation."
            } catch { status = error.localizedDescription }
            busy = false
        }
    }

    private func confirm() {
        busy = true
        status = "Importing into local storage…"
        Task {
            do {
                let result = try await SeedImportCoordinator.shared.confirm(decisions: decisions)
                store.reload()
                preview = nil
                decisions = [:]
                status = result.newMovements == 0 ? "No new movements; local data was unchanged." : "Imported \(result.newMovements) movements into local storage."
            } catch { status = error.localizedDescription }
            busy = false
        }
    }
}

struct HistoricalReferenceSection: View {
    @EnvironmentObject private var store: FinanceStore

    var body: some View {
        if store.hasHistoricalImport {
            Section("Imported reference data") {
                NavigationLink("Accounts · \(store.historicalAccounts.count)") {
                    List(store.historicalAccounts) { account in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.sourceName).font(.headline)
                            Text([account.kind, account.currency].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.navigationTitle("Accounts")
                }
                NavigationLink("Trips · \(store.historicalTrips.count)") {
                    List(store.historicalTrips) { trip in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(trip.name).font(.headline)
                            if let destination = trip.destination { Text(destination).font(.caption).foregroundStyle(.secondary) }
                        }
                    }.navigationTitle("Trips")
                }
                NavigationLink("Recurring rules · \(store.historicalRules.count)") {
                    List(store.historicalRules) { rule in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rule.name).font(.headline)
                            Text("\(rule.ruleKind == "investment" ? "Investment plan" : "Subscription") · \(rule.frequency ?? "Schedule unspecified")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("Recurring rules")
                    .safeAreaInset(edge: .bottom) {
                        Text("Rules are definitions only. No expected occurrences or duplicate transactions were generated.")
                            .font(.caption).padding().frame(maxWidth: .infinity)
                            .background(.regularMaterial)
                    }
                }
            }
        }
    }
}
