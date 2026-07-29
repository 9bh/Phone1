import Foundation
import Security

enum VaultPersistenceError: Error, Equatable, Sendable {
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)
    case invalidEncryptionKeyData
    case missingEncryptionKeyForExistingVault
    case keychainDuplicateItemButKeyMissing
    case unsupportedVaultFormatVersion(UInt16)
    case invalidEnvelope
    case sealedRepresentationUnavailable
    case invalidSealedData
    case decryptionFailed
    case encodingFailed
    case decodingFailed
    case applicationSupportUnavailable
    case directoryCreationFailed
    case fileReadFailed
    case temporaryFileWriteFailed
    case fileProtectionFailed
    case backupExclusionFailed
    case atomicReplacementFailed
    case atomicRecoveryFailed
    case commitStateUnknown
    case existingVaultWithMissingInstallationMarker
}
