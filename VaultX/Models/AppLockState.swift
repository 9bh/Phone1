import Foundation
import Combine

enum AppState: Equatable {
    case needsPasscodeSetup
    case needsPasscodeConfirmation
    case needsFaceIDChoice
    case locked
    case unlocked
}

@MainActor
class AppLockState: ObservableObject {
    @Published var currentState: AppState = .locked
    @Published private(set) var setupError: String? = nil
    @Published private(set) var installationPreparationResult: InstallationPreparationResult = .existingInstallation

    private var tempPasscode: String = ""
    private var trustedSystemPresentationDepth = 0
    private var observedSceneTransitionDuringTrustedPresentation = false
    private var trustedBackgroundedAt: Date?
    private var backgroundedAt: Date?
    private var pendingLockTask: Task<Void, Never>?

    private let passcodeStore: PasscodeStore
    private let installationService: AppInstallationService
    private let autoLockDelayProvider: () -> TimeInterval
    let biometricService: BiometricAuthenticating
    var faceIDPreferences: FaceIDPreferenceStore

    init(
        passcodeStore: PasscodeStore = PasscodeKeychainService(),
        installationService: AppInstallationService = AppInstallationService(),
        biometricService: BiometricAuthenticating = BiometricAuthenticationService(),
        faceIDPreferences: FaceIDPreferenceStore = UserDefaultsFaceIDPreferenceStore(),
        autoLockDelayProvider: @escaping () -> TimeInterval = { 0 }
    ) {
        self.passcodeStore = passcodeStore
        self.installationService = installationService
        self.biometricService = biometricService
        self.faceIDPreferences = faceIDPreferences
        self.autoLockDelayProvider = autoLockDelayProvider
        determineInitialState()
    }

    #if DEBUG
    /// Preview-safe factory that bypasses real installation detection.
    static func preview(state: AppState, preparationResult: InstallationPreparationResult = .existingInstallation) -> AppLockState {
        let stateObj = AppLockState(
            passcodeStore: PreviewPasscodeStore(),
            installationService: PreviewInstallationService(),
            biometricService: PreviewBiometricService(),
            faceIDPreferences: PreviewFaceIDPreferences()
        )
        stateObj.currentState = state
        stateObj.installationPreparationResult = preparationResult
        return stateObj
    }
    #endif

    func determineInitialState() {
        if installationService.isFreshInstall() {
            prepareFreshInstallation()
        } else {
            installationPreparationResult = .existingInstallation
            do {
                if try passcodeStore.hasPasscode() {
                    currentState = .locked
                } else {
                    currentState = .needsPasscodeSetup
                }
            } catch {
                currentState = .locked
            }
        }
    }

    func retryPreparation() {
        if installationPreparationResult == .preparationFailed {
            prepareFreshInstallation()
        }
    }

    private func prepareFreshInstallation() {
        do {
            try passcodeStore.deletePasscode()
            installationService.markAsInstalled()
            installationPreparationResult = .freshInstallationPrepared
            currentState = .needsPasscodeSetup
            setupError = nil
        } catch {
            installationPreparationResult = .preparationFailed
            currentState = .needsPasscodeSetup
            setupError = "Unable to prepare VaultX securely. Please try again."
        }
    }

    func beginTrustedSystemPresentation() {
        if trustedSystemPresentationDepth == 0 {
            cancelPendingLock(clearBackgroundDate: true)
            observedSceneTransitionDuringTrustedPresentation = false
            trustedBackgroundedAt = nil
        }
        trustedSystemPresentationDepth += 1
    }

    func endTrustedSystemPresentation(lockIfStillBackgrounded: Bool) {
        guard trustedSystemPresentationDepth > 0 else { return }

        trustedSystemPresentationDepth -= 1
        guard trustedSystemPresentationDepth == 0 else { return }

        let shouldStartLockCountdown = lockIfStillBackgrounded
            && observedSceneTransitionDuringTrustedPresentation
            && currentState == .unlocked
        let transitionDate = trustedBackgroundedAt ?? Date()

        observedSceneTransitionDuringTrustedPresentation = false
        trustedBackgroundedAt = nil

        if shouldStartLockCountdown {
            beginLockCountdown(startedAt: transitionDate)
        } else {
            cancelPendingLock(clearBackgroundDate: true)
        }
    }

    func appEnteredBackground(at date: Date = Date()) {
        if trustedSystemPresentationDepth > 0 {
            observedSceneTransitionDuringTrustedPresentation = true
            if trustedBackgroundedAt == nil {
                trustedBackgroundedAt = date
            }
            return
        }

        guard currentState == .unlocked else { return }
        guard backgroundedAt == nil else { return }
        beginLockCountdown(startedAt: date)
    }

    func appBecameActive(at date: Date = Date()) {
        guard trustedSystemPresentationDepth == 0 else { return }
        guard let backgroundedAt else {
            pendingLockTask?.cancel()
            pendingLockTask = nil
            return
        }

        pendingLockTask?.cancel()
        pendingLockTask = nil
        self.backgroundedAt = nil

        let delay = max(autoLockDelayProvider(), 0)
        let elapsed = max(date.timeIntervalSince(backgroundedAt), 0)
        if currentState == .unlocked, delay == 0 || elapsed >= delay {
            currentState = .locked
        }
    }

    private func beginLockCountdown(startedAt: Date) {
        guard currentState == .unlocked else { return }

        let delay = max(autoLockDelayProvider(), 0)
        pendingLockTask?.cancel()
        pendingLockTask = nil
        backgroundedAt = startedAt

        if delay == 0 {
            lockImmediately()
            return
        }

        let remaining = delay - max(Date().timeIntervalSince(startedAt), 0)
        guard remaining > 0 else {
            lockImmediately()
            return
        }

        let nanoseconds = UInt64(remaining * 1_000_000_000)
        pendingLockTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self else { return }
            guard self.trustedSystemPresentationDepth == 0,
                  self.backgroundedAt != nil,
                  self.currentState == .unlocked else { return }
            self.lockImmediately()
        }
    }

    private func lockImmediately() {
        pendingLockTask?.cancel()
        pendingLockTask = nil
        backgroundedAt = nil
        currentState = .locked
    }

    private func cancelPendingLock(clearBackgroundDate: Bool) {
        pendingLockTask?.cancel()
        pendingLockTask = nil
        if clearBackgroundDate {
            backgroundedAt = nil
        }
    }

    func passcodeSetupEntered(_ passcode: String) {
        guard installationPreparationResult != .preparationFailed else { return }
        guard PasscodeValidator.isValidPasscode(passcode) else { return }
        tempPasscode = passcode
        setupError = nil
        currentState = .needsPasscodeConfirmation
    }

    func confirmPasscode(_ passcode: String) -> Bool {
        guard installationPreparationResult != .preparationFailed else { return false }
        guard PasscodeValidator.isValidPasscode(passcode) else { return false }

        if passcode == tempPasscode {
            do {
                try passcodeStore.savePasscode(passcode)
                clearTemporaryPasscode()
                currentState = .needsFaceIDChoice
                return true
            } catch {
                clearTemporaryPasscode()
                setupError = "Unable to save your passcode. Please try again."
                currentState = .needsPasscodeSetup
                return false
            }
        } else {
            clearTemporaryPasscode()
            setupError = "Passcodes do not match. Create your passcode again."
            currentState = .needsPasscodeSetup
            return false
        }
    }

    func faceIDChoiceMade() {
        cancelPendingLock(clearBackgroundDate: true)
        currentState = .unlocked
    }

    func verifyAndUnlock(passcode: String) -> PasscodeVerificationResult {
        guard PasscodeValidator.isValidPasscode(passcode) else {
            return .invalidInput
        }

        do {
            let isValid = try passcodeStore.verifyPasscode(passcode)
            if isValid {
                cancelPendingLock(clearBackgroundDate: true)
                currentState = .unlocked
                return .success
            } else {
                return .incorrect
            }
        } catch {
            return .storageUnavailable
        }
    }

    func unlockSuccessfully() {
        cancelPendingLock(clearBackgroundDate: true)
        currentState = .unlocked
    }

    /// Verifies a sensitive settings change without destroying the current navigation state.
    /// The trusted-presentation guard prevents the Face ID system sheet from triggering auto-lock.
    func verifyOwnerWithFaceID(
        reason: String,
        completion: @escaping (BiometricAuthResult) -> Void
    ) {
        beginTrustedSystemPresentation()
        biometricService.authenticate(reason: reason) { [weak self] result in
            guard let self else {
                completion(.notAvailable)
                return
            }

            self.endTrustedSystemPresentation(lockIfStillBackgrounded: false)
            completion(result)
        }
    }

    private func clearTemporaryPasscode() {
        tempPasscode = ""
    }

    func clearSetupError() {
        setupError = nil
    }
}
