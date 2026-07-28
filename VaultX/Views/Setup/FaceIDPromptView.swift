import SwiftUI

struct FaceIDPromptView: View {
    @EnvironmentObject var appState: AppLockState
    @State private var isAuthenticating = false
    @State private var isFaceIDAvailable = false
    @State private var biometricError: String? = nil
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "faceid")
                .font(.system(size: 80))
                .foregroundColor(isFaceIDAvailable ? .accentColor : .secondary)
                .accessibilityHidden(true)
            
            VStack(spacing: 12) {
                Text("Enable Face ID?")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                
                Text("Use your face to quickly unlock VaultX without entering your passcode.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                if let error = biometricError {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top, 4)
                } else if !isFaceIDAvailable {
                    Text("Face ID is currently not set up or unavailable on this device. You can skip this step and use your passcode.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }
            }
            
            Spacer()
            
            VStack(spacing: 16) {
                Button(action: {
                    requestFaceID()
                }) {
                    ZStack {
                        if isAuthenticating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Enable Face ID")
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor.opacity((!isFaceIDAvailable || isAuthenticating) ? 0.5 : 1.0))
                    .cornerRadius(12)
                }
                .disabled(!isFaceIDAvailable || isAuthenticating)
                .padding(.horizontal, 24)
                
                Button(action: {
                    guard !isAuthenticating else { return }
                    appState.faceIDPreferences.isFaceIDEnabled = false
                    appState.faceIDChoiceMade()
                }) {
                    Text("Not Now")
                        .font(.headline)
                        .foregroundColor(.accentColor)
                        .padding()
                }
                .disabled(isAuthenticating)
            }
            .padding(.bottom, 40)
        }
        .background(Color(UIColor.systemBackground))
        .onAppear {
            isFaceIDAvailable = appState.biometricService.canEvaluateFaceID()
        }
    }
    
    private func requestFaceID() {
        guard !isAuthenticating, isFaceIDAvailable else { return }
        isAuthenticating = true
        biometricError = nil
        
        appState.biometricService.authenticate(reason: "Enable Face ID to unlock VaultX") { result in
            isAuthenticating = false
            
            switch result {
            case .success:
                appState.faceIDPreferences.isFaceIDEnabled = true
                appState.faceIDChoiceMade()
            case .notAvailable, .notEnrolled:
                biometricError = "Face ID is not set up on this device."
            case .lockedOut:
                biometricError = "Face ID is locked. Please use your passcode."
            case .authenticationFailed:
                // No message needed, iOS handles shake. Just stay on screen.
                break
            case .cancelled:
                // User cancelled, do nothing.
                break
            }
        }
    }
}

#if DEBUG
#Preview {
    FaceIDPromptView()
        .environmentObject(AppLockState.preview(state: .needsFaceIDChoice))
}
#endif
