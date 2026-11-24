import SwiftUI

@main
struct EasyTrackApp: App {
    @StateObject private var store = FinanceStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.italian.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environment(\.locale, AppLanguage.resolved(languageCode).locale)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.refreshOnForeground() }
                }
        }
    }
}
