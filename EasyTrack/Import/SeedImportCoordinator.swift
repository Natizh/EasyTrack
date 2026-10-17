import Foundation
import SQLite3

actor SeedImportCoordinator {
    static let shared = SeedImportCoordinator()
    private var stagedURL: URL?
    private var validatedSeed: ValidatedSeed?

    init() {
        let directory = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("EasyTrack-seed-stage-") && file.pathExtension == "sqlite" {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    func stage(_ selectedURL: URL) throws -> HistoricalImportPreview {
        cancel()
        let scopedAccess = selectedURL.startAccessingSecurityScopedResource()
        let isOwnContainer = selectedURL.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path + "/")
        guard scopedAccess || isOwnContainer else {
            throw SeedImportError.database("Files access was not granted. Select the file again.")
        }
        defer { if scopedAccess { selectedURL.stopAccessingSecurityScopedResource() } }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("EasyTrack-seed-stage-\(UUID().uuidString).sqlite")
        do {
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            var copyError: Error?
            coordinator.coordinate(readingItemAt: selectedURL, options: [], error: &coordinationError) { source in
                do { try Self.snapshotSQLite(from: source, to: target) }
                catch { copyError = error }
            }
            if let copyError { throw copyError }
            if coordinationError != nil { throw SeedImportError.database("Files could not coordinate the selected file") }
            let seed = try SeedMapper(url: target).read(url: target)
            let preview = try SQLiteDatabase.open().historicalImportPreview(seed)
            stagedURL = target
            validatedSeed = seed
            return preview
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
    }

    func confirm(decisions: [String: HistoricalImportDecision] = [:]) throws -> HistoricalImportPreview {
        guard let seed = validatedSeed else { throw SeedImportError.database("Choose the seed file again") }
        let result = try SQLiteDatabase.open().importHistoricalSeed(seed, decisions: decisions)
        cancel()
        return result
    }

    func cancel() {
        if let stagedURL { try? FileManager.default.removeItem(at: stagedURL) }
        stagedURL = nil
        validatedSeed = nil
    }

    static func snapshotSQLite(from source: URL, to target: URL) throws {
        var sourceHandle: OpaquePointer?
        var targetHandle: OpaquePointer?
        guard sqlite3_open_v2(source.path, &sourceHandle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(sourceHandle)
            throw SeedImportError.database("selected file is not readable SQLite")
        }
        defer { sqlite3_close(sourceHandle) }
        guard sqlite3_open_v2(target.path, &targetHandle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(targetHandle)
            throw SeedImportError.database("temporary snapshot could not be created")
        }
        defer { sqlite3_close(targetHandle) }
        guard let backup = sqlite3_backup_init(targetHandle, "main", sourceHandle, "main") else {
            throw SeedImportError.database("SQLite snapshot could not start")
        }
        let result = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finished == SQLITE_OK else {
            throw SeedImportError.database("SQLite snapshot could not finish")
        }
    }
}
