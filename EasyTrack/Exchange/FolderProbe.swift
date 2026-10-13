import Foundation

enum FolderProbeError: LocalizedError {
    case noFolder, accessDenied, staleBookmark, coordinationFailed, mismatch
    var errorDescription: String? {
        switch self {
        case .noFolder: "Choose a folder first."
        case .accessDenied: "Folder access was denied. Select the folder again in Files."
        case .staleBookmark: "The saved folder moved or changed. Select it again."
        case .coordinationFailed: "The file provider could not coordinate this file operation."
        case .mismatch: "The test file did not read back with the same operation ID."
        }
    }
}

actor FolderProbe {
    static let shared = FolderProbe()
    private let bookmarkKey = "exchangeFolderBookmarkV1"

    func hasSavedFolder() -> Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }

    private func isOwnContainer(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path + "/")
    }

    func select(_ url: URL) throws {
        let scopedAccess = url.startAccessingSecurityScopedResource()
        guard scopedAccess || isOwnContainer(url) else { throw FolderProbeError.accessDenied }
        defer { if scopedAccess { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    }

    func writeAndRead() throws -> ExchangeOperation {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { throw FolderProbeError.noFolder }
        var stale = false
        let folder = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale else { throw FolderProbeError.staleBookmark }
        let scopedAccess = folder.startAccessingSecurityScopedResource()
        guard scopedAccess || isOwnContainer(folder) else { throw FolderProbeError.accessDenied }
        defer { if scopedAccess { folder.stopAccessingSecurityScopedResource() } }

        let file = folder.appendingPathComponent("easytrack-folder-probe.json")
        let operation = ExchangeOperation.folderProbe()
        let encoded = try JSONEncoder().encode(operation)
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var operationError: Error?
        coordinator.coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do { try encoded.write(to: coordinatedURL, options: .atomic) }
            catch { operationError = error }
        }
        if let error = operationError { throw error }
        if coordinationError != nil { throw FolderProbeError.coordinationFailed }

        var readData: Data?
        coordinator.coordinate(readingItemAt: file, options: [], error: &coordinationError) { coordinatedURL in
            do { readData = try Data(contentsOf: coordinatedURL) }
            catch { operationError = error }
        }
        if let error = operationError { throw error }
        if coordinationError != nil { throw FolderProbeError.coordinationFailed }
        guard let readData, try JSONDecoder().decode(ExchangeOperation.self, from: readData) == operation else {
            throw FolderProbeError.mismatch
        }
        return operation
    }
}
