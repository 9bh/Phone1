import Foundation
import CryptoKit

protocol VaultEncryptionKeyStoring: Sendable {
    func loadKey() async throws -> SymmetricKey?
    func saveNewKey(_ proposedKey: SymmetricKey) async throws -> SymmetricKey
}
