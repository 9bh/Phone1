import SwiftUI

@main
struct VaultXApp: App {
    @StateObject private var appState = AppLockState()
    @StateObject private var accountsStore = VaultAccountsStore()
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appState)
                .environmentObject(accountsStore)
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .background || newPhase == .inactive {
                        appState.appEnteredBackground()
                    }
                }
        }
    }
}
