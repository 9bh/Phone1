import SwiftUI

@main
struct VaultXApp: App {
  @StateObject private var securitySettings: VaultSecuritySettings
  @StateObject private var appState: AppLockState
  @StateObject private var accountsStore: VaultAccountsStore
  @Environment(\.scenePhase) private var scenePhase
  @State private var isPrivacyShieldVisible = true

  init() {
    let settings = VaultSecuritySettings()
    _securitySettings = StateObject(wrappedValue: settings)
    _appState = StateObject(
      wrappedValue: AppLockState(
        faceIDPreferences: settings,
        autoLockDelayProvider: { settings.autoLockDelay.seconds }
      )
    )

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
      ZStack {
        AppRootView()
          .environmentObject(appState)
          .environmentObject(accountsStore)
          .environmentObject(securitySettings)

        if isPrivacyShieldVisible {
          PrivacyShieldView()
            .transition(.opacity)
            .zIndex(1_000)
        }
      }
      .task {
        if scenePhase == .active {
          appState.appBecameActive()
          isPrivacyShieldVisible = false
        }
      }
      .onChange(of: scenePhase) { newPhase in
        if newPhase == .active {
          appState.appBecameActive()
          TOTPClock.shared.updateNow()
          if appState.currentState == .unlocked {
            TOTPClock.shared.start()
          }

          DispatchQueue.main.async {
            isPrivacyShieldVisible = false
          }
        } else if newPhase == .background || newPhase == .inactive {
          isPrivacyShieldVisible = true
          TOTPClock.shared.stop()
          appState.appEnteredBackground()
        }
      }
    }
  }
}

private struct PrivacyShieldView: View {
  var body: some View {
    ZStack {
      Color(uiColor: .systemBackground)
        .ignoresSafeArea()

      VStack(spacing: 12) {
        Image(systemName: "lock.shield.fill")
          .font(.system(size: 42, weight: .semibold))
          .foregroundColor(.accentColor)

        Text("VaultX محمي")
          .font(.headline)
      }
      .environment(\.layoutDirection, .rightToLeft)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("VaultX محمي")
  }
}
