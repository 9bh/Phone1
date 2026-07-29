import Foundation

protocol VaultEncryptionKeyResetting: Sendable {
    func deleteKeyForVerifiedFreshInstall() async throws
}
