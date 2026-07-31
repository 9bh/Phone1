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
        .onChange(of: scenePhase) { newPhase in
          if newPhase == .active {
            TOTPClock.shared.updateNow()
            if appState.currentState == .unlocked {
              TOTPClock.shared.start()
            }
          } else if newPhase == .background || newPhase == .inactive {
            TOTPClock.shared.stop()
            appState.appEnteredBackground()
          }
        }
    }
  }
}
