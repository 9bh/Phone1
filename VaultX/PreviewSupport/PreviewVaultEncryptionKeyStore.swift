import Foundation
import CryptoKit
import Security

actor PreviewVaultEncryptionKeyStore: VaultEncryptionKeyStoring, VaultEncryptionKeyResetting {
    private var key: SymmetricKey?
    
    private var failsRead = false
    private var failsWrite = false
    private var returnsInvalidData = false
    
    private var emulateDuplicateAdd = false
    private var duplicateItemButMissing = false
    
    private var simulateRaceExistingKey: SymmetricKey?
    
    func loadKey() async throws -> SymmetricKey? {
        if failsRead { throw VaultPersistenceError.keychainReadFailed(errSecNotAvailable) }
        if returnsInvalidData { throw VaultPersistenceError.invalidEncryptionKeyData }
        return key
    }
    
    func saveNewKey(_ proposedKey: SymmetricKey) async throws -> SymmetricKey {
        if failsWrite { throw VaultPersistenceError.keychainWriteFailed(errSecNotAvailable) }
        
        if emulateDuplicateAdd {
            if duplicateItemButMissing {
                throw VaultPersistenceError.keychainDuplicateItemButKeyMissing
            }
            if returnsInvalidData {
                throw VaultPersistenceError.invalidEncryptionKeyData
            }
            if let existing = key {
                return existing
            } else if let simulated = simulateRaceExistingKey {
                // Return the simulated existing key without replacing our actual `key` because a duplicate wouldn't override.
                // Wait, if it's the authoritative key from a duplicate add, we should adopt it.
                key = simulated
                return simulated
            } else {
                throw VaultPersistenceError.keychainDuplicateItemButKeyMissing
            }
        }
        
        if key == nil {
            key = proposedKey
        }
        return key!
    }
    
    func deleteKeyForVerifiedFreshInstall() async throws {
        key = nil
    }
    
    func setFailsRead(_ fails: Bool) { failsRead = fails }
    func setFailsWrite(_ fails: Bool) { failsWrite = fails }
    func setReturnsInvalidData(_ fails: Bool) { returnsInvalidData = fails }
    func setEmulateDuplicateAdd(_ emulate: Bool) { emulateDuplicateAdd = emulate }
    func setDuplicateItemButMissing(_ missing: Bool) { duplicateItemButMissing = missing }
    func setSimulateRaceExisting(_ key: SymmetricKey) { simulateRaceExistingKey = key }
}
