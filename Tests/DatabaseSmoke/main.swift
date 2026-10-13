import Foundation

let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-db-test-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }

let database = try SQLiteDatabase(url: folder.appendingPathComponent("test.sqlite"))
try database.seedDemoIfNeeded()
try database.seedDemoIfNeeded()
let initial = try database.transactions()
precondition(initial.count == 3)

var item = initial[0]
let itemID = item.id
item.merchant = "Edited demo"
item.amountMinor = 1_875
item.eurMinor = 1_875
item.personalExpenseEURMinor = 1_875
item.category = "Edited category"
item.subcategory = "Edited subcategory"
item.note = "Edited note"
try database.save(item)
let edited = try database.transactions()
precondition(edited.first(where: { $0.id == itemID })?.revision == 2)
precondition(edited.first(where: { $0.id == itemID })?.amountMinor == 1_875)
precondition(edited.first(where: { $0.id == itemID })?.eurMinor == 1_875)
precondition(edited.first(where: { $0.id == itemID })?.personalExpenseEURMinor == 1_875)
precondition(edited.first(where: { $0.id == itemID })?.subcategory == "Edited subcategory")

item.deletedAt = .now
try database.save(item)
let active = try database.transactions()
let includingDeleted = try database.transactions(includeDeleted: true)
precondition(active.count == 2)
precondition(includingDeleted.count == 3)

let date = Date(timeIntervalSince1970: 1_700_000_000)
let event = NotificationEvent.make(sourceApp: "Test source", title: "Test", subtitle: "", message: "€1.00", receivedAt: date)!
let inserted = try database.insertEvent(event)
let insertedAgain = try database.insertEvent(event)
let events = try database.notificationEvents()
precondition(inserted)
precondition(!insertedAgain)
precondition(events.count == 1)

var linked = initial[1]
linked.id = UUID()
linked.isDemo = false
linked.sourceEventID = event.id
try database.save(linked)
var duplicateLinked = linked
duplicateLinked.id = UUID()
let duplicateRejected = (try? database.save(duplicateLinked)) == nil
precondition(duplicateRejected)
linked.deletedAt = .now
try database.save(linked)
try database.save(duplicateLinked)
let operations = try database.operations()
precondition(operations.count == 8)
print("SQLite smoke test passed: seed, edit, tombstone, event dedupe, active-link uniqueness, operation log")
