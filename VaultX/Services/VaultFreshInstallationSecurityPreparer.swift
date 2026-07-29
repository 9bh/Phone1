import Foundation

actor VaultFreshInstallationSecurityPreparer: FreshInstallationSecurityPreparing {
    private let markerStore: InstallationMarkerStoring
    private let passcodeResetter: PasscodeVerifierResetting
    private let keyResetter: VaultEncryptionKeyResetting
    private let vaultPersistence: VaultAccountsPersisting
    
    init(
        markerStore: InstallationMarkerStoring,
        passcodeResetter: PasscodeVerifierResetting,
        keyResetter: VaultEncryptionKeyResetting,
        vaultPersistence: VaultAccountsPersisting
    ) {
        self.markerStore = markerStore
        self.passcodeResetter = passcodeResetter
        self.keyResetter = keyResetter
        self.vaultPersistence = vaultPersistence
    }
    
    func prepareVerifiedFreshInstallation() async throws {
        if try await markerStore.isInstallationMarked() {
            return
        }
        
        let vaultExists = try await vaultPersistence.vaultExists()
        
        if vaultExists {
            throw VaultPersistenceError.existingVaultWithMissingInstallationMarker
        }
        
        try await passcodeResetter.deletePasscodeVerifierForVerifiedFreshInstall()
        try await keyResetter.deleteKeyForVerifiedFreshInstall()
        
        try await markerStore.markInstallationCompleted()
    }
}
