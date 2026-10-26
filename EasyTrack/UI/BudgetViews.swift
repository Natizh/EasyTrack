import SwiftUI

struct BudgetHomeWidget: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.easyTrackTheme) private var theme
    let financial: FinancialAnalyticsSnapshot?

    private var budgetSnapshot: MonthlyBudgetSnapshot? {
        guard let financial else { return nil }
        return try? BudgetAnalytics.snapshot(financial: financial,
            budgets: store.monthlyBudgets, categories: store.ledgerCategories)
    }
    private var activeGoal: SavingsGoal? {
        store.savingsGoals.first { $0.archivedAt == nil }
    }

    var body: some View {
        DashboardModuleCard {
            NavigationLink { BudgetsAndGoalsView() } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Budgets & goals", systemImage: "target")
                            .font(.title3.bold()).foregroundStyle(theme.primaryText)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    if let progress = budgetSnapshot?.overall {
                        BudgetProgressContent(progress: progress)
                    } else if let progress = budgetSnapshot?.categories.first {
                        BudgetProgressContent(progress: progress)
                    } else if let goal = activeGoal {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(goal.name).font(.subheadline.weight(.semibold))
                            ProgressView(value: min(Double(goal.progressEURMinor) /
                                max(Double(goal.targetEURMinor), 1), 1))
                            Text("Manual progress \(Money.format(goal.progressEURMinor)) of \(Money.format(goal.targetEURMinor))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No budget or savings goal configured.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let count = budgetSnapshot?.missingConversionCount, count > 0 {
                        Label("\(count) movement(s) lack verified EUR coverage",
                              systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityIdentifier("homeBudgetsGoalsWidget")
    }
}

private struct BudgetProgressContent: View {
    @Environment(\.easyTrackTheme) private var theme
    let progress: BudgetProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(progress.title).font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: progress.isOverLimit ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .foregroundStyle(progress.isOverLimit ? theme.coral : theme.accent)
                    .accessibilityHidden(true)
            }
            ProgressView(value: min(max(Double(progress.spentEURMinor) /
                max(Double(progress.budget.limitEURMinor), 1), 0), 1))
                .tint(progress.isOverLimit ? theme.coral : theme.accent)
            Text(progress.isOverLimit
                 ? "Over by \(Money.format(-progress.remainingEURMinor))"
                 : "Remaining \(Money.format(progress.remainingEURMinor))")
                .font(.caption.weight(.semibold)).monospacedDigit()
            Text("Spent \(Money.format(progress.spentEURMinor)) of \(Money.format(progress.budget.limitEURMinor)) · no rollover")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

struct BudgetsAndGoalsView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var selectedBudget: MonthlyBudget?
    @State private var selectedGoal: SavingsGoal?
    @State private var newBudgetScope: MonthlyBudgetScope?
    @State private var showingNewGoal = false

    private var activeBudgets: [MonthlyBudget] { store.monthlyBudgets.filter { $0.archivedAt == nil } }
    private var archivedBudgets: [MonthlyBudget] { store.monthlyBudgets.filter { $0.archivedAt != nil } }
    private var activeGoals: [SavingsGoal] { store.savingsGoals.filter { $0.archivedAt == nil } }
    private var archivedGoals: [SavingsGoal] { store.savingsGoals.filter { $0.archivedAt != nil } }

    var body: some View {
        List {
            Section("Monthly budgets") {
                if activeBudgets.isEmpty { Text("No monthly budget configured.").foregroundStyle(.secondary) }
                ForEach(activeBudgets) { budget in budgetRow(budget) }
            }
            if !archivedBudgets.isEmpty {
                Section("Archived budgets") { ForEach(archivedBudgets) { budget in budgetRow(budget) } }
            }
            Section("Manual savings goals") {
                if activeGoals.isEmpty { Text("No savings goal configured.").foregroundStyle(.secondary) }
                ForEach(activeGoals) { goal in goalRow(goal) }
            }
            if !archivedGoals.isEmpty {
                Section("Archived goals") { ForEach(archivedGoals) { goal in goalRow(goal) } }
            }
            Section {
                Text("Budgets reset each calendar month with no rollover. Goal progress is manual and is not a bank balance or investment value.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Budgets & Goals")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Overall monthly budget") { newBudgetScope = .overall }
                    Button("Category monthly budget") { newBudgetScope = .category }
                    Button("Savings goal") { showingNewGoal = true }
                } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add budget or goal")
            }
        }
        .sheet(item: $selectedBudget) { budget in NavigationStack { MonthlyBudgetEditor(budget: budget) } }
        .sheet(item: $selectedGoal) { goal in NavigationStack { SavingsGoalEditor(goal: goal) } }
        .sheet(item: $newBudgetScope) { scope in NavigationStack { MonthlyBudgetEditor(scope: scope) } }
        .sheet(isPresented: $showingNewGoal) { NavigationStack { SavingsGoalEditor() } }
    }

    private func budgetRow(_ budget: MonthlyBudget) -> some View {
        Button { selectedBudget = budget } label: {
            LabeledContent(budgetTitle(budget), value: Money.format(budget.limitEURMinor))
                .foregroundStyle(.primary).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func goalRow(_ goal: SavingsGoal) -> some View {
        Button { selectedGoal = goal } label: {
            VStack(alignment: .leading, spacing: 5) {
                LabeledContent(goal.name, value: "\(Money.format(goal.progressEURMinor)) / \(Money.format(goal.targetEURMinor))")
                if let dueDate = goal.dueDate { Text("Due \(dueDate.isoString)").font(.caption).foregroundStyle(.secondary) }
            }.foregroundStyle(.primary).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func budgetTitle(_ budget: MonthlyBudget) -> String {
        guard budget.scope == .category else { return "Overall" }
        return budget.categoryID.flatMap { id in store.ledgerCategories.first { $0.id == id }?.name }
            ?? "Unavailable category"
    }
}

private struct MonthlyBudgetEditor: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let original: MonthlyBudget?
    @State private var scope: MonthlyBudgetScope
    @State private var categoryID: UUID?
    @State private var amount: String
    @State private var validation: String?

    init(budget: MonthlyBudget? = nil, scope: MonthlyBudgetScope = .overall) {
        original = budget
        _scope = State(initialValue: budget?.scope ?? scope)
        _categoryID = State(initialValue: budget?.categoryID)
        _amount = State(initialValue: budget.map { Money.editString($0.limitEURMinor) } ?? "")
    }

    var body: some View {
        Form {
            Picker("Budget", selection: $scope) {
                ForEach(MonthlyBudgetScope.allCases) { Text($0.title).tag($0) }
            }.disabled(original != nil)
            if scope == .category {
                Picker("Category", selection: $categoryID) {
                    Text("Choose category").tag(UUID?.none)
                    ForEach(store.ledgerCategories.filter { $0.archivedAt == nil || $0.id == categoryID }) {
                        Text($0.archivedAt == nil ? $0.name : "\($0.name) · archived").tag(Optional($0.id))
                    }
                }
            }
            LabeledContent("Monthly limit (EUR)") {
                TextField("0,00", text: $amount).keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
            }
            Text("The full limit applies to the calendar month. It is not prorated and unused amounts never roll over.")
                .font(.footnote).foregroundStyle(.secondary)
            if let validation { Text(validation).foregroundStyle(.red) }
            if original != nil {
                Button(original?.archivedAt == nil ? "Archive budget" : "Restore budget",
                       role: original?.archivedAt == nil ? .destructive : nil) { archiveOrRestore() }
            }
        }
        .navigationTitle(original == nil ? "New Budget" : "Edit Budget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.semibold) }
        }
    }

    private func save() {
        let cents: Int64
        switch Money.validatedPositiveAmount(amount) {
        case .success(let value): cents = value
        case .failure(let error): validation = error.message; return
        }
        guard scope == .overall || categoryID != nil else { validation = "Choose a category."; return }
        let now = Date()
        var budget = original ?? MonthlyBudget(id: UUID(), scope: scope,
            categoryID: scope == .category ? categoryID : nil, limitEURMinor: cents,
            createdAt: now, updatedAt: now, archivedAt: nil, revision: 0)
        budget.limitEURMinor = cents
        budget.categoryID = scope == .category ? categoryID : nil
        do { _ = try store.saveMonthlyBudget(budget); dismiss() }
        catch { validation = error.localizedDescription }
    }

    private func archiveOrRestore() {
        guard var budget = original else { return }
        budget.archivedAt = budget.archivedAt == nil ? .now : nil
        do { _ = try store.saveMonthlyBudget(budget); dismiss() }
        catch { validation = error.localizedDescription }
    }
}

private struct SavingsGoalEditor: View {
    @EnvironmentObject private var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    let original: SavingsGoal?
    @State private var name: String
    @State private var target: String
    @State private var progress: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var validation: String?

    init(goal: SavingsGoal? = nil) {
        original = goal
        _name = State(initialValue: goal?.name ?? "")
        _target = State(initialValue: goal.map { Money.editString($0.targetEURMinor) } ?? "")
        _progress = State(initialValue: goal.map { Money.editString($0.progressEURMinor) } ?? "0,00")
        _hasDueDate = State(initialValue: goal?.dueDate != nil)
        _dueDate = State(initialValue: goal?.dueDate?.noon(in: .current) ?? .now)
    }

    var body: some View {
        Form {
            TextField("Goal name", text: $name)
            LabeledContent("Target (EUR)") { TextField("0,00", text: $target).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing) }
            LabeledContent("Manual progress (EUR)") { TextField("0,00", text: $progress).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing) }
            Toggle("Due date", isOn: $hasDueDate)
            if hasDueDate { DatePicker("Due", selection: $dueDate, displayedComponents: .date) }
            Text("Progress is entered manually and does not represent a bank balance.")
                .font(.footnote).foregroundStyle(.secondary)
            if let validation { Text(validation).foregroundStyle(.red) }
            if original != nil {
                Button(original?.archivedAt == nil ? "Archive goal" : "Restore goal",
                       role: original?.archivedAt == nil ? .destructive : nil) { archiveOrRestore() }
            }
        }
        .navigationTitle(original == nil ? "New Savings Goal" : "Edit Savings Goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.semibold) }
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { validation = "Enter a name."; return }
        guard case .success(let targetMinor) = Money.validatedPositiveAmount(target) else { validation = "Enter a positive target."; return }
        guard let progressMinor = Money.parseMinor(progress), progressMinor >= 0 else { validation = "Enter valid manual progress."; return }
        let now = Date()
        var goal = original ?? SavingsGoal(id: UUID(), name: name,
            targetEURMinor: targetMinor, progressEURMinor: progressMinor, dueDate: nil,
            createdAt: now, updatedAt: now, archivedAt: nil, revision: 0)
        goal.name = name
        goal.targetEURMinor = targetMinor
        goal.progressEURMinor = progressMinor
        goal.dueDate = hasDueDate ? LocalDay(date: dueDate, timeZone: .current) : nil
        do { _ = try store.saveSavingsGoal(goal); dismiss() }
        catch { validation = error.localizedDescription }
    }

    private func archiveOrRestore() {
        guard var goal = original else { return }
        goal.archivedAt = goal.archivedAt == nil ? .now : nil
        do { _ = try store.saveSavingsGoal(goal); dismiss() }
        catch { validation = error.localizedDescription }
    }
}
