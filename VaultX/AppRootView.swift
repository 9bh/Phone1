import SwiftUI

struct AppRootView: View {
  @EnvironmentObject var appState: AppLockState
  @EnvironmentObject var accountsStore: VaultAccountsStore
  @StateObject private var editorSession = AccountEditorSession()
  @StateObject private var navigationSession = VaultNavigationSession()
  @StateObject private var googleImportSession = GoogleAuthenticatorImportSession()
  @StateObject private var backupRestoreSession = VaultBackupRestoreSession()

  var body: some View {
    Group {
      switch appState.currentState {
      case .needsPasscodeSetup:
        CreatePasscodeView()
      case .needsPasscodeConfirmation:
        ConfirmPasscodeView()
      case .needsFaceIDChoice:
        FaceIDPromptView()
      case .locked:
        VaultLockView()
      case .unlocked:
        unlockedView
      }
    }
    .animation(.easeInOut, value: appState.currentState)
    .task(id: appState.currentState) {
      if appState.currentState == .unlocked {
        TOTPClock.shared.start()
        await accountsStore.unlockAndLoad()
      } else {
        TOTPClock.shared.stop()
        accountsStore.lockAndClear()
      }
    }
  }

  @ViewBuilder
  private var unlockedView: some View {
    switch accountsStore.loadState {
    case .locked, .loading:
      ProgressView("جاري تحميل الحسابات...")
    case .loaded:
      VaultHomeView()
        .environmentObject(editorSession)
        .environmentObject(navigationSession)
        .environmentObject(googleImportSession)
        .environmentObject(backupRestoreSession)
    case .failed:
      VStack(spacing: 16) {
        Text("تعذر الوصول إلى الخزنة")
          .font(.title2)
          .fontWeight(.bold)

        Text("تعذر تحميل بيانات الحسابات بأمان. لم يتم حذف بياناتك.")
          .multilineTextAlignment(.center)
          .foregroundColor(.secondary)
          .padding(.horizontal)

        Button("إعادة المحاولة") {
          Task {
            await accountsStore.retryLoad()
          }
        }
        .buttonStyle(.borderedProminent)
      }
      .environment(\.layoutDirection, .rightToLeft)
    }
  }
}

#if DEBUG
  #Preview {
    AppRootView()
      .environmentObject(AppLockState.preview(state: .needsPasscodeSetup))
      .environmentObject(VaultAccountsStore.preview(loadState: .locked))
      .environmentObject(VaultSecuritySettings())
  }
#endif
