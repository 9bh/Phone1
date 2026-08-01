import XCTest
@testable import VaultX

private actor BackupTestPersistence: VaultAccountsPersisting {
    private var storedAccounts: [VaultAccount]
    private var saveError: VaultPersistenceError?

    init(accounts: [VaultAccount] = []) {
        storedAccounts = accounts
    }

    func vaultExists() async throws -> Bool {
        !storedAccounts.isEmpty
    }

    func loadAccounts() async throws -> [VaultAccount] {
        storedAccounts
    }

    func saveAccounts(_ accounts: [VaultAccount]) async throws {
        if let saveError {
            throw saveError
        }
        storedAccounts = accounts
    }

    func setSaveError(_ error: VaultPersistenceError?) {
        saveError = error
    }

    func snapshot() -> [VaultAccount] {
        storedAccounts
    }
}

final class VaultBackupCryptoTests: XCTestCase {
    private let password = "Strong Backup 123!"

    private func service() -> VaultBackupCryptoService {
        VaultBackupCryptoService(
            iterationCount: 500,
            minimumAcceptedIterations: 1,
            maximumAcceptedIterations: 10_000
        )
    }

    private func account(
        id: UUID = UUID(),
        site: String = "example.com",
        email: String = "user@example.com",
        password: String = "secret",
        secret: String? = "JBSWY3DPEHPK3PXP"
    ) -> VaultAccount {
        VaultAccount(
            id: id,
            siteURL: site,
            email: email,
            password: password,
            username: "user",
            notes: "private note",
            has2FA: secret != nil,
            hasBackupFile: true,
            totpSecret: secret,
            totpIssuer: "Example",
            totpAlgorithm: .sha256,
            totpDigits: 8,
            totpPeriod: 60
        )
    }

    func testEncryptedBackupRoundTripPreservesEveryAccountField() async throws {
        let accounts = [account(), account(site: "second.example", email: "two@example.com")]
        let backup = try await service().createBackup(
            accounts: accounts,
            appVersion: "1.3.0 (42)",
            password: password
        )

        XCTAssertFalse(String(data: backup, encoding: .utf8)?.contains("secret") ?? false)

        let payload = try await service().decryptBackup(backup, password: password)
        XCTAssertEqual(payload.payloadVersion, VaultBackupPayload.currentVersion)
        XCTAssertEqual(payload.sourceAppVersion, "1.3.0 (42)")
        XCTAssertEqual(payload.accounts, accounts)
    }

    func testWrongPasswordFailsWithoutReturningAccounts() async throws {
        let backup = try await service().createBackup(
            accounts: [account()],
            appVersion: "1.3.0",
            password: password
        )

        do {
            _ = try await service().decryptBackup(backup, password: "Wrong Password 999!")
            XCTFail("Wrong password unexpectedly decrypted the backup")
        } catch let error as VaultBackupError {
            XCTAssertEqual(error, .invalidPasswordOrCorruptedFile)
        }
    }

    func testTamperedCiphertextFailsAuthentication() async throws {
        let backup = try await service().createBackup(
            accounts: [account()],
            appVersion: "1.3.0",
            password: password
        )

        var envelope = try PropertyListDecoder().decode(VaultBackupEnvelope.self, from: backup)
        var tampered = envelope.sealedPayload
        tampered[tampered.index(before: tampered.endIndex)] ^= 0x01
        envelope = VaultBackupEnvelope(
            magic: envelope.magic,
            formatVersion: envelope.formatVersion,
            keyDerivation: envelope.keyDerivation,
            iterationCount: envelope.iterationCount,
            salt: envelope.salt,
            sealedPayload: tampered
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let tamperedFile = try encoder.encode(envelope)

        do {
            _ = try await service().decryptBackup(tamperedFile, password: password)
            XCTFail("Tampered backup unexpectedly decrypted")
        } catch let error as VaultBackupError {
            XCTAssertEqual(error, .invalidPasswordOrCorruptedFile)
        }
    }

    func testShortPasswordIsRejected() async {
        do {
            _ = try await service().createBackup(
                accounts: [account()],
                appVersion: "1.3.0",
                password: "short"
            )
            XCTFail("Short password unexpectedly accepted")
        } catch let error as VaultBackupError {
            XCTAssertEqual(error, .passwordTooShort)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

final class VaultBackupMergePlannerTests: XCTestCase {
    private func account(
        id: UUID = UUID(),
        site: String = "example.com",
        email: String = "user@example.com",
        password: String = "secret",
        secret: String? = nil
    ) -> VaultAccount {
        VaultAccount(
            id: id,
            siteURL: site,
            email: email,
            password: password,
            username: "user",
            notes: "note",
            has2FA: secret != nil,
            hasBackupFile: false,
            totpSecret: secret,
            totpIssuer: secret == nil ? nil : "Example"
        )
    }

    func testPlannerClassifiesNewIdenticalAndConflictAccounts() {
        let identical = account()
        let conflictCurrent = account(site: "github.com", email: "dev@example.com", password: "old")
        var conflictIncoming = conflictCurrent
        conflictIncoming.password = "new"
        let newAccount = account(site: "new.example", email: "new@example.com")

        let items = VaultBackupMergePlanner.makeReviewItems(
            importedAccounts: [identical, conflictIncoming, newAccount],
            currentAccounts: [identical, conflictCurrent]
        )

        XCTAssertEqual(items.count, 3)
        if case .identical(let id) = items[0].status {
            XCTAssertEqual(id, identical.id)
        } else {
            XCTFail("Expected identical status")
        }
        if case .conflict(let id) = items[1].status {
            XCTAssertEqual(id, conflictCurrent.id)
        } else {
            XCTFail("Expected conflict status")
        }
        if case .new = items[2].status {
            XCTAssertEqual(items[2].decision, .add)
        } else {
            XCTFail("Expected new status")
        }
    }

    func testFinalAccountsRespectsExplicitConflictDecision() {
        let current = account(password: "old")
        var incoming = current
        incoming.password = "new"

        var items = VaultBackupMergePlanner.makeReviewItems(
            importedAccounts: [incoming],
            currentAccounts: [current]
        )
        items[0].decision = .replace(existingID: current.id)

        let final = VaultBackupMergePlanner.finalAccounts(
            currentAccounts: [current],
            reviewItems: items
        )

        XCTAssertEqual(final.count, 1)
        XCTAssertEqual(final[0].id, current.id)
        XCTAssertEqual(final[0].password, "new")
    }

    func testReplacementNormalizesDuplicateIDs() {
        let sharedID = UUID()
        let first = account(id: sharedID)
        let second = account(id: sharedID, site: "second.example", email: "second@example.com")

        let replacement = VaultBackupMergePlanner.replacementAccounts(from: [first, second])

        XCTAssertEqual(replacement.count, 2)
        XCTAssertNotEqual(replacement[0].id, replacement[1].id)
    }
}

@MainActor
final class VaultBackupStoreTests: XCTestCase {
    private func account(site: String) -> VaultAccount {
        VaultAccount(siteURL: site, email: "user@\(site)", password: "secret")
    }

    func testBackupRestorePublishesOnlyAfterPersistenceSucceeds() async {
        let old = account(site: "old.example")
        let restored = account(site: "restored.example")
        let persistence = BackupTestPersistence(accounts: [old])
        let store = VaultAccountsStore(persistence: persistence)
        await store.unlockAndLoad()

        let result = await store.applyBackupRestore(finalAccounts: [restored])

        guard case .success = result else {
            return XCTFail("Restore failed")
        }
        XCTAssertEqual(store.accounts, [restored])
        let saved = await persistence.snapshot()
        XCTAssertEqual(saved, [restored])
    }

    func testFailedBackupRestoreKeepsCurrentAccounts() async {
        let old = account(site: "old.example")
        let restored = account(site: "restored.example")
        let persistence = BackupTestPersistence(accounts: [old])
        await persistence.setSaveError(.temporaryFileWriteFailed)
        let store = VaultAccountsStore(persistence: persistence)
        await store.unlockAndLoad()

        let result = await store.applyBackupRestore(finalAccounts: [restored])

        guard case .failure(let error) = result else {
            return XCTFail("Restore unexpectedly succeeded")
        }
        XCTAssertEqual(error, .saveFailed)
        XCTAssertEqual(store.accounts, [old])
        let saved = await persistence.snapshot()
        XCTAssertEqual(saved, [old])
    }
}
