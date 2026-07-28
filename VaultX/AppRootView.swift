import SwiftUI

struct AppRootView: View {
    @EnvironmentObject var appState: AppLockState
    
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
                UnlockedPlaceholderView()
            }
        }
        .animation(.easeInOut, value: appState.currentState)
    }
}

#if DEBUG
#Preview {
    AppRootView()
        .environmentObject(AppLockState.preview(state: .needsPasscodeSetup))
}
#endif
