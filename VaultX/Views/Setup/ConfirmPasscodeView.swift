import SwiftUI

struct ConfirmPasscodeView: View {
    @EnvironmentObject var appState: AppLockState
    @State private var passcode = ""
    @State private var isProcessing = false
    private let passcodeLength = 6
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 10)
            
            VStack(spacing: 12) {
                Text("Confirm your passcode")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                
                Text("Enter your 6-digit passcode again")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer(minLength: 10)
            
            PasscodeDotsView(length: passcodeLength, activeCount: passcode.count)
                .padding(.vertical, 10)
            
            Spacer(minLength: 10)
            
            NumberPadView(
                onNumberTapped: { number in
                    guard passcode.count < passcodeLength, !isProcessing else { return }
                    
                    passcode.append(number)
                    
                    if passcode.count == passcodeLength {
                        isProcessing = true
                        let success = appState.confirmPasscode(passcode)
                        if !success {
                            passcode = ""
                        }
                        isProcessing = false
                    }
                },
                onDeleteTapped: {
                    guard !passcode.isEmpty, !isProcessing else { return }
                    passcode.removeLast()
                },
                onFaceIDTapped: nil,
                isFaceIDEnabled: false,
                isInputDisabled: isProcessing
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
    ConfirmPasscodeView()
        .environmentObject(AppLockState.preview(state: .needsPasscodeConfirmation))
}
#endif
