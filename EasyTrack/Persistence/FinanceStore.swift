import Foundation

@MainActor
final class FinanceStore: ObservableObject {
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var events: [NotificationEvent] = []
    @Published private(set) var parserSources: [ParserSource] = []
    @Published private(set) var localAccounts: [LocalAccount] = []
    @Published private(set) var parserRules: [ParserRule] = []
    @Published private(set) var parserAttempts: [ParserAttempt] = []
    @Published private(set) var historicalCounts: [String: Int] = [:]
    @Published private(set) var historicalAccounts: [HistoricalAccount] = []
    @Published private(set) var historicalTrips: [HistoricalTrip] = []
    @Published private(set) var historicalRules: [HistoricalRecurringRule] = []
    @Published var errorMessage: String?

    init() {
        do { try SQLiteDatabase.open().seedDemoIfNeeded() }
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
        var updated = transactions.filter { $0.id != persisted.id }
        if persisted.deletedAt == nil { updated.append(persisted) }
        transactions = updated.sorted { $0.occurredAt > $1.occurredAt }
        return persisted
    }

    func delete(_ item: Transaction) throws {
        var deleted = item
        deleted.deletedAt = .now
        try save(deleted)
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
        Array(Set(localAccounts.map(\.name) + historicalAccounts.map(\.sourceName) +
                  transactions.map(\.account).filter { !$0.isEmpty })).sorted()
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

    func backup() throws -> BackupEnvelope {
        let database = try SQLiteDatabase.open()
        let rules = try database.parserRules(includeDeleted: true)
        return BackupEnvelope(schemaVersion: 4, exportID: UUID(), exportedAt: .now,
                              transactions: try database.transactions(includeDeleted: true),
                              notificationEvents: try database.notificationEvents(),
                              operations: try database.operations(), historical: try database.historicalBackup(),
                              parserSources: try database.parserSources(), parserRules: rules,
                              localAccounts: try database.localAccounts(),
                              parserRuleVersions: try rules.flatMap { try database.parserRuleHistory($0.id) },
                              parserAttempts: try database.parserAttempts())
    }

    var hasHistoricalImport: Bool { (historicalCounts["historical_imported_movements"] ?? 0) > 0 }
}
