import Foundation

#if DEBUG
class PreviewPasscodeStore: PasscodeStore {
    var storedPasscode: String? = nil
    
    func hasPasscode() throws -> Bool {
        return storedPasscode != nil
    }
    
    func savePasscode(_ passcode: String) throws {
        storedPasscode = passcode
    }
    
    func verifyPasscode(_ passcode: String) throws -> Bool {
        return storedPasscode == passcode
    }
    
    func deletePasscode() throws {
        storedPasscode = nil
    }
}

class PreviewInstallationService: AppInstallationService {
    override func isFreshInstall() -> Bool {
        return false
    }
    
    override func markAsInstalled() {}
}

class PreviewBiometricService: BiometricAuthenticating {
    var available = true
    var result: BiometricAuthResult = .success
    
    func canEvaluateFaceID() -> Bool {
        return available
    }
    
    func authenticate(reason: String, completion: @escaping (BiometricAuthResult) -> Void) {
        completion(result)
    }
}

class PreviewFaceIDPreferences: FaceIDPreferenceStore {
    var isFaceIDEnabled: Bool = false
}
#endif
