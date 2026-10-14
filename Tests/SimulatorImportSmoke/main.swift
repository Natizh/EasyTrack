import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("Pass the simulator database path") }
let database = try SQLiteDatabase(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let active = try database.transactions()
precondition(active.filter { $0.sourceMovementID != nil }.count == 1,
             "Expected only the synthetic imported movement among historical rows")
guard var item = active.first(where: { $0.sourceMovementID == "synthetic-9" }) else {
    fatalError("Synthetic source identity not found")
}
let id = item.id
let sheet = item.sourceSheet
let row = item.sourceRow
item.note = "Synthetic local edit retained after reimport"
try database.save(item)
guard let reopened = try database.transactions().first(where: { $0.id == id }) else {
    fatalError("Synthetic transaction disappeared")
}
precondition(reopened.id == id && reopened.sourceMovementID == "synthetic-9")
precondition(reopened.sourceSheet == sheet && reopened.sourceRow == row)
precondition(reopened.note == item.note)
print("Simulator synthetic edit round-trip passed; stable identity and provenance retained")
