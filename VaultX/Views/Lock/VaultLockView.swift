import SwiftUI

struct VaultLockView: View {
    @EnvironmentObject var appState: AppLockState
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var passcode = ""
    @State private var attempts = 0
    @State private var isAuthenticating = false
    @State private var errorMessage: String? = nil
    @State private var hasAttemptedAutomaticFaceID = false
    private let passcodeLength = 6
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 10)
            
            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                    .accessibilityHidden(true)
                
                Text("Enter Passcode")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                
                if let error = errorMessage {
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .accessibilityLabel(Text(error))
                } else {
                    Text("Unlock VaultX to continue")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(.horizontal)
            
            Spacer(minLength: 10)
            
            PasscodeDotsView(length: passcodeLength, activeCount: passcode.count)
                .padding(.vertical, 10)
                .modifier(ShakeEffect(animatableData: CGFloat(attempts)))
            
            Spacer(minLength: 10)
            
            NumberPadView(
                onNumberTapped: { number in
                    guard passcode.count < passcodeLength, !isAuthenticating else { return }
                    
                    if errorMessage != nil {
                        errorMessage = nil
                    }
                    
                    passcode.append(number)
                    
                    if passcode.count == passcodeLength {
                        isAuthenticating = true
                        verifyPasscode()
                    }
                },
                onDeleteTapped: {
                    guard !passcode.isEmpty, !isAuthenticating else { return }
                    if errorMessage != nil {
                        errorMessage = nil
                    }
                    passcode.removeLast()
                },
                onFaceIDTapped: {
                    requestFaceID()
                },
                isFaceIDEnabled: appState.faceIDPreferences.isFaceIDEnabled,
                isInputDisabled: isAuthenticating
            )
            .padding(.bottom, 20)
            .layoutPriority(1)
        }
        .background(Color(UIColor.systemBackground))
        .onAppear {
            passcode = ""
            errorMessage = nil
            
            if scenePhase == .active {
                requestAutomaticFaceID()
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                requestAutomaticFaceID()
            } else if newPhase == .background {
                // Reset flag for the next lock session
                hasAttemptedAutomaticFaceID = false
                passcode = ""
                errorMessage = nil
            }
        }
    }
    
    private func verifyPasscode() {
        let result = appState.verifyAndUnlock(passcode: passcode)
        
        switch result {
        case .success:
            passcode = ""
            isAuthenticating = false
            // State transitions to unlocked
        case .incorrect:
            triggerShake()
            errorMessage = "Incorrect passcode"
            passcode = ""
            isAuthenticating = false
        case .invalidInput:
            passcode = ""
            isAuthenticating = false
        case .storageUnavailable:
            errorMessage = "Unable to access your saved passcode. Please try again."
            passcode = ""
            isAuthenticating = false
            // Note: intentionally not shaking for storage error
        }
    }
    
    private func requestAutomaticFaceID() {
        guard !hasAttemptedAutomaticFaceID,
              !isAuthenticating,
              appState.faceIDPreferences.isFaceIDEnabled,
              appState.biometricService.canEvaluateFaceID() else { return }
        
        hasAttemptedAutomaticFaceID = true
        requestFaceID()
    }
    
    private func requestFaceID() {
        guard !isAuthenticating, 
              appState.faceIDPreferences.isFaceIDEnabled,
              appState.biometricService.canEvaluateFaceID() else { return }
              
        isAuthenticating = true
        appState.biometricService.authenticate(reason: "Unlock VaultX") { result in
            isAuthenticating = false
            if result == .success {
                appState.unlockSuccessfully()
            } else if result == .lockedOut {
                errorMessage = "Face ID is locked. Please use your passcode."
            }
        }
    }
    
    private func triggerShake() {
        withAnimation(.default) {
            attempts += 1
        }
    }
}

// Shake Animation Modifier
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    
    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = 10 * sin(animatableData * .pi * 3) // 3 shakes
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

#if DEBUG
#Preview {
    VaultLockView()
        .environmentObject(AppLockState.preview(state: .locked))
}
#endif
