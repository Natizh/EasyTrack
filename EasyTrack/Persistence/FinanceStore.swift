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
    @Published var errorMessage: String?

    init() {
        do {
            let database = try SQLiteDatabase.open()
            try database.seedDemoIfNeeded()
            _ = try database.materializeDueRecurring()
        }
        catch { errorMessage = error.localizedDescription }
        reload()
    }

    func refreshOnForeground() {
        do { _ = try SQLiteDatabase.open().materializeDueRecurring() }
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
        } catch { errorMessage = error.localizedDescription }
    }

    @discardableResult func save(_ item: Transaction) throws -> Transaction {
        let persisted = try SQLiteDatabase.open().save(item)
        reload()
        return persisted
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

    @discardableResult func saveCategory(_ category: LedgerCategory) throws -> LedgerCategory {
        let saved = try SQLiteDatabase.open().saveLedgerCategory(category)
        reload()
        return saved
    }

    func swapCategoryOrder(_ first: LedgerCategory, _ second: LedgerCategory) throws {
        try SQLiteDatabase.open().swapCategoryOrder(first, second)
        reload()
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
