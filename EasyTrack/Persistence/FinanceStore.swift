import Foundation

@MainActor
final class FinanceStore: ObservableObject {
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var events: [NotificationEvent] = []
    @Published private(set) var parserSources: [ParserSource] = []
    @Published private(set) var localAccounts: [LocalAccount] = []
    @Published private(set) var ledgerCategories: [LedgerCategory] = []
    @Published private(set) var recurringRules: [RecurringRule] = []
    @Published private(set) var recurringOccurrences: [RecurringOccurrence] = []
    @Published private(set) var recurringCandidates: [RecurringCandidate] = []
    @Published private(set) var parserRules: [ParserRule] = []
    @Published private(set) var parserAttempts: [ParserAttempt] = []
    @Published private(set) var historicalCounts: [String: Int] = [:]
    @Published private(set) var historicalAccounts: [HistoricalAccount] = []
    @Published private(set) var historicalTrips: [HistoricalTrip] = []
    @Published private(set) var historicalRules: [HistoricalRecurringRule] = []
    @Published private(set) var dashboardWidgetPreferences: [DashboardWidgetPreference] = []
    @Published private(set) var dashboardHeroPreferences = DashboardHeroPreferences.default
    @Published private(set) var merchantAliasGroups: [MerchantAliasGroup] = []
    @Published private(set) var reimbursementStatuses: [ExpenseReimbursementStatus] = []
    @Published private(set) var categoryKeywordRules: [CategoryKeywordRule] = []
    @Published private(set) var categorySuggestionsEnabled = true
    @Published private(set) var monthlyBudgets: [MonthlyBudget] = []
    @Published private(set) var savingsGoals: [SavingsGoal] = []
    @Published private(set) var notificationRetentionDays = NotificationRetentionPolicy.defaultDays
    @Published private(set) var automationSetupMilestones: Set<AutomationSetupMilestone> = []
    @Published private(set) var appearancePreferences = AppearancePreferences.default
    @Published private(set) var backupReminderPreferences = BackupReminderPreferences.default
    @Published private(set) var defaultExpenseAccountID: UUID?
    @Published private(set) var shouldPresentOnboarding = false
    @Published var errorMessage: String?

    init() {
        do {
            let database = try SQLiteDatabase.open()
            try database.prepareProductionLedger()
            _ = try database.materializeDueRecurring()
            _ = try database.purgeExpiredNotificationContents()
        }
        catch { errorMessage = error.localizedDescription }
        reload()
    }

    func refreshOnForeground() {
        do {
            let database = try SQLiteDatabase.open()
            _ = try database.materializeDueRecurring()
            _ = try database.purgeExpiredNotificationContents()
        }
        catch { errorMessage = error.localizedDescription }
        reload()
    }

    func reload() {
        do {
            let database = try SQLiteDatabase.open()
            transactions = try database.transactions()
            events = try database.notificationEvents()
            parserSources = try database.parserSources()
            localAccounts = try database.localAccounts()
            ledgerCategories = try database.ledgerCategories()
            recurringRules = try database.recurringRules(includeArchived: true)
            recurringOccurrences = try database.recurringOccurrences()
            recurringCandidates = try database.recurringCandidates()
            parserRules = try database.parserRules()
            parserAttempts = try database.parserAttempts()
            historicalCounts = try database.historicalCounts()
            historicalAccounts = try database.historicalAccounts()
            historicalTrips = try database.historicalTrips()
            historicalRules = try database.historicalRules()
            dashboardWidgetPreferences = try database.dashboardWidgetPreferences()
            dashboardHeroPreferences = try database.dashboardHeroPreferences()
            merchantAliasGroups = try database.merchantAliasGroups()
            reimbursementStatuses = try database.reimbursementStatuses()
            categoryKeywordRules = try database.categoryKeywordRules()
            categorySuggestionsEnabled = try database.categorySuggestionsEnabled()
            monthlyBudgets = try database.monthlyBudgets()
            savingsGoals = try database.savingsGoals()
            notificationRetentionDays = try database.notificationRetentionDays()
            automationSetupMilestones = try database.automationSetupMilestones()
            appearancePreferences = try database.appearancePreferences()
            backupReminderPreferences = try database.backupReminderPreferences()
            defaultExpenseAccountID = try database.defaultExpenseAccountID()
            shouldPresentOnboarding = try database.shouldPresentOnboarding()
        } catch { errorMessage = error.localizedDescription }
    }

    @discardableResult func save(_ item: Transaction) throws -> Transaction {
        let persisted = try SQLiteDatabase.open().save(item)
        reload()
        return persisted
    }

    @discardableResult
    func save(_ item: Transaction, expectedReimbursementEURMinor: Int64?) throws -> Transaction {
        let persisted = try SQLiteDatabase.open().save(item,
            expectedReimbursementEURMinor: expectedReimbursementEURMinor)
        reload()
        return persisted
    }

    func linkReimbursement(expenseID: UUID, reimbursementID: UUID) throws {
        try SQLiteDatabase.open().linkReimbursement(expenseID: expenseID,
                                                    reimbursementID: reimbursementID)
        reload()
    }

    @discardableResult
    func createAndLinkReimbursement(expenseID: UUID, reimbursement: Transaction) throws -> Transaction {
        let result = try SQLiteDatabase.open().createAndLinkReimbursement(
            expenseID: expenseID, reimbursement: reimbursement)
        reload()
        return result
    }

    func unlinkReimbursement(_ reimbursementID: UUID) throws {
        try SQLiteDatabase.open().unlinkReimbursement(reimbursementID)
        reload()
    }

    func writeOffOutstandingReimbursement(_ expenseID: UUID) throws {
        try SQLiteDatabase.open().writeOffOutstandingReimbursement(expenseID)
        reload()
    }

    func undoReimbursementWriteOff(_ expenseID: UUID) throws {
        try SQLiteDatabase.open().undoReimbursementWriteOff(expenseID)
        reload()
    }

    func delete(_ item: Transaction) throws {
        var deleted = item
        deleted.deletedAt = .now
        try save(deleted)
    }

    @discardableResult func saveAccount(_ account: LocalAccount) throws -> LocalAccount {
        let saved = try SQLiteDatabase.open().saveLocalAccount(account)
        reload()
        return saved
    }

    func setDefaultExpenseAccountID(_ id: UUID?) throws {
        try SQLiteDatabase.open().setDefaultExpenseAccountID(id)
        reload()
    }

    @discardableResult func saveTrip(id: String? = nil, name: String) throws -> HistoricalTrip {
        let saved = try SQLiteDatabase.open().saveTrip(id: id, name: name)
        reload()
        return saved
    }

    @discardableResult func saveCategory(_ category: LedgerCategory) throws -> LedgerCategory {
        let saved = try SQLiteDatabase.open().saveLedgerCategory(category)
        reload()
        return saved
    }

    func swapCategoryOrder(_ first: LedgerCategory, _ second: LedgerCategory) throws {
        try SQLiteDatabase.open().swapCategoryOrder(first, second)
        reload()
    }

    func saveDashboardWidgetPreferences(_ knownPreferences: [DashboardWidgetPreference]) throws {
        let incoming = Set(knownPreferences.map(\.widgetID))
        let unknown = dashboardWidgetPreferences.filter { !incoming.contains($0.widgetID) }
        let combined = knownPreferences.enumerated().map { index, item in
            DashboardWidgetPreference(widgetID: item.widgetID, position: index,
                                      isVisible: item.isVisible, updatedAt: item.updatedAt)
        } + unknown.enumerated().map { offset, item in
            DashboardWidgetPreference(widgetID: item.widgetID,
                                      position: knownPreferences.count + offset,
                                      isVisible: item.isVisible, updatedAt: item.updatedAt)
        }
        try SQLiteDatabase.open().saveDashboardWidgetPreferences(combined)
        reload()
    }

    func resetDashboardWidgetPreferences() throws {
        try SQLiteDatabase.open().resetDashboardWidgetPreferences()
        reload()
    }

    func saveDashboardHeroPreferences(_ preferences: DashboardHeroPreferences) throws {
        try SQLiteDatabase.open().saveDashboardHeroPreferences(preferences)
        dashboardHeroPreferences = preferences.resolved
    }

    func saveMerchantAliasGroup(_ group: MerchantAliasGroup) throws {
        try SQLiteDatabase.open().saveMerchantAliasGroup(group)
        reload()
    }

    func deleteMerchantAliasGroup(_ id: UUID) throws {
        try SQLiteDatabase.open().deleteMerchantAliasGroup(id)
        reload()
    }

    func setCategorySuggestionsEnabled(_ enabled: Bool) throws {
        try SQLiteDatabase.open().setCategorySuggestionsEnabled(enabled)
        reload()
    }

    @discardableResult
    func saveCategoryKeywordRule(_ rule: CategoryKeywordRule) throws -> CategoryKeywordRule {
        let saved = try SQLiteDatabase.open().saveCategoryKeywordRule(rule)
        reload()
        return saved
    }

    func deleteCategoryKeywordRule(_ id: UUID) throws {
        try SQLiteDatabase.open().deleteCategoryKeywordRule(id)
        reload()
    }

    @discardableResult
    func assignCategory(_ category: LedgerCategory?, to transactionIDs: Set<UUID>) throws -> [Transaction] {
        let selected = transactions.filter { transactionIDs.contains($0.id) }
        guard selected.count == transactionIDs.count else { throw DailyValidationError.staleRecord }
        let changes = selected.map { TransactionCategoryChange(transactionID: $0.id,
            expectedRevision: $0.revision, categoryID: category?.id) }
        let saved = try SQLiteDatabase.open().applyTransactionCategoryChanges(changes)
        reload()
        return saved
    }

    @discardableResult
    func restoreCategories(from transactions: [Transaction], replacing persisted: [Transaction]) throws -> [Transaction] {
        let oldByID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        let changes = try persisted.map { current -> TransactionCategoryChange in
            guard let old = oldByID[current.id] else { throw DailyValidationError.staleRecord }
            return TransactionCategoryChange(transactionID: current.id,
                expectedRevision: current.revision, categoryID: old.categoryID)
        }
        let saved = try SQLiteDatabase.open().applyTransactionCategoryChanges(changes)
        reload()
        return saved
    }

    @discardableResult
    func saveMonthlyBudget(_ budget: MonthlyBudget) throws -> MonthlyBudget {
        let saved = try SQLiteDatabase.open().saveMonthlyBudget(budget)
        reload()
        return saved
    }

    @discardableResult
    func saveSavingsGoal(_ goal: SavingsGoal) throws -> SavingsGoal {
        let saved = try SQLiteDatabase.open().saveSavingsGoal(goal)
        reload()
        return saved
    }

    @discardableResult func saveRecurringRule(_ rule: RecurringRule) throws -> RecurringRule {
        let saved = try SQLiteDatabase.open().saveRecurringRule(rule)
        refreshOnForeground()
        return saved
    }

    func skipNextRecurring(_ id: UUID) throws {
        try SQLiteDatabase.open().skipNextRecurring(id)
        reload()
    }

    @discardableResult func createNextRecurringNow(_ id: UUID) throws -> Transaction {
        let saved = try SQLiteDatabase.open().createNextRecurringNow(id)
        reload()
        return saved
    }

    @discardableResult func recordExpectedRecurringNow(_ id: String) throws -> Transaction {
        let saved = try SQLiteDatabase.open().recordExpectedRecurringNow(id)
        reload()
        return saved
    }

    func changeExpectedOccurrence(_ id: String, to status: RecurringOccurrenceStatus) throws {
        try SQLiteDatabase.open().changeExpectedOccurrence(id, to: status)
        reload()
    }

    func markCountedOccurrenceMissed(_ id: String) throws {
        try SQLiteDatabase.open().markCountedOccurrenceMissed(id)
        reload()
    }

    func confirmRecurringCandidate(_ id: UUID, candidateRevision: Int64? = nil,
                                   occurrenceRevision: Int64? = nil, ruleRevision: Int64? = nil,
                                   transactionRevision: Int64? = nil) throws {
        try SQLiteDatabase.open().confirmRecurringCandidate(id,
            expectedCandidateRevision: candidateRevision,
            expectedOccurrenceRevision: occurrenceRevision,
            expectedRuleRevision: ruleRevision,
            expectedTransactionRevision: transactionRevision)
        reload()
    }

    func separateRecurringEvent(_ eventID: UUID) throws {
        _ = try SQLiteDatabase.open().separateRecurringEvent(eventID)
        reload()
    }

    func rejectRecurringCandidate(_ id: UUID) throws {
        _ = try SQLiteDatabase.open().rejectRecurringCandidate(id)
        reload()
    }

    func approveRecurringPayee(_ name: String, for ruleID: UUID) throws {
        try SQLiteDatabase.open().approveRecurringPayee(name, for: ruleID)
        reload()
    }

    func linkRecurringTransaction(_ transactionID: UUID, to occurrenceID: String,
                                  occurrenceRevision: Int64? = nil,
                                  transactionRevision: Int64? = nil) throws {
        try SQLiteDatabase.open().linkRecurringTransaction(transactionID, to: occurrenceID,
            expectedOccurrenceRevision: occurrenceRevision,
            expectedTransactionRevision: transactionRevision)
        reload()
    }

    func unlinkRecurringTransaction(_ occurrenceID: String,
                                    occurrenceRevision: Int64? = nil,
                                    transactionRevision: Int64? = nil) throws {
        try SQLiteDatabase.open().unlinkRecurringTransaction(occurrenceID,
            expectedOccurrenceRevision: occurrenceRevision,
            expectedTransactionRevision: transactionRevision)
        reload()
    }

    func upcomingRecurring(days: Int = 30, now: Date = .now) -> [UpcomingRecurringItem] {
        recurringRules.flatMap { (try? RecurringSchedule.upcoming(for: $0, now: now, days: days)) ?? [] }
            .sorted { $0.day < $1.day }
    }

#if DEBUG
    @discardableResult func captureDemoEvent() -> Bool {
        guard let event = NotificationEvent.make(sourceApp: "Demo payment app", title: "Demo purchase",
                                                 subtitle: "Test notification", message: "Demo payment of €4.50 at Coffee Shop",
                                                 receivedAt: .now) else { return false }
        do {
            _ = try SQLiteDatabase.open().captureNotification(event)
            reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult func captureSyntheticExample(_ variant: Int) -> Bool {
        let source = ProcessInfo.processInfo.environment["EASYTRACK_TEST_SAMPLE_SOURCE"] ??
            (variant == 2 ? "Harbor Wallet (fictional)" : "Northstar Pay (fictional)")
        let merchantSuffix = ProcessInfo.processInfo.environment["EASYTRACK_TEST_MERCHANT_SUFFIX"]
            .map { " \($0)" } ?? ""
        let title = variant == 2 ? "Wallet receipt" : "Card purchase"
        let message = variant == 2 ? "Moor Cafe | 8.75 EUR received" :
            (variant == 3 ? "Paid €9,50 at Merchant Alpha\(merchantSuffix)" :
             (variant == 4 ? "Paid €7,89 at Merchant Beta\(merchantSuffix)" :
              "Paid €12,34 at Merchant Alpha\(merchantSuffix)"))
        guard let event = NotificationEvent.make(sourceApp: source, title: title, subtitle: "",
                                                 message: message, receivedAt: .now) else { return false }
        do {
            _ = try SQLiteDatabase.open().captureNotification(event)
            reload()
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
#endif

    @discardableResult func saveRule(_ rule: ParserRule) throws -> ParserRule {
        let saved = try SQLiteDatabase.open().saveParserRule(rule)
        reload()
        return saved
    }

    @discardableResult func mapSourceAccount(_ sourceID: UUID, to name: String) throws -> ParserSource {
        let source = try SQLiteDatabase.open().mapParserSource(sourceID, to: name)
        reload()
        return source
    }

    @discardableResult
    func configureNotificationSource(label: String, accountID: UUID) throws -> ParserSource {
        let source = try SQLiteDatabase.open().configureParserSource(named: label, accountID: accountID)
        try SQLiteDatabase.open().markAutomationSetupMilestone(.sourceMapped)
        reload()
        return source
    }

    func markAutomationSetupMilestone(_ milestone: AutomationSetupMilestone) throws {
        try SQLiteDatabase.open().markAutomationSetupMilestone(milestone)
        reload()
    }

    @discardableResult
    func setNotificationRetentionDays(_ days: Int) throws -> Int {
        let changed = try SQLiteDatabase.open().setNotificationRetentionDays(days)
        reload()
        return changed
    }

    @discardableResult
    func purgeExpiredNotificationContents() throws -> Int {
        let changed = try SQLiteDatabase.open().purgeExpiredNotificationContents()
        reload()
        return changed
    }

    @discardableResult
    func clearNotificationDiagnosticContents() throws -> Int {
        let changed = try SQLiteDatabase.open().clearNotificationDiagnosticContents()
        reload()
        return changed
    }

    func saveAppearancePreferences(_ preferences: AppearancePreferences) throws {
        try SQLiteDatabase.open().saveAppearancePreferences(preferences)
        appearancePreferences = preferences
    }

    func setBackupReminderEnabled(_ enabled: Bool) throws {
        var preferences = backupReminderPreferences
        preferences.isEnabled = enabled
        try SQLiteDatabase.open().saveBackupReminderPreferences(preferences)
        backupReminderPreferences = preferences
    }

    func recordSuccessfulBackupExport(at date: Date = .now) throws {
        var preferences = backupReminderPreferences
        preferences.lastSuccessfulExportAt = date
        try SQLiteDatabase.open().saveBackupReminderPreferences(preferences)
        backupReminderPreferences = preferences
    }

    func completeOnboarding() throws {
        try SQLiteDatabase.open().completeOnboarding()
        shouldPresentOnboarding = false
    }

    var availableAccountNames: [String] {
        let archived = Set(localAccounts.filter { $0.archivedAt != nil }
            .map { NotificationParser.normalize($0.name) })
        return Array(Set(activeAccounts.map(\.name) + historicalAccounts.map(\.sourceName) +
                         transactions.map(\.account).filter { !$0.isEmpty }))
            .filter { !archived.contains(NotificationParser.normalize($0)) }
            .sorted()
    }

    func proposedAccountName(for source: ParserSource) -> String {
        source.accountName ?? availableAccountNames.first {
            NotificationParser.normalize($0) == NotificationParser.normalize(source.name)
        } ?? source.name
    }

    func swapRulePriorities(_ first: ParserRule, _ second: ParserRule) throws {
        try SQLiteDatabase.open().swapParserRulePriorities(first, second)
        reload()
    }

    @discardableResult func processAttempt(_ id: UUID, preferredRuleID: UUID? = nil) throws -> ParserAttempt {
        let result = try SQLiteDatabase.open().processNotificationAttempt(id, preferredRuleID: preferredRuleID)
        reload()
        return result
    }

    func leaveSampleReady(_ id: UUID) throws {
        try SQLiteDatabase.open().leaveSampleReady(id)
        reload()
    }

    func backup() throws -> BackupArchive { try SQLiteDatabase.open().exportBackup() }

    var hasHistoricalImport: Bool { (historicalCounts["historical_imported_movements"] ?? 0) > 0 }

    var activeAccounts: [LocalAccount] { localAccounts.filter { $0.archivedAt == nil } }
    var activeCategories: [LedgerCategory] { ledgerCategories.filter { $0.archivedAt == nil } }
}
