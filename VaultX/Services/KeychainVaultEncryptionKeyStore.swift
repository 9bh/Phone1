import Foundation
import Security
import CryptoKit

actor KeychainVaultEncryptionKeyStore: VaultEncryptionKeyStoring, VaultEncryptionKeyResetting {
    private let service = "com.vaultx.app"
    private let account = "vault-accounts-encryption-key-v1"
    private let client: VaultKeychainClient
    
    init(client: VaultKeychainClient = ProductionVaultKeychainClient()) {
        self.client = client
    }
    
    func loadKey() async throws -> SymmetricKey? {
        let data = try await client.readData(service: service, account: account)
        guard let data = data else { return nil }
        
        guard data.count == 32 else {
            throw VaultPersistenceError.invalidEncryptionKeyData
        }
        
        return SymmetricKey(data: data)
    }
    
    func saveNewKey(_ proposedKey: SymmetricKey) async throws -> SymmetricKey {
        let keyData = proposedKey.withUnsafeBytes { Data($0) }
        let result = try await client.addData(keyData, service: service, account: account, accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        
        switch result {
        case .success:
            return proposedKey
        case .duplicate:
            guard let existingData = try await client.readData(service: service, account: account) else {
                throw VaultPersistenceError.keychainDuplicateItemButKeyMissing
            }
            guard existingData.count == 32 else {
                throw VaultPersistenceError.invalidEncryptionKeyData
            }
            return SymmetricKey(data: existingData)
        case .failure(let status):
            throw VaultPersistenceError.keychainWriteFailed(status)
        }
    }
    
    func deleteKeyForVerifiedFreshInstall() async throws {
        try await client.deleteData(service: service, account: account)
    }
}
