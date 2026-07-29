import Foundation

#if DEBUG
class PreviewPasscodeStore: PasscodeStore {
    var storedPasscode: String? = nil

    func hasPasscode() throws -> Bool {
        storedPasscode != nil
    }

    func savePasscode(_ passcode: String) throws {
        storedPasscode = passcode
    }

    func verifyPasscode(_ passcode: String) throws -> Bool {
        storedPasscode == passcode
    }

    func deletePasscode() throws {
        storedPasscode = nil
    }
}

class PreviewInstallationService: AppInstallationService {
    override func isFreshInstall() -> Bool {
        false
    }

    override func markAsInstalled() {}
}

class PreviewBiometricService: BiometricAuthenticating {
    var available = true
    var result: BiometricAuthResult = .success

    func canEvaluateFaceID() -> Bool {
        available
    }

    func authenticate(
        reason: String,
        completion: @escaping (BiometricAuthResult) -> Void
    ) {
        completion(result)
    }
}

class PreviewFaceIDPreferences: FaceIDPreferenceStore {
    var isFaceIDEnabled: Bool = false
}

extension VaultAccountsStore {
    @MainActor
    static func preview(
        accounts: [VaultAccount] = [],
        loadState: SecureVaultLoadState = .loaded,
        simulateFailure: Bool = false
    ) -> VaultAccountsStore {
        let shouldFailLoad = simulateFailure || loadState == .failed
        let persistence = PreviewVaultAccountsPersistence(
            initialAccounts: accounts,
            failsLoad: shouldFailLoad
        )
        let store = VaultAccountsStore(persistence: persistence)

        if loadState != .locked {
            Task {
                await store.unlockAndLoad()
            }
        }

        return store
    }
}
#endif
