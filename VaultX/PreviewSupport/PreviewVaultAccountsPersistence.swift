import Foundation

actor PreviewVaultAccountsPersistence: VaultAccountsPersisting {
    private var accounts: [VaultAccount]?
    private var failsLoad = false
    private var failsSave = false
    
    init(initialAccounts: [VaultAccount]? = nil) {
        self.accounts = initialAccounts
    }
    
    func setFailsLoad(_ value: Bool) { failsLoad = value }
    func setFailsSave(_ value: Bool) { failsSave = value }
    
    func vaultExists() async throws -> Bool {
        return accounts != nil
    }
    
    func loadAccounts() async throws -> [VaultAccount] {
        if failsLoad { throw VaultPersistenceError.fileReadFailed }
        return accounts ?? []
    }
    
    func saveAccounts(_ accounts: [VaultAccount]) async throws {
        if failsSave { throw VaultPersistenceError.temporaryFileWriteFailed }
        self.accounts = accounts
    }
}
