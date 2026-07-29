import Foundation
import CryptoKit

actor EncryptedVaultAccountsPersistence: VaultAccountsPersisting {
    private let keyStore: VaultEncryptionKeyStoring
    private let filesystem: VaultFilesystemClient
    private let baseDirectoryURL: URL?
    
    private let gate = AsyncFIFOTransactionGate()
    
    init(keyStore: VaultEncryptionKeyStoring, filesystem: VaultFilesystemClient, baseDirectoryURL: URL? = nil) {
        self.keyStore = keyStore
        self.filesystem = filesystem
        self.baseDirectoryURL = baseDirectoryURL
    }
    
    private func getBaseDirectoryURL() async throws -> URL {
        if let url = baseDirectoryURL { return url }
        return try await filesystem.applicationSupportURL().appendingPathComponent("VaultX", isDirectory: true)
    }
    
    private func vaultFileURL() async throws -> URL {
        try await getBaseDirectoryURL().appendingPathComponent("vault-accounts.v1")
    }
    
    private func authenticatedData(for version: UInt16) throws -> Data {
        guard let data = "VaultX.Accounts.v\(version)".data(using: .utf8) else {
            throw VaultPersistenceError.encodingFailed
        }
        return data
    }
    
    func vaultExists() async throws -> Bool {
        let url = try await vaultFileURL()
        return await filesystem.fileExists(atPath: url.path)
    }
    
    func loadAccounts() async throws -> [VaultAccount] {
        let url = try await vaultFileURL()
        if await !filesystem.fileExists(atPath: url.path) {
            return []
        }
        
        guard let key = try await keyStore.loadKey() else {
            throw VaultPersistenceError.missingEncryptionKeyForExistingVault
        }
        
        let encryptedData: Data
        do {
            encryptedData = try await filesystem.readData(from: url)
        } catch {
            throw VaultPersistenceError.fileReadFailed
        }
        
        let envelope: VaultFileEnvelope
        do {
            envelope = try PropertyListDecoder().decode(VaultFileEnvelope.self, from: encryptedData)
        } catch {
            throw VaultPersistenceError.invalidEnvelope
        }
        
        guard envelope.formatVersion == 1 else {
            throw VaultPersistenceError.unsupportedVaultFormatVersion(envelope.formatVersion)
        }
        
        let aad = try authenticatedData(for: envelope.formatVersion)
        
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: envelope.sealedPayload)
        } catch {
            throw VaultPersistenceError.invalidSealedData
        }
        
        let decryptedData: Data
        do {
            decryptedData = try AES.GCM.open(sealedBox, using: key, authenticating: aad)
        } catch {
            throw VaultPersistenceError.decryptionFailed
        }
        
        do {
            return try JSONDecoder().decode([VaultAccount].self, from: decryptedData)
        } catch {
            throw VaultPersistenceError.decodingFailed
        }
    }
    
    func saveAccounts(_ accounts: [VaultAccount]) async throws {
        try await gate.withLock {
            try await performSave(accounts)
        }
    }
    
    private func performSave(_ accounts: [VaultAccount]) async throws {
        let url = try await vaultFileURL()
        let vaultExists = await filesystem.fileExists(atPath: url.path)
        let existingKey = try await keyStore.loadKey()
        
        if vaultExists && existingKey == nil {
            throw VaultPersistenceError.missingEncryptionKeyForExistingVault
        }
        
        let key: SymmetricKey
        if let existing = existingKey {
            key = existing
        } else {
            let generatedKey = SymmetricKey(size: .bits256)
            key = try await keyStore.saveNewKey(generatedKey)
        }
        
        let accountData: Data
        do {
            accountData = try JSONEncoder().encode(accounts)
        } catch {
            throw VaultPersistenceError.encodingFailed
        }
        
        let aad = try authenticatedData(for: 1)
        
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.seal(accountData, using: key, authenticating: aad)
        } catch {
            throw VaultPersistenceError.encodingFailed
        }
        
        guard let combined = sealedBox.combined else {
            throw VaultPersistenceError.sealedRepresentationUnavailable
        }
        
        let envelope = VaultFileEnvelope(formatVersion: 1, sealedPayload: combined)
        let envelopeData: Data
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            envelopeData = try encoder.encode(envelope)
        } catch {
            throw VaultPersistenceError.encodingFailed
        }
        
        let baseDir = try await getBaseDirectoryURL()
        if await !filesystem.fileExists(atPath: baseDir.path) {
            do {
                try await filesystem.createDirectory(at: baseDir, withIntermediateDirectories: true)
            } catch {
                throw VaultPersistenceError.directoryCreationFailed
            }
        }
        
        let uuid = UUID().uuidString
        let tempURL = baseDir.appendingPathComponent("vault-accounts-\(uuid).tmp")
        let backupName = "vault-accounts-\(uuid).backup"
        let backupURL = baseDir.appendingPathComponent(backupName)
        
        do {
            try await filesystem.writeData(envelopeData, to: tempURL)
        } catch {
            throw VaultPersistenceError.temporaryFileWriteFailed
        }
        
        do {
            try await applyProtectionAndBackupExclusion(to: tempURL)
            try await verifyProtectionAndExclusion(at: tempURL)
        } catch let tempError {
            do {
                try await filesystem.removeItem(at: tempURL)
            } catch {
                // If cleanup fails on an orphan temp file, the committed vault remains authoritative.
            }
            throw tempError
        }
        
        if vaultExists {
            let replacedURL: URL?
            do {
                replacedURL = try await filesystem.replaceItemAt(url, withItemAt: tempURL, backupItemName: backupName)
            } catch {
                do {
                    try await filesystem.removeItem(at: tempURL)
                } catch {
                    // orphan temp cleanup failure does not change authoritative state
                }
                throw VaultPersistenceError.atomicReplacementFailed
            }
            
            let finalURL = replacedURL ?? url
            
            do {
                if await !filesystem.fileExists(atPath: backupURL.path) {
                    throw VaultPersistenceError.commitStateUnknown // backup must exist
                }
                try await applyProtectionAndBackupExclusion(to: backupURL)
                try await verifyProtectionAndExclusion(at: backupURL)
                try await verifyProtectionAndExclusion(at: finalURL)
                
                do {
                    try await filesystem.removeItem(at: backupURL)
                } catch {
                    // Orphan backup file does not change the authoritative state
                }
            } catch let validationError {
                do {
                    _ = try await filesystem.replaceItemAt(finalURL, withItemAt: backupURL, backupItemName: nil)
                    try await verifyProtectionAndExclusion(at: url)
                } catch {
                    throw VaultPersistenceError.commitStateUnknown
                }
                do {
                    try await filesystem.removeItem(at: tempURL)
                } catch { }
                do {
                    try await filesystem.removeItem(at: backupURL)
                } catch { }
                throw validationError
            }
        } else {
            do {
                try await filesystem.moveItem(at: tempURL, to: url)
            } catch {
                do {
                    try await filesystem.removeItem(at: tempURL)
                } catch { }
                throw VaultPersistenceError.atomicReplacementFailed
            }
            
            do {
                try await verifyProtectionAndExclusion(at: url)
            } catch let validationError {
                do {
                    try await filesystem.removeItem(at: url)
                } catch {
                    throw VaultPersistenceError.commitStateUnknown
                }
                throw validationError
            }
        }
    }
    
    private func applyProtectionAndBackupExclusion(to url: URL) async throws {
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true
        do {
            try await filesystem.setResourceValues(rv, for: url)
        } catch {
            throw VaultPersistenceError.backupExclusionFailed
        }
        
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
        do {
            try await filesystem.setAttributes(attributes, ofItemAtPath: url.path)
        } catch {
            throw VaultPersistenceError.fileProtectionFailed
        }
    }
    
    private func verifyProtectionAndExclusion(at url: URL) async throws {
        do {
            let rv = try await filesystem.resourceValues(forKeys: [.isExcludedFromBackupKey], for: url)
            if rv.isExcludedFromBackup != true {
                throw VaultPersistenceError.backupExclusionFailed
            }
        } catch {
            throw VaultPersistenceError.backupExclusionFailed
        }
        
        do {
            let attributes = try await filesystem.attributesOfItem(atPath: url.path)
            guard let protection = attributes[.protectionKey] as? FileProtectionType,
                  protection == .complete else {
                throw VaultPersistenceError.fileProtectionFailed
            }
        } catch {
            throw VaultPersistenceError.fileProtectionFailed
        }
    }
}
