import SwiftUI

@main
struct VaultXApp: App {
    @StateObject private var appState = AppLockState()
    @StateObject private var accountsStore: VaultAccountsStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let filesystem = ProductionVaultFilesystemClient()
        let keychainClient = ProductionVaultKeychainClient()
        let keyStore = KeychainVaultEncryptionKeyStore(client: keychainClient)
        let persistence = EncryptedVaultAccountsPersistence(
            keyStore: keyStore,
            filesystem: filesystem
        )

        _accountsStore = StateObject(
            wrappedValue: VaultAccountsStore(persistence: persistence)
        )
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appState)
                .environmentObject(accountsStore)
                .onAppear {
                    updateTOTPClockState()
                }
                .onChange(of: scenePhase) { newPhase in
                    updateTOTPClockState()

                    if newPhase == .background || newPhase == .inactive {
                        appState.appEnteredBackground()
                    }
                }
                .onChange(of: appState.currentState) { _ in
                    updateTOTPClockState()
                }
        }
    }

    private func updateTOTPClockState() {
        if scenePhase == .active, appState.currentState == .unlocked {
            TOTPClock.shared.start()
        } else {
            TOTPClock.shared.stop()
        }
    }
}
