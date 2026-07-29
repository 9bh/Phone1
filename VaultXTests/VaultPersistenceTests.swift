import XCTest
import CryptoKit
import Security
@testable import VaultX

final class VaultPersistenceTests: XCTestCase {
    
    var tempDir: URL!
    var keyStore: PreviewVaultEncryptionKeyStore!
    var mockFS: MockVaultFilesystemClient!
    var persistence: EncryptedVaultAccountsPersistence!
    
    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        mockFS = MockVaultFilesystemClient(baseDirectory: tempDir)
        keyStore = PreviewVaultEncryptionKeyStore()
        persistence = EncryptedVaultAccountsPersistence(keyStore: keyStore, filesystem: mockFS, baseDirectoryURL: tempDir)
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func test1_NoFileNoKeyLoadsEmptyArray() async throws {
        let accounts = try await persistence.loadAccounts()
        XCTAssertTrue(accounts.isEmpty)
        let key = try await keyStore.loadKey()
        XCTAssertNil(key, "No key should be created until first save")
    }
    
    func test2_FirstSaveCreatesKeyAndFile() async throws {
        try await persistence.saveAccounts([])
        let key = try await keyStore.loadKey()
        XCTAssertNotNil(key)
        XCTAssertEqual(key?.bitCount, 256)
        
        let url = tempDir.appendingPathComponent("vault-accounts.v1")
        let exists = await mockFS.fileExists(atPath: url.path)
        XCTAssertTrue(exists)
    }
    
    func test3_SaveLoadFullAccountEquality() async throws {
        let account = VaultAccount(siteURL: "test.com", email: "test@test.com", password: "pw", username: "user1", notes: "notes1", has2FA: true, hasBackupFile: true)
        try await persistence.saveAccounts([account])
        
        let loaded = try await persistence.loadAccounts()
        XCTAssertEqual(loaded.count, 1)
        let first = loaded.first!
        XCTAssertEqual(first.id, account.id)
        XCTAssertEqual(first.siteURL, "test.com")
        XCTAssertEqual(first.email, "test@test.com")
        XCTAssertEqual(first.password, "pw")
        XCTAssertEqual(first.username, "user1")
        XCTAssertEqual(first.notes, "notes1")
        XCTAssertEqual(first.has2FA, true)
        XCTAssertEqual(first.hasBackupFile, true)
    }
    
    func test4_RawFileContainsNoPlaintext() async throws {
        let account = VaultAccount(siteURL: "secret.com", email: "secret@test.com", password: "supersecretpw", username: "secretuser", notes: "secretnotes", has2FA: false, hasBackupFile: false)
        try await persistence.saveAccounts([account])
        
        let url = tempDir.appendingPathComponent("vault-accounts.v1")
        let data = try Data(contentsOf: url)
        
        func dataContains(_ data: Data, string: String) -> Bool {
            guard let searchData = string.data(using: .utf8) else { return false }
            return data.range(of: searchData) != nil
        }
        
        XCTAssertFalse(dataContains(data, string: "secret.com"))
        XCTAssertFalse(dataContains(data, string: "secret@test.com"))
        XCTAssertFalse(dataContains(data, string: "supersecretpw"))
        XCTAssertFalse(dataContains(data, string: "secretnotes"))
        XCTAssertFalse(dataContains(data, string: "secretuser"))
    }
    
    func test5_ExistingVaultMissingKeyThrows() async throws {
        try await persistence.saveAccounts([])
        try await keyStore.deleteKeyForVerifiedFreshInstall()
        
        do {
            _ = try await persistence.loadAccounts()
            XCTFail("Should throw missingEncryptionKeyForExistingVault")
        } catch VaultPersistenceError.missingEncryptionKeyForExistingVault {
            // Success
        } catch {
            XCTFail("Wrong error")
        }
    }
    
    func test6_MissingKeyNeverOverwrites() async throws {
        try await persistence.saveAccounts([])
        let url = tempDir.appendingPathComponent("vault-accounts.v1")
        let originalData = try Data(contentsOf: url)
        try await keyStore.deleteKeyForVerifiedFreshInstall()
        
        do {
            try await persistence.saveAccounts([])
            XCTFail("Should throw missingEncryptionKeyForExistingVault")
        } catch VaultPersistenceError.missingEncryptionKeyForExistingVault {
            // Success
        } catch {
            XCTFail("Wrong error")
        }
        
        let newData = try Data(contentsOf: url)
        XCTAssertEqual(originalData, newData)
    }
    
    func test7_InvalidLengthKeyNeverOverwrites() async throws {
        try await persistence.saveAccounts([])
        let url = tempDir.appendingPathComponent("vault-accounts.v1")
        let originalData = try Data(contentsOf: url)
        
        await keyStore.setReturnsInvalidData(true)
        
        do {
            try await persistence.saveAccounts([])
            XCTFail("Should throw invalidEncryptionKeyData")
        } catch VaultPersistenceError.invalidEncryptionKeyData {
            // Success
        } catch {
            XCTFail("Wrong error")
        }
        
        let newData = try Data(contentsOf: url)
        XCTAssertEqual(originalData, newData)
    }
    
    func test8_NoFileExistingKeyReusesKey() async throws {
        let key = SymmetricKey(size: .bits256)
        _ = try await keyStore.saveNewKey(key)
        
        let loaded = try await persistence.loadAccounts()
        XCTAssertTrue(loaded.isEmpty)
        
        try await persistence.saveAccounts([])
        
        let currentKey = try await keyStore.loadKey()
        XCTAssertEqual(key.withUnsafeBytes { Data($0) }, currentKey?.withUnsafeBytes { Data($0) })
    }
    
    func test9_CorruptEnvelopeFailsWithoutOverwrite() async throws {
        try await persistence.saveAccounts([])
        let url = tempDir.appendingPathComponent("vault-accounts.v1")
        
        let corruptedData = "Not a plist".data(using: .utf8)!
        try corruptedData.write(to: url)
        
        do {
            _ = try await persistence.loadAccounts()
            XCTFail("Should throw invalidEnvelope")
        } catch VaultPersistenceError.invalidEnvelope {
            // Success
        } catch {
            XCTFail("Wrong error")
        }
        let newData = try Data(contentsOf: url)
        XCTAssertEqual(corruptedData, newData)
    }
    
    func test10_UnsupportedVersionFailsBeforeDecryption() async throws {
        try await persistence.saveAccounts([])
        let url = tempDir.appendingPathComponent("vault-accounts.v1")
        let envelope = VaultFileEnvelope(formatVersion: 999, sealedPayload: Data())
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(envelope)
        try data.write(to: url)
        
        do {
            _ = try await persistence.loadAccounts()
            XCTFail("Should throw unsupportedVaultFormatVersion")
        } catch VaultPersistenceError.unsupportedVaultFormatVersion(let v) {
            XCTAssertEqual(v, 999)
        } catch {
            XCTFail("Wrong error")
        }
        let newData = try Data(contentsOf: url)
        XCTAssertEqual(data, newData)
    }
    
    func test11_InvalidSealedDataFails() async throws {
        try await persistence.saveAccounts([])
        let url = tempDir.appendingPathComponent("vault-accounts.v1")
        let envelope = VaultFileEnvelope(formatVersion: 1, sealedPayload: "bad payload".data(using: .utf8)!)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(envelope)
        try data.write(to: url)
        
        do {
            _ = try await persistence.loadAccounts()
            XCTFail("Should throw invalidSealedData")
        } catch VaultPersistenceError.invalidSealedData {
            // Success
        } catch {
            XCTFail("Wrong error")
        }
        let newData = try Data(contentsOf: url)
        XCTAssertEqual(data, newData)
    }
    
    func test12_CiphertextTamperingFailsAuthentication() async throws {
        try await persistence.saveAccounts([])
        let url = tempDir.appendingPathComponent("vault-accounts.v1")
        let rawData = try Data(contentsOf: url)
        let envelope = try PropertyListDecoder().decode(VaultFileEnvelope.self, from: rawData)
        
        var mutatedPayload = envelope.sealedPayload
        mutatedPayload[mutatedPayload.count - 1] ^= 0xFF
        
        let mutatedEnvelope = VaultFileEnvelope(formatVersion: 1, sealedPayload: mutatedPayload)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let mutatedData = try encoder.encode(mutatedEnvelope)
        try mutatedData.write(to: url)
        
        do {
            _ = try await persistence.loadAccounts()
            XCTFail("Should throw decryptionFailed")
        } catch VaultPersistenceError.decryptionFailed {
            // Success
        } catch {
            XCTFail("Wrong error")
        }
        let newData = try Data(contentsOf: url)
        XCTAssertEqual(mutatedData, newData)
    }
    
    func test13_WrongAADFailsAuthentication() async throws {
        let key = SymmetricKey(size: .bits256)
        _ = try await keyStore.saveNewKey(key)
        let accountData = try JSONEncoder().encode([VaultAccount]())
        let wrongAAD = "VaultX.Accounts.v2".data(using: .utf8)!
        let sealedBox = try AES.GCM.seal(accountData, using: key, authenticating: wrongAAD)
        
        let envelope = VaultFileEnvelope(formatVersion: 1, sealedPayload: sealedBox.combined!)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(envelope)
        let url = tempDir.appendingPathComponent("vault-accounts.v1")
        try data.write(to: url)
        
        do {
            _ = try await persistence.loadAccounts()
            XCTFail("Should throw decryptionFailed")
        } catch VaultPersistenceError.decryptionFailed {
            // Success
        } catch {
            XCTFail("Wrong error")
        }
        let newData = try Data(contentsOf: url)
        XCTAssertEqual(data, newData)
    }
    
    func test14_DecodingFailureDoesNotOverwrite() async throws {
        let key = SymmetricKey(size: .bits256)
        _ = try await keyStore.saveNewKey(key)
        
        let badJsonData = "Not JSON".data(using: .utf8)!
        let aad = "VaultX.Accounts.v1".data(using: .utf8)!
        let sealedBox = try AES.GCM.seal(badJsonData, using: key, authenticating: aad)
        let envelope = VaultFileEnvelope(formatVersion: 1, sealedPayload: sealedBox.combined!)
        
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(envelope)
        let url = tempDir.appendingPathComponent("vault-accounts.v1")
        try data.write(to: url)
        
        do {
            _ = try await persistence.loadAccounts()
            XCTFail("Should throw decodingFailed")
        } catch VaultPersistenceError.decodingFailed {
            // Success
        } catch {
            XCTFail("Wrong error")
        }
        let newData = try Data(contentsOf: url)
        XCTAssertEqual(data, newData)
    }
    
    func test15_TwoRapidSavesExecuteFIFO() async throws {
        let account1 = VaultAccount(siteURL: "1", email: "", password: "", username: "", notes: "", has2FA: false, hasBackupFile: false)
        let account2 = VaultAccount(siteURL: "2", email: "", password: "", username: "", notes: "", has2FA: false, hasBackupFile: false)
        
        try await persistence.saveAccounts([]) 
        
        await mockFS.setControlledSuspension(at: .replaceExisting, occurrences: [1, 2])
        
        let t1 = Task { try await persistence.saveAccounts([account1]) }
        
        await mockFS.waitUntilEntryCount(1, at: .replaceExisting)
        
        let t2 = Task { try await persistence.saveAccounts([account2]) }
        
        let c2 = await mockFS.entryCount(at: .replaceExisting)
        XCTAssertEqual(c2, 1, "Second save should not enter the protected transaction")
        
        await mockFS.resumeOccurrence(1, at: .replaceExisting)
        _ = try await t1.value
        
        await mockFS.waitUntilEntryCount(2, at: .replaceExisting)
        await mockFS.resumeOccurrence(2, at: .replaceExisting)
        _ = try await t2.value
        
        let loaded = try await persistence.loadAccounts()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.siteURL, "2")
    }
    
    func test16_CompleteProtectionAndExclusionRequestedAndVerified() async throws {
        try await persistence.saveAccounts([])
        let account = VaultAccount(siteURL: "new", email: "", password: "", username: "", notes: "", has2FA: false, hasBackupFile: false)
        try await persistence.saveAccounts([account])
        
        let ops = await mockFS.recordedOperations
        XCTAssertTrue(ops.contains("setAttributes_complete_temp"))
        XCTAssertTrue(ops.contains("setResourceValues_exclusion_temp"))
        XCTAssertTrue(ops.contains("verifyAttributes_complete_temp"))
        XCTAssertTrue(ops.contains("verifyResourceValues_exclusion_temp"))
        XCTAssertTrue(ops.contains("setAttributes_complete_backup"))
        XCTAssertTrue(ops.contains("setResourceValues_exclusion_backup"))
        XCTAssertTrue(ops.contains("verifyAttributes_complete_backup"))
        XCTAssertTrue(ops.contains("verifyResourceValues_exclusion_backup"))
        XCTAssertTrue(ops.contains("verifyAttributes_complete_final"))
        XCTAssertTrue(ops.contains("verifyResourceValues_exclusion_final"))
    }
    
    func test17_PostReplacementVerificationFailureRestores() async throws {
        let account = VaultAccount(siteURL: "old", email: "", password: "", username: "", notes: "", has2FA: false, hasBackupFile: false)
        try await persistence.saveAccounts([account])
        
        let oldBytes = try Data(contentsOf: tempDir.appendingPathComponent("vault-accounts.v1"))
        
        await mockFS.setFaultPoint(.verifyFinalProtection)
        let newAccount = VaultAccount(siteURL: "new", email: "", password: "", username: "", notes: "", has2FA: false, hasBackupFile: false)
        
        do {
            try await persistence.saveAccounts([newAccount])
            XCTFail("Should throw fileProtectionFailed")
        } catch VaultPersistenceError.fileProtectionFailed {
            // Success
        } catch {
            XCTFail("Wrong error")
        }
        
        let restoredBytes = try Data(contentsOf: tempDir.appendingPathComponent("vault-accounts.v1"))
        XCTAssertEqual(oldBytes, restoredBytes)
        
        let ops = await mockFS.recordedOperations
        XCTAssertTrue(ops.contains("restoreBackup"))
    }
    
    func test18_RecoveryFailureReturnsCommitStateUnknown() async throws {
        let account = VaultAccount(siteURL: "old", email: "", password: "", username: "", notes: "", has2FA: false, hasBackupFile: false)
        try await persistence.saveAccounts([account])
        
        await mockFS.setFaultPoint(.verifyFinalProtection)
        await mockFS.setFaultPoint2(.restoreBackup)
        let newAccount = VaultAccount(siteURL: "new", email: "", password: "", username: "", notes: "", has2FA: false, hasBackupFile: false)
        
        do {
            try await persistence.saveAccounts([newAccount])
            XCTFail("Should throw commitStateUnknown")
        } catch VaultPersistenceError.commitStateUnknown {
            // Expected
        } catch {
            XCTFail("Wrong error")
        }
    }
    
    func test19_KeychainDeleteItemNotFoundSucceeds() async throws {
        XCTAssertNoThrow(try ProductionVaultKeychainClient.validateDeleteStatus(errSecItemNotFound))
        
        do {
            try ProductionVaultKeychainClient.validateDeleteStatus(errSecNotAvailable)
            XCTFail("Should throw")
        } catch VaultPersistenceError.keychainDeleteFailed(let status) {
            XCTAssertEqual(status, errSecNotAvailable)
        }
        
        let mockKeychain = MockVaultKeychainClient()
        await mockKeychain.setEmulateItemNotFound(true)
        let resetter = KeychainVaultEncryptionKeyStore(client: mockKeychain)
        
        try await resetter.deleteKeyForVerifiedFreshInstall()
        
        let deletions = await mockKeychain.deletions
        XCTAssertEqual(deletions.count, 1)
        XCTAssertEqual(deletions[0].service, "com.vaultx.app")
        XCTAssertEqual(deletions[0].account, "vault-accounts-encryption-key-v1")
    }
    
    func test20_MarkerPresentDeletesNothing() async throws {
        let eventRecorder = StringEventRecorder()
        let mockAppStore = MockInstallationMarkerStore(isMarked: true, recorder: eventRecorder)
        let mockPasscode = MockPasscodeVerifierResetter(recorder: eventRecorder)
        let mockKeyStore = MockVaultEncryptionKeyResetter(recorder: eventRecorder)
        let preparer = VaultFreshInstallationSecurityPreparer(
            markerStore: mockAppStore,
            passcodeResetter: mockPasscode,
            keyResetter: mockKeyStore,
            vaultPersistence: persistence
        )
        try await preparer.prepareVerifiedFreshInstallation()
        
        let resetCountPasscode = await mockPasscode.resetCount
        let resetCountKey = await mockKeyStore.resetCount
        let markCountApp = await mockAppStore.markCount
        
        XCTAssertEqual(resetCountPasscode, 0)
        XCTAssertEqual(resetCountKey, 0)
        XCTAssertEqual(markCountApp, 0)
    }
    
    func test21_MarkerMissingNoVaultResetsAndMarks() async throws {
        let eventRecorder = StringEventRecorder()
        let mockAppStore = MockInstallationMarkerStore(isMarked: false, recorder: eventRecorder)
        let mockPasscode = MockPasscodeVerifierResetter(recorder: eventRecorder)
        let mockKeyStore = MockVaultEncryptionKeyResetter(recorder: eventRecorder)
        let preparer = VaultFreshInstallationSecurityPreparer(
            markerStore: mockAppStore,
            passcodeResetter: mockPasscode,
            keyResetter: mockKeyStore,
            vaultPersistence: persistence
        )
        try await preparer.prepareVerifiedFreshInstallation()
        
        let resetCountPasscode = await mockPasscode.resetCount
        let resetCountKey = await mockKeyStore.resetCount
        let markCountApp = await mockAppStore.markCount
        let isMarked = try await mockAppStore.isInstallationMarked()
        
        XCTAssertEqual(resetCountPasscode, 1)
        XCTAssertEqual(resetCountKey, 1)
        XCTAssertEqual(markCountApp, 1)
        XCTAssertTrue(isMarked)
        
        let events = await eventRecorder.snapshot()
        XCTAssertEqual(events, ["passcodeReset", "keyReset", "markerWrite"])
    }
    
    func test22_MarkerMissingExistingVaultDeletesNothing() async throws {
        try await persistence.saveAccounts([])
        let originalBytes = try await mockFS.readData(from: tempDir.appendingPathComponent("vault-accounts.v1"))
        let originalKey = try await keyStore.loadKey()!
        
        let eventRecorder = StringEventRecorder()
        let mockAppStore = MockInstallationMarkerStore(isMarked: false, recorder: eventRecorder)
        let mockPasscode = MockPasscodeVerifierResetter(recorder: eventRecorder)
        let mockKeyStore = MockVaultEncryptionKeyResetter(recorder: eventRecorder)
        let preparer = VaultFreshInstallationSecurityPreparer(
            markerStore: mockAppStore,
            passcodeResetter: mockPasscode,
            keyResetter: mockKeyStore,
            vaultPersistence: persistence
        )
        
        do {
            try await preparer.prepareVerifiedFreshInstallation()
            XCTFail("Should throw existingVaultWithMissingInstallationMarker")
        } catch VaultPersistenceError.existingVaultWithMissingInstallationMarker {
            // Success
        } catch {
            XCTFail("Wrong error")
        }
        
        let newBytes = try await mockFS.readData(from: tempDir.appendingPathComponent("vault-accounts.v1"))
        XCTAssertEqual(originalBytes, newBytes)
        
        let currentKey = try await keyStore.loadKey()!
        XCTAssertEqual(originalKey.withUnsafeBytes { Data($0) }, currentKey.withUnsafeBytes { Data($0) })
        
        let resetCountPasscode = await mockPasscode.resetCount
        let resetCountKey = await mockKeyStore.resetCount
        let markCountApp = await mockAppStore.markCount
        
        XCTAssertEqual(resetCountPasscode, 0)
        XCTAssertEqual(resetCountKey, 0)
        XCTAssertEqual(markCountApp, 0)
    }
    
    func test23_ArbitraryErrorsMappedToSendable() async throws {
        await mockFS.setFaultPoint(.writeTemporary)
        do {
            try await persistence.saveAccounts([])
            XCTFail("Should throw temporaryFileWriteFailed")
        } catch VaultPersistenceError.temporaryFileWriteFailed {
            // Success
        } catch {
            XCTFail("Wrong error")
        }
    }
    
    func test24_SuccessfulAddReturnsProposedKey() async throws {
        let proposed = SymmetricKey(size: .bits256)
        let returned = try await keyStore.saveNewKey(proposed)
        XCTAssertEqual(proposed.withUnsafeBytes { Data($0) }, returned.withUnsafeBytes { Data($0) })
    }
    
    func test25_DuplicateAddReturnsExistingKey() async throws {
        let existing = SymmetricKey(size: .bits256)
        _ = try await keyStore.saveNewKey(existing)
        
        await keyStore.setEmulateDuplicateAdd(true)
        let proposed = SymmetricKey(size: .bits256)
        let returned = try await keyStore.saveNewKey(proposed)
        
        XCTAssertEqual(existing.withUnsafeBytes { Data($0) }, returned.withUnsafeBytes { Data($0) })
        XCTAssertNotEqual(proposed.withUnsafeBytes { Data($0) }, returned.withUnsafeBytes { Data($0) })
    }
    
    func test26_DuplicateButMissingReadThrowsConsistencyError() async throws {
        await keyStore.setEmulateDuplicateAdd(true)
        await keyStore.setDuplicateItemButMissing(true)
        let proposed = SymmetricKey(size: .bits256)
        do {
            _ = try await keyStore.saveNewKey(proposed)
            XCTFail("Should throw keychainDuplicateItemButKeyMissing")
        } catch VaultPersistenceError.keychainDuplicateItemButKeyMissing {
            // Success
        } catch {
            XCTFail("Wrong error")
        }
    }
    
    func test27_DuplicateKeyRaceReturnsSimulatedKey() async throws {
        let actual = SymmetricKey(size: .bits256)
        
        await keyStore.setEmulateDuplicateAdd(true)
        await keyStore.setSimulateRaceExisting(actual)
        
        let account = VaultAccount(siteURL: "dup", email: "", password: "", username: "", notes: "", has2FA: false, hasBackupFile: false)
        try await persistence.saveAccounts([account])
        
        let currentKey = try await keyStore.loadKey()
        XCTAssertEqual(actual.withUnsafeBytes { Data($0) }, currentKey?.withUnsafeBytes { Data($0) })
        
        let loaded = try await persistence.loadAccounts()
        XCTAssertEqual(loaded.first?.siteURL, "dup")
    }
    
    func test28_ExistingKeyIsNeverReplaced() async throws {
        let existing = SymmetricKey(size: .bits256)
        _ = try await keyStore.saveNewKey(existing)
        
        await keyStore.setEmulateDuplicateAdd(true)
        let proposed = SymmetricKey(size: .bits256)
        _ = try await keyStore.saveNewKey(proposed)
        
        let finalKey = try await keyStore.loadKey()
        XCTAssertEqual(existing.withUnsafeBytes { Data($0) }, finalKey?.withUnsafeBytes { Data($0) })
    }
    
    func test29_Gate_FIFO_Order() async throws {
        let gate = AsyncFIFOTransactionGate()
        let recorder = IntEventRecorder()
        
        let entered1 = AsyncEventLatch()
        let release1 = AsyncEventLatch()
        let t1 = Task {
            try await gate.withLock {
                await entered1.signal()
                await release1.wait()
                await recorder.append(1)
            }
        }
        
        await entered1.wait()
        
        let entered2 = AsyncEventLatch()
        let release2 = AsyncEventLatch()
        let t2 = Task {
            try await gate.withLock {
                await entered2.signal()
                await release2.wait()
                await recorder.append(2)
            }
        }
        
        while await gate.snapshot().queuedCount < 1 { await Task.yield() }
        
        let entered3 = AsyncEventLatch()
        let release3 = AsyncEventLatch()
        let t3 = Task {
            try await gate.withLock {
                await entered3.signal()
                await release3.wait()
                await recorder.append(3)
            }
        }
        
        while await gate.snapshot().queuedCount < 2 { await Task.yield() }
        
        await release1.signal()
        _ = try await t1.value
        
        await entered2.wait()
        await release2.signal()
        _ = try await t2.value
        
        await entered3.wait()
        await release3.signal()
        _ = try await t3.value
        
        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot, [1, 2, 3])
        
        let gateSnapshot = await gate.snapshot()
        XCTAssertFalse(gateSnapshot.ownerPresent)
        XCTAssertEqual(gateSnapshot.registeredCount, 0)
        XCTAssertEqual(gateSnapshot.queuedCount, 0)
    }
    
    func test30_Gate_CancelledMiddleWaiterIsSkipped() async throws {
        let gate = AsyncFIFOTransactionGate()
        let recorder = IntEventRecorder()
        
        let entered1 = AsyncEventLatch()
        let release1 = AsyncEventLatch()
        let t1 = Task {
            try await gate.withLock {
                await entered1.signal()
                await release1.wait()
                await recorder.append(1)
            }
        }
        
        await entered1.wait()
        
        let entered2 = AsyncEventLatch()
        let release2 = AsyncEventLatch()
        let t2 = Task {
            try await gate.withLock {
                await entered2.signal()
                await release2.wait()
                await recorder.append(2)
            }
        }
        
        while await gate.snapshot().queuedCount < 1 { await Task.yield() }
        
        let entered3 = AsyncEventLatch()
        let release3 = AsyncEventLatch()
        let t3 = Task {
            try await gate.withLock {
                await entered3.signal()
                await release3.wait()
                await recorder.append(3)
            }
        }
        
        while await gate.snapshot().queuedCount < 2 { await Task.yield() }
        
        t2.cancel()
        
        do {
            _ = try await t2.value
            XCTFail("t2 should have thrown CancellationError")
        } catch is CancellationError {
            // Expected
        } catch {
            XCTFail("Wrong error")
        }
        
        while await gate.snapshot().queuedCount != 1 { await Task.yield() }
        
        await release1.signal()
        _ = try await t1.value
        
        await entered3.wait()
        await release3.signal()
        _ = try await t3.value
        
        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot, [1, 3])
        
        let gateSnapshot = await gate.snapshot()
        XCTAssertFalse(gateSnapshot.ownerPresent)
        XCTAssertEqual(gateSnapshot.registeredCount, 0)
        XCTAssertEqual(gateSnapshot.queuedCount, 0)
    }
    
    func test31_Gate_CancellationBeforeEnqueue() async throws {
        let gate = AsyncFIFOTransactionGate()
        let recorder = IntEventRecorder()
        
        let entered1 = AsyncEventLatch()
        let release1 = AsyncEventLatch()
        let t1 = Task {
            try await gate.withLock {
                await entered1.signal()
                await release1.wait()
                await recorder.append(1)
            }
        }
        
        await entered1.wait()
        
        let start2 = AsyncEventLatch()
        let entered2 = AsyncEventLatch()
        let t2 = Task {
            await start2.wait()
            try await gate.withLock {
                await entered2.signal()
                await recorder.append(2)
            }
        }
        
        t2.cancel() // Cancel before letting it start waiting
        await start2.signal()
        
        do {
            _ = try await t2.value
            XCTFail("Should throw cancellation")
        } catch is CancellationError {
            // Expected
        }
        
        let entered3 = AsyncEventLatch()
        let release3 = AsyncEventLatch()
        let t3 = Task {
            try await gate.withLock {
                await entered3.signal()
                await release3.wait()
                await recorder.append(3)
            }
        }
        
        while await gate.snapshot().queuedCount < 1 { await Task.yield() }
        
        await release1.signal()
        _ = try await t1.value
        
        await entered3.wait()
        await release3.signal()
        _ = try await t3.value
        
        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot, [1, 3])
        
        let gateSnapshot = await gate.snapshot()
        XCTAssertFalse(gateSnapshot.ownerPresent)
        XCTAssertEqual(gateSnapshot.registeredCount, 0)
        XCTAssertEqual(gateSnapshot.queuedCount, 0)
    }
    
    func test32_Gate_ReleasesAfterThrowingTransaction() async throws {
        let gate = AsyncFIFOTransactionGate()
        let recorder = IntEventRecorder()
        
        let entered1 = AsyncEventLatch()
        let release1 = AsyncEventLatch()
        let t1 = Task {
            try await gate.withLock {
                await entered1.signal()
                await release1.wait()
                throw NSError(domain: "test", code: 1)
            }
        }
        
        await entered1.wait()
        
        let entered2 = AsyncEventLatch()
        let release2 = AsyncEventLatch()
        let t2 = Task {
            try await gate.withLock {
                await entered2.signal()
                await release2.wait()
                await recorder.append(2)
            }
        }
        
        while await gate.snapshot().queuedCount < 1 { await Task.yield() }
        
        await release1.signal()
        do {
            _ = try await t1.value
            XCTFail("Should throw")
        } catch {
            // Expected
        }
        
        await entered2.wait()
        await release2.signal()
        _ = try await t2.value
        
        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot, [2])
        
        let gateSnapshot = await gate.snapshot()
        XCTAssertFalse(gateSnapshot.ownerPresent)
        XCTAssertEqual(gateSnapshot.registeredCount, 0)
        XCTAssertEqual(gateSnapshot.queuedCount, 0)
    }
    
    func test33_Gate_ImmediateCancellationOnFreeGate() async throws {
        for _ in 0..<1000 {
            let gate = AsyncFIFOTransactionGate()
            let t = Task {
                try await gate.withLock {
                    await Task.yield()
                }
            }
            t.cancel()
            
            do {
                _ = try await t.value
                XCTFail("Should throw cancellation")
            } catch is CancellationError {
                // Expected
            }
            
            let snapshot = await gate.snapshot()
            XCTAssertFalse(snapshot.ownerPresent)
            XCTAssertEqual(snapshot.queuedCount, 0)
            XCTAssertEqual(snapshot.registeredCount, 0)
        }
    }

    func test34_Gate_LateCancellationAfterNormalRelease() async throws {
        let gate = AsyncFIFOTransactionGate()
        let t = Task {
            try await gate.withLock {
                return 42
            }
        }
        let result = try await t.value
        XCTAssertEqual(result, 42)
        
        await gate.testHook_cancelUnknown()
        
        let snapshot = await gate.snapshot()
        XCTAssertFalse(snapshot.ownerPresent)
        XCTAssertEqual(snapshot.queuedCount, 0)
        XCTAssertEqual(snapshot.registeredCount, 0)
    }

    func test35_Gate_CancelledOwnerWithNonCooperativeOperation() async throws {
        let gate = AsyncFIFOTransactionGate()
        let entered1 = AsyncEventLatch()
        let release1 = AsyncEventLatch()
        
        let t1 = Task {
            try await gate.withLock {
                await entered1.signal()
                await release1.wait()
                try Task.checkCancellation()
                return 1
            }
        }
        
        await entered1.wait()
        
        let entered2 = AsyncEventLatch()
        let release2 = AsyncEventLatch()
        let t2 = Task {
            try await gate.withLock {
                await entered2.signal()
                await release2.wait()
                return 2
            }
        }
        
        while await gate.snapshot().queuedCount < 1 { await Task.yield() }
        
        t1.cancel()
        
        for _ in 0..<5 { await Task.yield() }
        let midSnapshot = await gate.snapshot()
        XCTAssertEqual(midSnapshot.queuedCount, 1)
        XCTAssertTrue(midSnapshot.ownerPresent)
        
        await release1.signal()
        do {
            _ = try await t1.value
            XCTFail("Should throw")
        } catch is CancellationError {
            // Expected
        }
        
        await entered2.wait()
        await release2.signal()
        _ = try await t2.value
        
        let snapshot = await gate.snapshot()
        XCTAssertFalse(snapshot.ownerPresent)
        XCTAssertEqual(snapshot.queuedCount, 0)
        XCTAssertEqual(snapshot.registeredCount, 0)
    }
}

actor IntEventRecorder {
    private var values: [Int] = []
    func append(_ value: Int) { values.append(value) }
    func snapshot() -> [Int] { values }
}

actor StringEventRecorder {
    private var values: [String] = []
    func append(_ value: String) { values.append(value) }
    func snapshot() -> [String] { values }
}

actor AsyncEventLatch {
    private var isSignaled = false
    private var continuation: CheckedContinuation<Void, Never>?
    
    func wait() async {
        if isSignaled { return }
        await withCheckedContinuation { c in continuation = c }
    }
    
    func signal() {
        isSignaled = true
        continuation?.resume()
        continuation = nil
    }
}

actor MockVaultKeychainClient: VaultKeychainClient {
    private var emulateItemNotFound = false
    var deletions: [(service: String, account: String)] = []
    
    func setEmulateItemNotFound(_ b: Bool) { emulateItemNotFound = b }
    
    func readData(service: String, account: String) async throws -> Data? { return nil }
    func addData(_ data: Data, service: String, account: String, accessibility: CFString) async throws -> VaultKeychainAddResult { return .success }
    func deleteData(service: String, account: String) async throws {
        deletions.append((service, account))
        if emulateItemNotFound {
            return
        }
    }
}

actor MockVaultEncryptionKeyResetter: VaultEncryptionKeyResetting {
    var resetCount = 0
    private var recorder: StringEventRecorder?
    init(recorder: StringEventRecorder? = nil) { self.recorder = recorder }
    func deleteKeyForVerifiedFreshInstall() async throws {
        resetCount += 1
        await recorder?.append("keyReset")
    }
}

struct SuspensionKey: Hashable, Sendable {
    let point: VaultFilesystemFaultPoint
    let occurrence: Int
}

enum VaultFilesystemFaultPoint: Sendable, Equatable {
    case writeTemporary
    case verifyTemporaryProtection
    case verifyTemporaryBackupExclusion
    case moveFirstSave
    case replaceExisting
    case verifyBackupProtection
    case verifyBackupExclusion
    case verifyFinalProtection
    case verifyFinalBackupExclusion
    case restoreBackup
    case verifyRestoredFinalProtection
    case verifyRestoredFinalBackupExclusion
    case removeFailedFirstSave
}

actor MockVaultFilesystemClient: VaultFilesystemClient {
    private let fm = FileManager.default
    private let baseDirectory: URL
    
    private var controlledSuspensionPoints: [SuspensionKey: Bool] = [:]
    private var suspendedContinuations: [SuspensionKey: CheckedContinuation<Void, Never>] = [:]
    private var entryCounts: [VaultFilesystemFaultPoint: Int] = [:]
    private var entryWaiters: [(point: VaultFilesystemFaultPoint, count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    
    private var faultPoint: VaultFilesystemFaultPoint?
    private var faultPoint2: VaultFilesystemFaultPoint?
    
    var recordedOperations: [String] = []
    
    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }
    
    func setControlledSuspension(at point: VaultFilesystemFaultPoint, occurrences: [Int]) {
        for occ in occurrences {
            controlledSuspensionPoints[SuspensionKey(point: point, occurrence: occ)] = true
        }
    }
    
    func setFaultPoint(_ point: VaultFilesystemFaultPoint) { faultPoint = point }
    func setFaultPoint2(_ point: VaultFilesystemFaultPoint) { faultPoint2 = point }
    
    func resumeOccurrence(_ occurrence: Int, at point: VaultFilesystemFaultPoint) {
        let key = SuspensionKey(point: point, occurrence: occurrence)
        controlledSuspensionPoints[key] = false
        suspendedContinuations[key]?.resume()
        suspendedContinuations[key] = nil
    }
    
    func waitUntilEntryCount(_ expectedCount: Int, at point: VaultFilesystemFaultPoint) async {
        if entryCount(at: point) >= expectedCount { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append((point: point, count: expectedCount, continuation: continuation))
        }
    }
    
    func entryCount(at point: VaultFilesystemFaultPoint) -> Int {
        return entryCounts[point, default: 0]
    }
    
    private func checkSuspension(for point: VaultFilesystemFaultPoint) async {
        let count = entryCounts[point, default: 0] + 1
        entryCounts[point] = count
        
        let waitersToResume = entryWaiters.filter { $0.point == point && $0.count <= count }
        entryWaiters.removeAll { w in waitersToResume.contains { $0.point == w.point && $0.count == w.count } }
        for w in waitersToResume { w.continuation.resume() }
        
        let key = SuspensionKey(point: point, occurrence: count)
        if controlledSuspensionPoints[key] == true {
            await withCheckedContinuation { continuation in
                suspendedContinuations[key] = continuation
            }
        }
    }
    
    func fileExists(atPath path: String) async -> Bool { fm.fileExists(atPath: path) }
    func applicationSupportURL() async throws -> URL { return baseDirectory }
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) async throws {
        try fm.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
    }
    func readData(from url: URL) async throws -> Data { try Data(contentsOf: url) }
    
    func writeData(_ data: Data, to url: URL) async throws {
        await checkSuspension(for: .writeTemporary)
        if faultPoint == .writeTemporary || faultPoint2 == .writeTemporary { throw NSError(domain: "test", code: 1) }
        try data.write(to: url, options: .atomic)
    }
    
    func moveItem(at sourceURL: URL, to destinationURL: URL) async throws {
        await checkSuspension(for: .moveFirstSave)
        if faultPoint == .moveFirstSave || faultPoint2 == .moveFirstSave { throw NSError(domain: "test", code: 1) }
        try fm.moveItem(at: sourceURL, to: destinationURL)
    }
    
    func replaceItemAt(_ originalItemURL: URL, withItemAt newItemURL: URL, backupItemName: String?) async throws -> URL? {
        if backupItemName == nil { // Restore
            await checkSuspension(for: .restoreBackup)
            recordedOperations.append("restoreBackup")
            if faultPoint == .restoreBackup || faultPoint2 == .restoreBackup { throw NSError(domain: "test", code: 1) }
        } else { // Replace
            await checkSuspension(for: .replaceExisting)
            if faultPoint == .replaceExisting || faultPoint2 == .replaceExisting { throw NSError(domain: "test", code: 1) }
        }
        return try fm.replaceItemAt(
            originalItemURL,
            withItemAt: newItemURL,
            backupItemName: backupItemName,
            options: backupItemName == nil ? [] : [.withoutDeletingBackupItem]
        )
    }
    
    func removeItem(at url: URL) async throws { try fm.removeItem(at: url) }
    
    func setResourceValues(_ values: URLResourceValues, for url: URL) async throws {
        let isTemp = url.path.contains(".tmp")
        let isBackup = url.path.contains(".backup")
        let name = isTemp ? "temp" : (isBackup ? "backup" : "final")
        
        if values.isExcludedFromBackup == true {
            recordedOperations.append("setResourceValues_exclusion_\(name)")
        }
    }
    
    func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) async throws {
        let isTemp = path.contains(".tmp")
        let isBackup = path.contains(".backup")
        let name = isTemp ? "temp" : (isBackup ? "backup" : "final")
        
        if let protection = attributes[.protectionKey] as? FileProtectionType, protection == .complete {
            recordedOperations.append("setAttributes_complete_\(name)")
        }
    }
    
    func attributesOfItem(atPath path: String) async throws -> [FileAttributeKey: Any] {
        let isTemp = path.contains(".tmp")
        let isBackup = path.contains(".backup")
        let isRestored = recordedOperations.contains("restoreBackup")
        let name = isTemp ? "temp" : (isBackup ? "backup" : "final")
        recordedOperations.append("verifyAttributes_complete_\(name)")
        
        let ptCheck = isTemp ? VaultFilesystemFaultPoint.verifyTemporaryProtection : (isBackup ? .verifyBackupProtection : (isRestored ? .verifyRestoredFinalProtection : .verifyFinalProtection))
        
        if faultPoint == ptCheck || faultPoint2 == ptCheck { return [:] }
        return [.protectionKey: FileProtectionType.complete]
    }
    
    func resourceValues(forKeys keys: Set<URLResourceKey>, for url: URL) async throws -> URLResourceValues {
        let isTemp = url.path.contains(".tmp")
        let isBackup = url.path.contains(".backup")
        let isRestored = recordedOperations.contains("restoreBackup")
        let name = isTemp ? "temp" : (isBackup ? "backup" : "final")
        recordedOperations.append("verifyResourceValues_exclusion_\(name)")
        
        let ptCheck = isTemp ? VaultFilesystemFaultPoint.verifyTemporaryBackupExclusion : (isBackup ? .verifyBackupExclusion : (isRestored ? .verifyRestoredFinalBackupExclusion : .verifyFinalBackupExclusion))
        
        if faultPoint == ptCheck || faultPoint2 == ptCheck {
            var rv = URLResourceValues()
            rv.isExcludedFromBackup = false
            return rv
        }
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true
        return rv
    }
}

actor MockInstallationMarkerStore: InstallationMarkerStoring {
    private var isMarked: Bool
    var markCount = 0
    private var recorder: StringEventRecorder?
    init(isMarked: Bool, recorder: StringEventRecorder? = nil) { self.isMarked = isMarked; self.recorder = recorder }
    func isInstallationMarked() async throws -> Bool { return isMarked }
    func markInstallationCompleted() async throws {
        isMarked = true
        markCount += 1
        await recorder?.append("markerWrite")
    }
}

actor MockPasscodeVerifierResetter: PasscodeVerifierResetting {
    var resetCount = 0
    private var recorder: StringEventRecorder?
    init(recorder: StringEventRecorder? = nil) { self.recorder = recorder }
    func deletePasscodeVerifierForVerifiedFreshInstall() async throws {
        resetCount += 1
        await recorder?.append("passcodeReset")
    }
}
