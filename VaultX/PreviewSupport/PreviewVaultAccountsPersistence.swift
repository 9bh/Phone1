import Foundation

actor PreviewVaultAccountsPersistence: VaultAccountsPersisting {
    private var storedAccounts: [VaultAccount]
    private var failsLoad: Bool
    private var failsSave: Bool

    init(
        initialAccounts: [VaultAccount] = [],
        failsLoad: Bool = false,
        failsSave: Bool = false
    ) {
        self.storedAccounts = initialAccounts
        self.failsLoad = failsLoad
        self.failsSave = failsSave
    }

    func setFailsLoad(_ value: Bool) {
        failsLoad = value
    }

    func setFailsSave(_ value: Bool) {
        failsSave = value
    }

    func replaceAccounts(_ accounts: [VaultAccount]) {
        storedAccounts = accounts
    }

    func snapshot() -> [VaultAccount] {
        storedAccounts
    }

    func vaultExists() async throws -> Bool {
        !storedAccounts.isEmpty
    }

    func loadAccounts() async throws -> [VaultAccount] {
        if failsLoad {
            throw VaultPersistenceError.fileReadFailed
        }
        return storedAccounts
    }

    func saveAccounts(_ accounts: [VaultAccount]) async throws {
        if failsSave {
            throw VaultPersistenceError.temporaryFileWriteFailed
        }
        storedAccounts = accounts
    }
}
