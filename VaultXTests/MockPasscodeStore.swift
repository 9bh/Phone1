import Foundation
@testable import VaultX

class MockPasscodeStore: PasscodeStore {
    var storedPasscode: String? = nil
    var unrelatedEntries: [String: String] = ["com.otherapp": "secret"]
    
    var shouldFailSave = false
    var shouldFailVerify = false
    var shouldFailDelete = false
    var deleteCallCount = 0
    
    func hasPasscode() throws -> Bool {
        return storedPasscode != nil
    }
    
    func savePasscode(_ passcode: String) throws {
        if shouldFailSave {
            throw PasscodeStoreError.keychainFailure(-50)
        }
        guard PasscodeValidator.isValidPasscode(passcode) else {
            throw PasscodeStoreError.invalidPasscode
        }
        storedPasscode = passcode
    }
    
    func verifyPasscode(_ passcode: String) throws -> Bool {
        if shouldFailVerify {
            throw PasscodeStoreError.keychainFailure(-50)
        }
        guard PasscodeValidator.isValidPasscode(passcode) else {
            return false
        }
        return storedPasscode == passcode
    }
    
    func deletePasscode() throws {
        deleteCallCount += 1
        if shouldFailDelete {
            throw PasscodeStoreError.keychainFailure(-50)
        }
        // Only delete the VaultX passcode entry
        storedPasscode = nil
    }
}

class MockAppInstallationService: AppInstallationService {
    var freshInstall = false
    
    override func isFreshInstall() -> Bool {
        return freshInstall
    }
    
    override func markAsInstalled() {
        freshInstall = false
    }
}

class MockBiometricService: BiometricAuthenticating {
    var available = true
    var result: BiometricAuthResult = .success
    var authenticateCallCount = 0
    
    func canEvaluateFaceID() -> Bool {
        return available
    }
    
    func authenticate(reason: String, completion: @escaping (BiometricAuthResult) -> Void) {
        authenticateCallCount += 1
        completion(result)
    }
}

class MockFaceIDPreferenceStore: FaceIDPreferenceStore {
    var isFaceIDEnabled: Bool = false
}
