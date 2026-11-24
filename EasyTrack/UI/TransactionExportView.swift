import SwiftUI
import UniformTypeIdentifiers

private extension UTType {
    static let easyTrackXLSX = UTType(filenameExtension: "xlsx") ??
        UTType(importedAs: "org.openxmlformats.spreadsheetml.sheet")
}

private struct TransactionExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .easyTrackXLSX] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct TransactionExportView: View {
    let activityFilter: TransactionFilter?

    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: TransactionExportSnapshot?
    @State private var filter = TransactionExportFilter()
    @State private var options = TransactionExportOptions()
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var endDate = Date.now
    @State private var loading = true
    @State private var working = false
    @State private var status: String?
    @State private var exportDocument: TransactionExportDocument?
    @State private var exportFilename = "EasyTrack-transactions"
    @State private var preparedFormat: TransactionExportFormat = .csv
    @State private var showingExporter = false
    @State private var workTask: Task<Void, Never>?

    private var selected: TransactionExportSelection? {
        guard let snapshot else { return nil }
        return try? snapshot.select(filter: filter, activityFilter: activityFilter, options: options)
    }

    private var selectedCount: String { selected.map { $0.rows.count.formatted() } ?? "—" }

    var body: some View {
        Form {
            Section("File") {
                Picker("Format", selection: $options.format) {
                    ForEach(TransactionExportFormat.allCases) { format in
                        Text(AppLanguage.localized(format.title)).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("transactionExportFormat")
                if options.format == .csv {
                    Picker("CSV preset", selection: $options.csvStyle) {
                        ForEach(TransactionCSVStyle.allCases) { style in
                            Text(AppLanguage.localized(style.title)).tag(style)
                        }
                    }
                    Text(AppLanguage.localized(options.csvStyle == .interoperable
                         ? "UTF-8 · comma-separated · decimal dot · ISO date with time-zone offset"
                         : "UTF-8 with BOM · semicolon-separated · decimal comma · ISO date with time-zone offset"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Dates · inclusive") {
                Picker("Period", selection: $filter.datePreset) {
                    ForEach(TransactionExportDatePreset.allCases) { preset in
                        Text(AppLanguage.localized(preset.title)).tag(preset)
                    }
                }
                .onChange(of: filter.datePreset) { _, value in
                    if value == .custom { updateCustomDates() }
                }
                if filter.datePreset == .custom {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                        .onChange(of: startDate) { _, _ in updateCustomDates() }
                    DatePicker("End", selection: $endDate, displayedComponents: .date)
                        .onChange(of: endDate) { _, _ in updateCustomDates() }
                    if let start = filter.customStart, let end = filter.customEnd, start > end {
                        Text("Start must be on or before End.")
                            .font(.footnote).foregroundStyle(.red)
                    }
                }
            }

            Section("Filters") {
                TextField("Description, note or payee", text: $filter.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("transactionExportSearch")
                if let snapshot {
                    filterLink("Accounts", choices: snapshot.accountChoices, selection: $filter.accountKeys)
                    filterLink("Categories", choices: snapshot.categoryChoices, selection: $filter.categoryKeys)
                    filterLink("Kinds", choices: snapshot.kindChoices, selection: $filter.kindKeys)
                    filterLink("Trips", choices: snapshot.tripChoices, selection: $filter.tripKeys)
                    filterLink("Currencies", choices: snapshot.currencyChoices, selection: $filter.currencyKeys)
                }
                if activityFilter != nil {
                    Text("Current Activity filters also apply. Export filters narrow those results; conflicting filters produce an empty export.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Columns") {
                Picker("Detail", selection: $options.columns) {
                    ForEach(TransactionExportColumns.allCases) { value in
                        Text(AppLanguage.localized(value.title)).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Include source and technical IDs", isOn: $options.includeTechnicalIDs)
                if options.format == .xlsx {
                    Toggle("Include Riepilogo summary sheet", isOn: $options.includeSummary)
                }
                Text("Kind and current amount stay separate. Signed directional EUR is an additional column. Detailed adds imported source values where available.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Preview") {
                if loading { ProgressView("Reading a consistent ledger snapshot…") }
                else if let snapshot {
                    LabeledContent("Transactions", value: selectedCount)
                        .accessibilityIdentifier("transactionExportCount")
                    if let selected {
                        if selected.rows.isEmpty {
                            Text("No matching transactions. You can still save a header-only file.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            ForEach(selected.rows.prefix(3), id: \.item.id) { row in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(row.item.merchant).lineLimit(2)
                                        Text(AppLanguage.localized(row.item.kind.title)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let eur = row.currentEURMinor {
                                        Text(Money.format(eur)).monospacedDigit()
                                    } else { Text("EUR unavailable").font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    } else {
                        Text("Check the date range and filters.").foregroundStyle(.red)
                    }
                    Text("\(snapshot.exportableTransactions.count) non-Demo, non-deleted transactions available before filters.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                if working { ProgressView("Creating export…") }
                Button("Save \(AppLanguage.localized(options.format.title)) in Files") { createExport() }
                    .disabled(loading || working || selected == nil)
                    .accessibilityIdentifier("saveTransactionExport")
                if working {
                    Button("Cancel export", role: .cancel) {
                        workTask?.cancel()
                        status = "Export cancelled."
                    }
                }
                if let status {
                    Text(AppLanguage.localized(status)).font(.footnote).accessibilityIdentifier("transactionExportStatus")
                }
            }
        }
        .navigationTitle("Export transactions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        .task { loadSnapshot() }
        .onDisappear { workTask?.cancel() }
        .fileExporter(isPresented: $showingExporter, document: exportDocument,
                      contentType: preparedFormat == .csv ? .commaSeparatedText : .easyTrackXLSX,
                      defaultFilename: exportFilename) { result in
            switch result {
            case .success(let url): status = AppLanguage.formatted("Saved %@", url.lastPathComponent)
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { status = error.localizedDescription }
            }
        }
    }

    private func filterLink(_ title: String, choices: [TransactionExportChoice],
                            selection: Binding<Set<String>?>) -> some View {
        NavigationLink {
            TransactionExportMultiSelect(title: title, choices: choices, selection: selection)
        } label: {
            LabeledContent(AppLanguage.localized(title), value: selection.wrappedValue.map {
                AppLanguage.formatted("%@ selected", String($0.count))
            } ?? AppLanguage.localized("All"))
        }
    }

    private func updateCustomDates() {
        guard let zone = TimeZone(identifier: options.timeZoneIdentifier) else { return }
        filter.customStart = LocalDay(date: startDate, timeZone: zone)
        filter.customEnd = LocalDay(date: endDate, timeZone: zone)
    }

    private func loadSnapshot() {
        guard snapshot == nil else { return }
        loading = true
        Task {
            do { snapshot = try await TransactionExportService.shared.snapshot() }
            catch { status = error.localizedDescription }
            loading = false
        }
    }

    private func createExport() {
        guard let selected else { return }
        let chosenOptions = options
        working = true
        status = nil
        workTask = Task {
            do {
                let bytes = try await TransactionExportService.shared.render(selected, options: chosenOptions)
                try Task.checkCancellation()
                exportDocument = TransactionExportDocument(data: bytes)
                preparedFormat = chosenOptions.format
                exportFilename = "EasyTrack-transactions-\(Int(Date().timeIntervalSince1970))"
                showingExporter = true
            } catch is CancellationError { status = "Export cancelled." }
            catch { status = error.localizedDescription }
            working = false
            workTask = nil
        }
    }
}

private struct TransactionExportMultiSelect: View {
    let title: String
    let choices: [TransactionExportChoice]
    @Binding var selection: Set<String>?

    var body: some View {
        List {
            Button {
                selection = nil
            } label: {
                HStack {
                    Text(AppLanguage.formatted("All %@", AppLanguage.localized(title)))
                    Spacer()
                    if selection == nil { Image(systemName: "checkmark").accessibilityHidden(true) }
                }
            }
            .accessibilityValue(selection == nil ? "Selected" : "Not selected")
            ForEach(choices) { choice in
                Button {
                    var values = selection ?? []
                    if values.contains(choice.id) { values.remove(choice.id) }
                    else { values.insert(choice.id) }
                    selection = values
                } label: {
                    HStack {
                        Text(title == "Kinds" ? AppLanguage.localized(choice.title) : choice.title)
                        Spacer()
                        if selection?.contains(choice.id) == true {
                            Image(systemName: "checkmark").accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityValue(selection?.contains(choice.id) == true ? "Selected" : "Not selected")
                .accessibilityIdentifier("transactionExportFilter-\(choice.id)")
            }
        }
        .navigationTitle(AppLanguage.localized(title))
    }
}
