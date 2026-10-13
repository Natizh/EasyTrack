import Foundation

@MainActor
final class FinanceStore: ObservableObject {
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var events: [NotificationEvent] = []
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

    @discardableResult func captureDemoEvent() -> Bool {
        guard let event = NotificationEvent.make(sourceApp: "Demo payment app", title: "Demo purchase",
                                                 subtitle: "Test notification", message: "Demo payment of €4.50 at Coffee Shop",
                                                 receivedAt: .now) else { return false }
        do {
            try SQLiteDatabase.open().insertEvent(event)
            reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func backup() throws -> BackupEnvelope {
        let database = try SQLiteDatabase.open()
        return BackupEnvelope(schemaVersion: 2, exportID: UUID(), exportedAt: .now,
                              transactions: try database.transactions(includeDeleted: true),
                              notificationEvents: try database.notificationEvents(),
                              operations: try database.operations(), historical: try database.historicalBackup())
    }

    var hasHistoricalImport: Bool { (historicalCounts["historical_imported_movements"] ?? 0) > 0 }
}
