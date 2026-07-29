import Foundation
import Security

struct ProductionVaultKeychainClient: VaultKeychainClient {
    func readData(service: String, account: String) async throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw VaultPersistenceError.keychainReadFailed(status)
        }
        
        guard let data = dataTypeRef as? Data else {
            throw VaultPersistenceError.keychainReadFailed(errSecItemNotFound)
        }
        
        return data
    }
    
    func addData(_ data: Data, service: String, account: String, accessibility: CFString) async throws -> VaultKeychainAddResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            return .success
        } else if status == errSecDuplicateItem {
            return .duplicate
        } else {
            return .failure(status)
        }
    }
    
    func deleteData(service: String, account: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        try Self.validateDeleteStatus(status)
    }
    
    static func validateDeleteStatus(_ status: OSStatus) throws {
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }
        throw VaultPersistenceError.keychainDeleteFailed(status)
    }
}
