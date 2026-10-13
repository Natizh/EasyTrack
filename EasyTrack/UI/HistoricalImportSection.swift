import SwiftUI
import UniformTypeIdentifiers

struct HistoricalImportSection: View {
    @EnvironmentObject private var store: FinanceStore
    @Binding var selectedFile: URL?
    let chooseFile: () -> Void
    @State private var busy = false
    @State private var preview: HistoricalImportPreview?
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
                    if !preview.canImport {
                        Text("This seed differs from previously imported source data. No changes will be made.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)
                Button(preview.newMovements == 0 ? "Confirm no changes" : "Import \(preview.newMovements) movements") {
                    confirm()
                }
                .disabled(busy || !preview.canImport)
                Button("Discard preview", role: .cancel) {
                    self.preview = nil
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

    private func stage(_ url: URL) {
        busy = true
        status = "Validating selected seed…"
        preview = nil
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
                let result = try await SeedImportCoordinator.shared.confirm()
                store.reload()
                preview = nil
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
