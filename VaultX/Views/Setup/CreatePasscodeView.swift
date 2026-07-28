import SwiftUI

struct CreatePasscodeView: View {
    @EnvironmentObject var appState: AppLockState
    @State private var passcode = ""
    @State private var isProcessing = false
    private let passcodeLength = 6
    
    var body: some View {
        let isPreparationFailed = appState.installationPreparationResult == .preparationFailed
        let isInputDisabled = isProcessing || isPreparationFailed
        
        VStack(spacing: 0) {
            Spacer(minLength: 10)
            
            VStack(spacing: 12) {
                Text("Create your passcode")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                
                if let error = appState.setupError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .accessibilityLabel(Text(error))
                } else {
                    Text("Create a 6-digit passcode to protect your vault")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                if isPreparationFailed {
                    Button(action: {
                        appState.retryPreparation()
                    }) {
                        Text("Retry")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .background(Color.accentColor)
                            .cornerRadius(8)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal)
            
            Spacer(minLength: 10)
            
            PasscodeDotsView(length: passcodeLength, activeCount: passcode.count)
                .padding(.vertical, 10)
            
            Spacer(minLength: 10)
            
            NumberPadView(
                onNumberTapped: { number in
                    guard passcode.count < passcodeLength, !isInputDisabled else { return }
                    
                    if appState.setupError != nil {
                        appState.clearSetupError()
                    }
                    
                    passcode.append(number)
                    
                    if passcode.count == passcodeLength {
                        isProcessing = true
                        appState.passcodeSetupEntered(passcode)
                        if appState.currentState == .needsPasscodeSetup {
                            passcode = ""
                        }
                        isProcessing = false
                    }
                },
                onDeleteTapped: {
                    guard !passcode.isEmpty, !isInputDisabled else { return }
                    if appState.setupError != nil {
                        appState.clearSetupError()
                    }
                    passcode.removeLast()
                },
                onFaceIDTapped: nil,
                isFaceIDEnabled: false,
                isInputDisabled: isInputDisabled
            )
            .padding(.bottom, 20)
            .layoutPriority(1)
        }
        .background(Color(UIColor.systemBackground))
        .onAppear {
            passcode = ""
        }
    }
}

#if DEBUG
#Preview {
    CreatePasscodeView()
        .environmentObject(AppLockState.preview(state: .needsPasscodeSetup, preparationResult: .preparationFailed))
}
#endif
