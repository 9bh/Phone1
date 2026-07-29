import Foundation

actor ProductionPasscodeVerifierResetter: PasscodeVerifierResetting {
    private let keychainClient: VaultKeychainClient
    
    init(keychainClient: VaultKeychainClient = ProductionVaultKeychainClient()) {
        self.keychainClient = keychainClient
    }
    
    func deletePasscodeVerifierForVerifiedFreshInstall() async throws {
        try await keychainClient.deleteData(service: "com.vaultx.app", account: "vault-passcode")
    }
}
