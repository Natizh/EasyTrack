import SwiftUI

struct CategorySuggestionsView: View {
    @EnvironmentObject private var store: FinanceStore
    let description: String
    let kind: TransactionKind
    let onSelect: (LedgerCategory) -> Void

    private var suggestions: [CategorySuggestion] {
        CategorySuggestionEngine.suggestions(description: description, kind: kind,
            categories: store.ledgerCategories, userRules: store.categoryKeywordRules,
            isEnabled: store.categorySuggestionsEnabled)
    }

    var body: some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Suggested categories").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(suggestions) { suggestion in
                    if let category = store.ledgerCategories.first(where: { $0.id == suggestion.categoryID }) {
                        Button { onSelect(category) } label: {
                            HStack {
                                Image(systemName: category.symbolName)
                                    .foregroundStyle(LedgerColor.color(category.colorName))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.name).font(.subheadline.weight(.semibold))
                                    Text("Matched “\(suggestion.matchedText)” · \(suggestion.source == .userRule ? "Your rule" : "Built in")")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Assign category")
                    }
                }
            }
        }
    }
}

struct SaveCategoryRuleView: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let description: String
    @State private var pattern: String
    @State private var categoryID: UUID
    @State private var validation: String?

    init(description: String, categoryID: UUID) {
        self.description = description
        _categoryID = State(initialValue: categoryID)
        _pattern = State(initialValue: CategorySuggestionEngine.suggestedRulePattern(from: description))
    }

    var body: some View {
        Form {
            Section {
                TextField("Word or exact phrase", text: $pattern)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("categoryRulePatternField")
                Picker("Category", selection: $categoryID) {
                    ForEach(store.ledgerCategories.filter { $0.archivedAt == nil }) {
                        Label($0.name, systemImage: $0.symbolName).tag($0.id)
                    }
                }
            } footer: {
                Text("The rule matches whole words or a contiguous phrase. It never assigns a category automatically.")
            }
            if let validation { Section { Text(validation).foregroundStyle(.red) } }
        }
        .navigationTitle("Salva questa regola")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.semibold) }
        }
    }

    private func save() {
        guard !CategorySuggestionEngine.normalized(pattern).isEmpty else {
            validation = "Enter a meaningful word or phrase."; return
        }
        let now = Date()
        do {
            _ = try store.saveCategoryKeywordRule(CategoryKeywordRule(id: UUID(), pattern: pattern,
                categoryID: categoryID, isEnabled: true, createdAt: now, updatedAt: now, revision: 0))
            dismiss()
        } catch { validation = error.localizedDescription }
    }
}

struct CategorySuggestionSettingsView: View {
    var body: some View {
        List { CategorySuggestionSections() }
            .navigationTitle("Category Suggestions")
    }
}

struct CategorySuggestionSections: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var selectedRule: CategoryKeywordRule?

    var body: some View {
        Group {
            Section {
                Toggle("Category suggestions", isOn: Binding {
                    store.categorySuggestionsEnabled
                } set: { enabled in
                    do { try store.setCategorySuggestionsEnabled(enabled) }
                    catch { store.errorMessage = error.localizedDescription }
                })
            } footer: {
                Text("Turning suggestions off keeps every personal rule and never changes saved transactions.")
            }
            Section("Personal rules") {
                if store.categoryKeywordRules.isEmpty {
                    Text("No personal rules yet.").foregroundStyle(.secondary)
                }
                ForEach(store.categoryKeywordRules) { rule in
                    Button { selectedRule = rule } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rule.pattern).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                Text(categoryLabel(rule)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !rule.isEnabled { Text("Off").font(.caption.weight(.bold)).foregroundStyle(.secondary) }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { delete(rule) }
                    }
                }
            }
        }
        .sheet(item: $selectedRule) { rule in
            NavigationStack { CategoryKeywordRuleEditor(rule: rule) }
        }
    }

    private func categoryLabel(_ rule: CategoryKeywordRule) -> String {
        guard let category = store.ledgerCategories.first(where: { $0.id == rule.categoryID }) else {
            return "Unavailable category"
        }
        return category.archivedAt == nil ? category.name : "\(category.name) · archived"
    }

    private func delete(_ rule: CategoryKeywordRule) {
        do { try store.deleteCategoryKeywordRule(rule.id) }
        catch { store.errorMessage = error.localizedDescription }
    }
}

private struct CategoryKeywordRuleEditor: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let original: CategoryKeywordRule
    @State private var pattern: String
    @State private var categoryID: UUID
    @State private var enabled: Bool
    @State private var validation: String?

    init(rule: CategoryKeywordRule) {
        original = rule
        _pattern = State(initialValue: rule.pattern)
        _categoryID = State(initialValue: rule.categoryID)
        _enabled = State(initialValue: rule.isEnabled)
    }

    var body: some View {
        Form {
            TextField("Word or exact phrase", text: $pattern)
            Picker("Category", selection: $categoryID) {
                ForEach(store.ledgerCategories.filter { $0.archivedAt == nil || $0.id == categoryID }) {
                    Text($0.archivedAt == nil ? $0.name : "\($0.name) · archived").tag($0.id)
                }
            }
            Toggle("Enabled", isOn: $enabled)
            if let validation { Text(validation).foregroundStyle(.red) }
        }
        .navigationTitle("Edit Rule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.semibold) }
        }
    }

    private func save() {
        var rule = original
        rule.pattern = pattern
        rule.categoryID = categoryID
        rule.isEnabled = enabled
        do { _ = try store.saveCategoryKeywordRule(rule); dismiss() }
        catch { validation = error.localizedDescription }
    }
}
