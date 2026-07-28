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
    
    private let passcodeStore: PasscodeStore
    private let installationService: AppInstallationService
    let biometricService: BiometricAuthenticating
    var faceIDPreferences: FaceIDPreferenceStore
    
    init(
        passcodeStore: PasscodeStore = PasscodeKeychainService(),
        installationService: AppInstallationService = AppInstallationService(),
        biometricService: BiometricAuthenticating = BiometricAuthenticationService(),
        faceIDPreferences: FaceIDPreferenceStore = UserDefaultsFaceIDPreferenceStore()
    ) {
        self.passcodeStore = passcodeStore
        self.installationService = installationService
        self.biometricService = biometricService
        self.faceIDPreferences = faceIDPreferences
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
    
    func appEnteredBackground() {
        if currentState == .unlocked {
            currentState = .locked
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
        currentState = .unlocked
    }
    
    func verifyAndUnlock(passcode: String) -> PasscodeVerificationResult {
        guard PasscodeValidator.isValidPasscode(passcode) else {
            return .invalidInput
        }
        
        do {
            let isValid = try passcodeStore.verifyPasscode(passcode)
            if isValid {
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
        currentState = .unlocked
    }
    
    private func clearTemporaryPasscode() {
        tempPasscode = ""
    }
    
    func clearSetupError() {
        setupError = nil
    }
}
