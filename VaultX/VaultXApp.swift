import SwiftUI

@main
struct VaultXApp: App {
    @StateObject private var appState = AppLockState()
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appState)
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .background || newPhase == .inactive {
                        appState.appEnteredBackground()
                    }
                }
        }
    }
}
