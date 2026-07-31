import XCTest
@testable import VaultX

private actor TestAsyncLatch {
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isSignaled {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        guard !isSignaled else { return }
        isSignaled = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor TestVaultAccountsPersistence: VaultAccountsPersisting {
    private var storedAccounts: [VaultAccount]
    private var loadError: VaultPersistenceError?
    private var saveError: VaultPersistenceError?
    private var loadStartedLatch: TestAsyncLatch?
    private var loadReleaseLatch: TestAsyncLatch?
    private var saveStartedLatch: TestAsyncLatch?
    private var saveReleaseLatch: TestAsyncLatch?

    init(accounts: [VaultAccount] = []) {
        storedAccounts = accounts
    }

    func vaultExists() async throws -> Bool {
        !storedAccounts.isEmpty
    }

    func loadAccounts() async throws -> [VaultAccount] {
        let started = loadStartedLatch
        let release = loadReleaseLatch
        let error = loadError

        if let started {
            await started.signal()
        }
        if let release {
            await release.wait()
        }
        if let error {
            throw error
        }

        return storedAccounts
    }

    func saveAccounts(_ accounts: [VaultAccount]) async throws {
        let started = saveStartedLatch
        let release = saveReleaseLatch
        let error = saveError

        if let started {
            await started.signal()
        }
        if let release {
            await release.wait()
        }
        if let error {
            throw error
        }

        storedAccounts = accounts
    }

    func setAccounts(_ accounts: [VaultAccount]) {
        storedAccounts = accounts
    }

    func snapshot() -> [VaultAccount] {
        storedAccounts
    }

    func setLoadError(_ error: VaultPersistenceError?) {
        loadError = error
    }

    func setSaveError(_ error: VaultPersistenceError?) {
        saveError = error
    }

    func suspendNextLoad(
        started: TestAsyncLatch,
        release: TestAsyncLatch
    ) {
        loadStartedLatch = started
        loadReleaseLatch = release
    }

    func suspendNextSave(
        started: TestAsyncLatch,
        release: TestAsyncLatch
    ) {
        saveStartedLatch = started
        saveReleaseLatch = release
    }
}

@MainActor
final class VaultAccountsStoreTests: XCTestCase {
    private func makeAccount(
        id: UUID = UUID(),
        siteURL: String = "example.com"
    ) -> VaultAccount {
        VaultAccount(
            id: id,
            siteURL: siteURL,
            email: "user@example.com",
            password: "secret",
            username: "user",
            notes: "note",
            has2FA: false,
            hasBackupFile: false
        )
    }

    func testStoreStartsLockedWithEmptyAccounts() {
        let persistence = TestVaultAccountsPersistence()
        let store = VaultAccountsStore(persistence: persistence)

        XCTAssertEqual(store.loadState, .locked)
        XCTAssertTrue(store.accounts.isEmpty)
    }

    func testUnlockLoadsAccounts() async {
        let account = makeAccount()
        let persistence = TestVaultAccountsPersistence(accounts: [account])
        let store = VaultAccountsStore(persistence: persistence)

        await store.unlockAndLoad()

        XCTAssertEqual(store.loadState, .loaded)
        XCTAssertEqual(store.accounts, [account])
    }

    func testSecondUnlockDoesNotDuplicateAccounts() async {
        let account = makeAccount()
        let persistence = TestVaultAccountsPersistence(accounts: [account])
        let store = VaultAccountsStore(persistence: persistence)

        await store.unlockAndLoad()
        await store.unlockAndLoad()

        XCTAssertEqual(store.accounts, [account])
    }

    func testLockClearsObservableAccounts() async {
        let account = makeAccount()
        let persistence = TestVaultAccountsPersistence(accounts: [account])
        let store = VaultAccountsStore(persistence: persistence)

        await store.unlockAndLoad()
        store.lockAndClear()

        XCTAssertEqual(store.loadState, .locked)
        XCTAssertTrue(store.accounts.isEmpty)
    }

    func testLockDuringLoadNeverPublishesAccounts() async {
        let account = makeAccount()
        let started = TestAsyncLatch()
        let release = TestAsyncLatch()
        let persistence = TestVaultAccountsPersistence(accounts: [account])
        await persistence.suspendNextLoad(started: started, release: release)
        let store = VaultAccountsStore(persistence: persistence)

        let loadTask = Task {
            await store.unlockAndLoad()
        }

        await started.wait()
        store.lockAndClear()
        await release.signal()
        await loadTask.value

        XCTAssertEqual(store.loadState, .locked)
        XCTAssertTrue(store.accounts.isEmpty)
    }

    func testLoadFailureKeepsAccountsEmptyAndBlocksMutations() async {
        let persistence = TestVaultAccountsPersistence()
        await persistence.setLoadError(.fileReadFailed)
        let store = VaultAccountsStore(persistence: persistence)

        await store.unlockAndLoad()
        let result = await store.addAccount(makeAccount())

        XCTAssertEqual(store.loadState, .failed)
        XCTAssertTrue(store.accounts.isEmpty)

        guard case .failure(let error) = result else {
            return XCTFail("Mutation unexpectedly succeeded")
        }
        XCTAssertEqual(error, .storeNotLoaded)
    }

    func testRetryAfterTransientLoadFailureSucceeds() async {
        let account = makeAccount()
        let persistence = TestVaultAccountsPersistence(accounts: [account])
        await persistence.setLoadError(.fileReadFailed)
        let store = VaultAccountsStore(persistence: persistence)

        await store.unlockAndLoad()
        XCTAssertEqual(store.loadState, .failed)

        await persistence.setLoadError(nil)
        await store.retryLoad()

        XCTAssertEqual(store.loadState, .loaded)
        XCTAssertEqual(store.accounts, [account])
    }

    func testAddPersistsAcrossStoreInstances() async {
        let account = makeAccount()
        let persistence = TestVaultAccountsPersistence()
        let store = VaultAccountsStore(persistence: persistence)

        await store.unlockAndLoad()
        let result = await store.addAccount(account)

        guard case .success = result else {
            return XCTFail("Add failed")
        }

        let freshStore = VaultAccountsStore(persistence: persistence)
        await freshStore.unlockAndLoad()
        XCTAssertEqual(freshStore.accounts, [account])
    }

    func testEditPersistsAcrossStoreInstances() async {
        let original = makeAccount()
        var edited = original
        edited.siteURL = "edited.example"

        let persistence = TestVaultAccountsPersistence(accounts: [original])
        let store = VaultAccountsStore(persistence: persistence)

        await store.unlockAndLoad()
        let result = await store.updateAccount(edited)

        guard case .success = result else {
            return XCTFail("Edit failed")
        }

        let freshStore = VaultAccountsStore(persistence: persistence)
        await freshStore.unlockAndLoad()
        XCTAssertEqual(freshStore.accounts, [edited])
    }

    func testDeletePersistsAcrossStoreInstances() async {
        let account = makeAccount()
        let persistence = TestVaultAccountsPersistence(accounts: [account])
        let store = VaultAccountsStore(persistence: persistence)

        await store.unlockAndLoad()
        let result = await store.deleteAccount(id: account.id)

        guard case .success = result else {
            return XCTFail("Delete failed")
        }

        let freshStore = VaultAccountsStore(persistence: persistence)
        await freshStore.unlockAndLoad()
        XCTAssertTrue(freshStore.accounts.isEmpty)
    }

    func testFailedAddRollsBack() async {
        let persistence = TestVaultAccountsPersistence()
        await persistence.setSaveError(.temporaryFileWriteFailed)
        let store = VaultAccountsStore(persistence: persistence)

        await store.unlockAndLoad()
        let result = await store.addAccount(makeAccount())

        guard case .failure(let error) = result else {
            return XCTFail("Add unexpectedly succeeded")
        }
        XCTAssertEqual(error, .saveFailed)
        XCTAssertTrue(store.accounts.isEmpty)
        XCTAssertNotNil(store.storageAlert)
    }

    func testFailedEditRollsBack() async {
        let original = makeAccount()
        var edited = original
        edited.siteURL = "edited.example"

        let persistence = TestVaultAccountsPersistence(accounts: [original])
        await persistence.setSaveError(.temporaryFileWriteFailed)
        let store = VaultAccountsStore(persistence: persistence)

        await store.unlockAndLoad()
        let result = await store.updateAccount(edited)

        guard case .failure(let error) = result else {
            return XCTFail("Edit unexpectedly succeeded")
        }
        XCTAssertEqual(error, .saveFailed)
        XCTAssertEqual(store.accounts, [original])
    }

    func testFailedDeleteRollsBack() async {
        let account = makeAccount()
        let persistence = TestVaultAccountsPersistence(accounts: [account])
        await persistence.setSaveError(.temporaryFileWriteFailed)
        let store = VaultAccountsStore(persistence: persistence)

        await store.unlockAndLoad()
        let result = await store.deleteAccount(id: account.id)

        guard case .failure(let error) = result else {
            return XCTFail("Delete unexpectedly succeeded")
        }
        XCTAssertEqual(error, .saveFailed)
        XCTAssertEqual(store.accounts, [account])
    }

    func testOnlyOneMutationRunsAtATime() async {
        let started = TestAsyncLatch()
        let release = TestAsyncLatch()
        let persistence = TestVaultAccountsPersistence()
        await persistence.suspendNextSave(started: started, release: release)
        let store = VaultAccountsStore(persistence: persistence)
        await store.unlockAndLoad()

        let firstAccount = makeAccount(siteURL: "first.example")
        let secondAccount = makeAccount(siteURL: "second.example")

        let firstTask = Task {
            await store.addAccount(firstAccount)
        }

        await started.wait()
        let secondResult = await store.addAccount(secondAccount)

        guard case .failure(let secondError) = secondResult else {
            return XCTFail("Second mutation unexpectedly succeeded")
        }
        XCTAssertEqual(secondError, .mutationInProgress)

        await release.signal()
        _ = await firstTask.value
        XCTAssertEqual(store.accounts, [firstAccount])
    }

    func testLockDuringSuccessfulSaveDoesNotRepublishAccounts() async {
        let started = TestAsyncLatch()
        let release = TestAsyncLatch()
        let persistence = TestVaultAccountsPersistence()
        await persistence.suspendNextSave(started: started, release: release)
        let store = VaultAccountsStore(persistence: persistence)
        await store.unlockAndLoad()

        let account = makeAccount()
        let saveTask = Task {
            await store.addAccount(account)
        }

        await started.wait()
        store.lockAndClear()
        await release.signal()
        _ = await saveTask.value

        XCTAssertEqual(store.loadState, .locked)
        XCTAssertTrue(store.accounts.isEmpty)

        let freshStore = VaultAccountsStore(persistence: persistence)
        await freshStore.unlockAndLoad()
        XCTAssertEqual(freshStore.accounts, [account])
    }

    func testLockDuringFailedSaveDoesNotRestoreSnapshot() async {
        let original = makeAccount(siteURL: "original.example")
        let started = TestAsyncLatch()
        let release = TestAsyncLatch()
        let persistence = TestVaultAccountsPersistence(accounts: [original])
        await persistence.setSaveError(.temporaryFileWriteFailed)
        await persistence.suspendNextSave(started: started, release: release)
        let store = VaultAccountsStore(persistence: persistence)
        await store.unlockAndLoad()

        let newAccount = makeAccount(siteURL: "new.example")
        let saveTask = Task {
            await store.addAccount(newAccount)
        }

        await started.wait()
        store.lockAndClear()
        await release.signal()
        _ = await saveTask.value

        XCTAssertEqual(store.loadState, .locked)
        XCTAssertTrue(store.accounts.isEmpty)
        XCTAssertNil(store.storageAlert)
    }

    func testCommitStateUnknownBlocksStoreUntilReload() async {
        let persistence = TestVaultAccountsPersistence()
        await persistence.setSaveError(.commitStateUnknown)
        let store = VaultAccountsStore(persistence: persistence)
        await store.unlockAndLoad()

        let result = await store.addAccount(makeAccount())

        guard case .failure(let error) = result else {
            return XCTFail("Mutation unexpectedly succeeded")
        }
        XCTAssertEqual(error, .commitStateUnknown)
        XCTAssertEqual(store.loadState, .failed)
        XCTAssertTrue(store.accounts.isEmpty)
        XCTAssertNotNil(store.storageAlert)
    }
    func testDeleteRemainsVisibleUntilEncryptedSaveCompletes() async {
        let account = makeAccount()
        let started = TestAsyncLatch()
        let release = TestAsyncLatch()
        let persistence = TestVaultAccountsPersistence(accounts: [account])
        await persistence.suspendNextSave(started: started, release: release)
        let store = VaultAccountsStore(persistence: persistence)

        await store.unlockAndLoad()

        let deleteTask = Task {
            await store.deleteAccount(id: account.id)
        }

        await started.wait()
        XCTAssertEqual(store.accounts, [account])
        XCTAssertTrue(store.isMutationInProgress)

        await release.signal()
        let result = await deleteTask.value

        guard case .success = result else {
            return XCTFail("Delete failed")
        }
        XCTAssertTrue(store.accounts.isEmpty)
        XCTAssertFalse(store.isMutationInProgress)
    }

    func testGoogleAuthenticatorImportUpdatesAndAddsInSingleSave() async {
        let existing = makeAccount(siteURL: "google.com")
        var updated = existing
        updated.has2FA = true
        updated.totpSecret = "JBSWY3DPEHPK3PXP"
        updated.totpIssuer = "Google"

        let added = VaultAccount(
            siteURL: "GitHub",
            email: "developer@example.com",
            password: "",
            username: "",
            notes: "",
            has2FA: true,
            totpSecret: "MZXW6YTBOI"
        )

        let persistence = TestVaultAccountsPersistence(accounts: [existing])
        let store = VaultAccountsStore(persistence: persistence)
        await store.unlockAndLoad()

        let result = await store.applyGoogleAuthenticatorImport(
            updatedAccounts: [updated],
            newAccounts: [added]
        )

        guard case .success = result else {
            return XCTFail("Import failed")
        }
        XCTAssertEqual(store.accounts, [updated, added])
        let persisted = await persistence.snapshot()
        XCTAssertEqual(persisted, [updated, added])
    }

    func testFailedGoogleAuthenticatorImportRollsBackWholeBatch() async {
        let existing = makeAccount(siteURL: "google.com")
        var updated = existing
        updated.has2FA = true
        updated.totpSecret = "JBSWY3DPEHPK3PXP"

        let added = makeAccount(siteURL: "github.com")
        let persistence = TestVaultAccountsPersistence(accounts: [existing])
        await persistence.setSaveError(.temporaryFileWriteFailed)
        let store = VaultAccountsStore(persistence: persistence)
        await store.unlockAndLoad()

        let result = await store.applyGoogleAuthenticatorImport(
            updatedAccounts: [updated],
            newAccounts: [added]
        )

        guard case .failure(let error) = result else {
            return XCTFail("Import unexpectedly succeeded")
        }
        XCTAssertEqual(error, .saveFailed)
        XCTAssertEqual(store.accounts, [existing])
        let persisted = await persistence.snapshot()
        XCTAssertEqual(persisted, [existing])
    }

}
