import Foundation
import CryptoKit
import Security

enum PasscodeStoreError: Error, Equatable {
    case invalidPasscode
    case randomGenerationFailed(OSStatus)
    case keychainFailure(OSStatus)
    case malformedStoredData
}

protocol PasscodeStore {
    func hasPasscode() throws -> Bool
    func savePasscode(_ passcode: String) throws
    func verifyPasscode(_ passcode: String) throws -> Bool
    func deletePasscode() throws
}

class PasscodeKeychainService: PasscodeStore {
    private let service = "com.vaultx.app"
    private let account = "vault-passcode"
    private let saltLength = 32
    
    func hasPasscode() throws -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            return true
        } else if status == errSecItemNotFound {
            return false
        } else {
            throw PasscodeStoreError.keychainFailure(status)
        }
    }
    
    func savePasscode(_ passcode: String) throws {
        guard PasscodeValidator.isValidPasscode(passcode) else {
            throw PasscodeStoreError.invalidPasscode
        }
        
        let salt = try generateSalt()
        let verifier = deriveVerifier(passcode: passcode, salt: salt)
        
        var payload = Data()
        payload.append(salt)
        payload.append(verifier)
        
        try deletePasscode() // Ensure no stale entry
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: payload,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw PasscodeStoreError.keychainFailure(status)
        }
    }
    
    func verifyPasscode(_ passcode: String) throws -> Bool {
        guard PasscodeValidator.isValidPasscode(passcode) else {
            return false
        }
        
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
            return false
        }
        
        guard status == errSecSuccess else {
            throw PasscodeStoreError.keychainFailure(status)
        }
        
        guard let data = dataTypeRef as? Data else {
            throw PasscodeStoreError.malformedStoredData
        }
        
        guard data.count > saltLength else { 
            throw PasscodeStoreError.malformedStoredData
        }
        
        let savedSalt = Data(data.prefix(saltLength))
        let savedVerifier = Data(data.dropFirst(saltLength))
        
        let computedVerifier = deriveVerifier(passcode: passcode, salt: savedSalt)
        
        return constantTimeCompare(savedVerifier, computedVerifier)
    }
    
    func deletePasscode() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PasscodeStoreError.keychainFailure(status)
        }
    }
    
    // MARK: - Private Helpers
    
    private func generateSalt() throws -> Data {
        var randomBytes = [UInt8](repeating: 0, count: saltLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, saltLength, &randomBytes)
        
        guard status == errSecSuccess else {
            throw PasscodeStoreError.randomGenerationFailed(status)
        }
        return Data(randomBytes)
    }
    
    private func deriveVerifier(passcode: String, salt: Data) -> Data {
        var dataToHash = salt
        if let passcodeData = passcode.data(using: .utf8) {
            dataToHash.append(passcodeData)
        }
        let hash = SHA256.hash(data: dataToHash)
        return Data(hash)
    }
    
    private func constantTimeCompare(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        
        var difference: UInt8 = 0
        for (leftByte, rightByte) in zip(lhs, rhs) {
            difference |= leftByte ^ rightByte
        }
        
        return difference == 0
    }
}
