import Foundation

protocol VaultAccountsPersisting: Sendable {
    func vaultExists() async throws -> Bool
    func loadAccounts() async throws -> [VaultAccount]
    func saveAccounts(_ accounts: [VaultAccount]) async throws
}
