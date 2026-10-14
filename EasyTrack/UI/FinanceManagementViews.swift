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

struct AccountsView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var selected: LocalAccount?
    @State private var showingNew = false

    private var active: [LocalAccount] { store.localAccounts.filter { $0.archivedAt == nil } }
    private var archived: [LocalAccount] { store.localAccounts.filter { $0.archivedAt != nil } }

    var body: some View {
        List {
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

private struct AccountEditorView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let original: LocalAccount?
    @State private var name: String
    @State private var symbol: String
    @State private var color: String
    @State private var archived: Bool
    @State private var errorMessage: String?
    @State private var saving = false

    init(account: LocalAccount? = nil) {
        original = account
        _name = State(initialValue: account?.name ?? "")
        _symbol = State(initialValue: account?.symbolName ?? "creditcard.fill")
        _color = State(initialValue: account?.colorName ?? "teal")
        _archived = State(initialValue: account?.archivedAt != nil)
    }

    var body: some View {
        Form {
            Section("Account") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("accountNameField")
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
                Picker("Color", selection: $color) {
                    ForEach(LedgerAppearance.colors, id: \.self) { value in
                        Label(value.capitalized, systemImage: "circle.fill")
                            .foregroundStyle(LedgerColor.color(value)).tag(value)
                    }
                }
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
            Section {
                Text("Categories are optional. Archiving a category leaves past transactions untouched. Notification formats never assign one automatically.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
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
                Picker("Color", selection: $color) {
                    ForEach(LedgerAppearance.colors, id: \.self) { value in
                        Label(value.capitalized, systemImage: "circle.fill")
                            .foregroundStyle(LedgerColor.color(value)).tag(value)
                    }
                }
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
