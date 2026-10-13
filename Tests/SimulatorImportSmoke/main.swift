import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("Pass the simulator database path") }
let database = try SQLiteDatabase(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let active = try database.transactions()
precondition(active.count == 1, "Expected only the synthetic imported movement")
var item = active[0]
precondition(item.sourceMovementID == "synthetic-9", "Unexpected source identity")
let id = item.id
let sheet = item.sourceSheet
let row = item.sourceRow
item.note = "Synthetic local edit retained after reimport"
try database.save(item)
let reopened = try database.transactions()[0]
precondition(reopened.id == id && reopened.sourceMovementID == "synthetic-9")
precondition(reopened.sourceSheet == sheet && reopened.sourceRow == row)
precondition(reopened.note == item.note)
print("Simulator synthetic edit round-trip passed; stable identity and provenance retained")
