import SwiftUI

struct OwnerVerificationView: View {
    @EnvironmentObject private var appState: AppLockState
    @Environment(\.dismiss) private var dismiss

    let title: String
    let reason: String
    let onVerified: () -> Void

    @State private var passcode = ""
    @State private var errorMessage: String?
    @State private var isAuthenticating = false
    @State private var hasAttemptedAutomaticFaceID = false
    @State private var shakeCount = 0

    private let passcodeLength = 6

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("إلغاء") {
                    dismiss()
                }
                .disabled(isAuthenticating)

                Spacer()

                Text(title)
                    .font(.headline)
            }
            .environment(\.layoutDirection, .leftToRight)
            .padding()

            Spacer(minLength: 8)

            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundColor(.accentColor)

                Text("تحقق من هويتك")
                    .font(.title2.bold())

                Text(errorMessage ?? "استخدم Face ID أو رمز VaultX للمتابعة.")
                    .font(.subheadline)
                    .foregroundColor(errorMessage == nil ? .secondary : .red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .environment(\.layoutDirection, .rightToLeft)

            Spacer(minLength: 12)

            PasscodeDotsView(length: passcodeLength, activeCount: passcode.count)
                .modifier(ShakeEffect(animatableData: CGFloat(shakeCount)))
                .padding(.vertical, 12)

            NumberPadView(
                onNumberTapped: handleNumber,
                onDeleteTapped: handleDelete,
                onFaceIDTapped: requestFaceID,
                isFaceIDEnabled: canUseFaceID,
                isInputDisabled: isAuthenticating
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 18)
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear {
            requestAutomaticFaceID()
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isAuthenticating)
    }

    private var canUseFaceID: Bool {
        appState.faceIDPreferences.isFaceIDEnabled
            && appState.biometricService.canEvaluateFaceID()
    }

    private func handleNumber(_ number: String) {
        guard !isAuthenticating, passcode.count < passcodeLength else { return }
        errorMessage = nil
        passcode.append(number)

        if passcode.count == passcodeLength {
            verifyPasscode()
        }
    }

    private func handleDelete() {
        guard !isAuthenticating, !passcode.isEmpty else { return }
        errorMessage = nil
        passcode.removeLast()
    }

    private func verifyPasscode() {
        isAuthenticating = true
        let result = appState.verifyOwnerPasscode(passcode)
        passcode = ""
        isAuthenticating = false

        switch result {
        case .success:
            completeVerification()
        case .incorrect:
            withAnimation(.default) { shakeCount += 1 }
            errorMessage = "رمز VaultX غير صحيح."
        case .invalidInput:
            errorMessage = "أدخل رمز VaultX المكوّن من 6 أرقام."
        case .storageUnavailable:
            errorMessage = "تعذر التحقق من رمز VaultX حاليًا."
        }
    }

    private func requestAutomaticFaceID() {
        guard !hasAttemptedAutomaticFaceID, canUseFaceID else { return }
        hasAttemptedAutomaticFaceID = true
        requestFaceID()
    }

    private func requestFaceID() {
        guard !isAuthenticating, canUseFaceID else { return }
        isAuthenticating = true
        appState.verifyOwnerWithFaceID(reason: reason) { result in
            isAuthenticating = false
            switch result {
            case .success:
                completeVerification()
            case .lockedOut:
                errorMessage = "Face ID مقفل. استخدم رمز VaultX."
            case .notAvailable, .notEnrolled:
                errorMessage = "Face ID غير متاح. استخدم رمز VaultX."
            case .cancelled:
                errorMessage = nil
            case .authenticationFailed:
                errorMessage = "لم ينجح التحقق. حاول مرة أخرى أو استخدم رمز VaultX."
            }
        }
    }

    private func completeVerification() {
        dismiss()
        DispatchQueue.main.async {
            onVerified()
        }
    }
}

#if DEBUG
#Preview {
    OwnerVerificationView(
        title: "إنشاء نسخة احتياطية",
        reason: "تحقق لإنشاء نسخة احتياطية مشفرة",
        onVerified: {}
    )
    .environmentObject(AppLockState.preview(state: .unlocked))
}
#endif
