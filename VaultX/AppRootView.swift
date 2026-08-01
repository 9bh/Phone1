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
    .onOpenURL(perform: handleIncomingFileURL)
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



  private func handleIncomingFileURL(_ url: URL) {
    guard VaultBackupFileAccess.isSupportedBackupURL(url) else { return }

    backupRestoreSession.isBusy = true
    Task {
      do {
        let data = try await VaultBackupFileAccess.readBackupData(from: url)
        backupRestoreSession.prepare(
          encryptedData: data,
          filename: url.lastPathComponent,
          requestPasswordPrompt: true
        )
        backupRestoreSession.isBusy = false
        navigationSession.path = []
        navigationSession.isMenuPresented = false
        navigationSession.isShowingGoogleImport = false
        navigationSession.isShowingSecuritySettings = false
        navigationSession.isShowingBackupRestore = true
      } catch {
        backupRestoreSession.isBusy = false
        backupRestoreSession.fileOpenErrorMessage = backupFileErrorMessage(error)
        navigationSession.path = []
        navigationSession.isMenuPresented = false
        navigationSession.isShowingGoogleImport = false
        navigationSession.isShowingSecuritySettings = false
        navigationSession.isShowingBackupRestore = true
      }
    }
  }

  private func backupFileErrorMessage(_ error: Error) -> String {
    if let localized = error as? LocalizedError,
       let description = localized.errorDescription {
      return description
    }
    return "تعذر قراءة ملف النسخة الاحتياطية."
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
