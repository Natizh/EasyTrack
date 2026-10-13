import AppIntents
import Foundation

struct CaptureNotificationIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Payment Notification"
    static var description = IntentDescription("Keep notification text on this iPhone for later rule setup. No transaction is created.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Source app") var sourceApp: String
    @Parameter(title: "Title") var notificationTitle: String?
    @Parameter(title: "Subtitle") var subtitle: String?
    @Parameter(title: "Message") var message: String?
    @Parameter(title: "Notification date") var notificationDate: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Capture notification from \(\.$sourceApp)") {
            \.$notificationTitle
            \.$subtitle
            \.$message
            \.$notificationDate
        }
    }

    func perform() async throws -> some IntentResult {
        guard let event = NotificationEvent.make(sourceApp: sourceApp, title: notificationTitle ?? "",
                                                  subtitle: subtitle ?? "", message: message ?? "",
                                                  receivedAt: notificationDate) else {
            throw IntakeError.invalidPayload
        }
        try SQLiteDatabase.open().insertEvent(event)
        return .result()
    }
}

enum IntakeError: LocalizedError {
    case invalidPayload
    var errorDescription: String? { "The notification needs a source app and fields shorter than 8 KB." }
}
