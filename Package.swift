// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "EasyTrackCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "EasyTrackCore", targets: ["EasyTrackCore"])],
    targets: [
        .target(name: "EasyTrackCore", path: "EasyTrack", exclude: ["App", "UI", "Intake", "Exchange", "Assets.xcassets", "Resources", "Info.plist", "Persistence/FinanceStore.swift"],
                sources: ["Shared/Models.swift", "Shared/NotificationParser.swift", "Shared/DailyModels.swift",
                          "Shared/RecurringSchedule.swift", "Persistence/SQLiteDatabase.swift",
                          "Persistence/SQLiteDatabase+Daily.swift",
                          "Persistence/SQLiteDatabase+Backup.swift",
                          "Persistence/LegacyBackupConverter.swift",
                          "Import/SeedMapper.swift", "Import/SeedImportCoordinator.swift"]),
        .testTarget(name: "EasyTrackCoreTests", dependencies: ["EasyTrackCore"], path: "Tests/EasyTrackCoreTests")
    ]
)
