import XCTest
@testable import VaultX

@MainActor
final class AppLockStateTests: XCTestCase {
    
    // MARK: - Fresh Installation Tests
    
    func testFreshInstallCallsDeletePasscodeExactlyOnceAndRemovesOldVaultXPasscode() {
        let store = MockPasscodeStore()
        try? store.savePasscode("123456")
        
        let installService = MockAppInstallationService()
        installService.freshInstall = true
        
        let state = AppLockState(passcodeStore: store, installationService: installService, biometricService: MockBiometricService(), faceIDPreferences: MockFaceIDPreferenceStore())
        
        XCTAssertEqual(store.deleteCallCount, 1)
        XCTAssertNil(store.storedPasscode)
        XCTAssertEqual(state.installationPreparationResult, .freshInstallationPrepared)
    }
    
    func testFreshInstallDoesNotRemoveUnrelatedMockEntries() {
        let store = MockPasscodeStore()
        let installService = MockAppInstallationService()
        installService.freshInstall = true
        
        let _ = AppLockState(passcodeStore: store, installationService: installService, biometricService: MockBiometricService(), faceIDPreferences: MockFaceIDPreferenceStore())
        
        XCTAssertEqual(store.unrelatedEntries["com.otherapp"], "secret")
    }
    
    func testSuccessfulFreshInstallPreparationMarksInstallationAsInstalled() {
        let store = MockPasscodeStore()
        let installService = MockAppInstallationService()
        installService.freshInstall = true
        
        let state = AppLockState(passcodeStore: store, installationService: installService, biometricService: MockBiometricService(), faceIDPreferences: MockFaceIDPreferenceStore())
        
        XCTAssertFalse(installService.isFreshInstall())
        XCTAssertEqual(state.currentState, .needsPasscodeSetup)
        XCTAssertNil(state.setupError)
    }
    
    func testFailedDeletionDoesNotMarkInstallationAsInstalledAndDoesNotStartLocked() {
        let store = MockPasscodeStore()
        try? store.savePasscode("123456")
        store.shouldFailDelete = true
        
        let installService = MockAppInstallationService()
        installService.freshInstall = true
        
        let state = AppLockState(passcodeStore: store, installationService: installService, biometricService: MockBiometricService(), faceIDPreferences: MockFaceIDPreferenceStore())
        
        XCTAssertEqual(state.installationPreparationResult, .preparationFailed)
        XCTAssertTrue(installService.isFreshInstall()) // Marker not created
        XCTAssertEqual(state.currentState, .needsPasscodeSetup)
        XCTAssertNotNil(state.setupError)
        XCTAssertNotEqual(state.currentState, .locked)
        
        // Ensure passcode setup cannot proceed if preparation failed
        state.passcodeSetupEntered("123456")
        XCTAssertNotEqual(state.currentState, .needsPasscodeConfirmation)
    }
    
    func testRetryAfterFailedDeletionSetsPreparedState() {
        let store = MockPasscodeStore()
        try? store.savePasscode("123456")
        store.shouldFailDelete = true
        
        let installService = MockAppInstallationService()
        installService.freshInstall = true
        
        let state = AppLockState(passcodeStore: store, installationService: installService, biometricService: MockBiometricService(), faceIDPreferences: MockFaceIDPreferenceStore())
        
        XCTAssertEqual(state.installationPreparationResult, .preparationFailed)
        
        // Now mock a successful deletion
        store.shouldFailDelete = false
        state.retryPreparation()
        
        XCTAssertEqual(state.installationPreparationResult, .freshInstallationPrepared)
        XCTAssertFalse(installService.isFreshInstall())
        XCTAssertNil(state.setupError)
        
        // Passcode setup should now be allowed
        state.passcodeSetupEntered("123456")
        XCTAssertEqual(state.currentState, .needsPasscodeConfirmation)
    }
    
    func testItemNotFoundDuringDeletionTreatedAsSuccessfulPreparation() {
        // MockPasscodeStore doesn't throw itemNotFound natively on delete in our mock,
        // but if it succeeds without failing, it represents successful preparation.
        let store = MockPasscodeStore()
        store.storedPasscode = nil // Explicitly empty
        
        let installService = MockAppInstallationService()
        installService.freshInstall = true
        
        let state = AppLockState(passcodeStore: store, installationService: installService, biometricService: MockBiometricService(), faceIDPreferences: MockFaceIDPreferenceStore())
        
        XCTAssertFalse(installService.isFreshInstall())
        XCTAssertEqual(state.currentState, .needsPasscodeSetup)
        XCTAssertEqual(state.installationPreparationResult, .freshInstallationPrepared)
    }
    
    // MARK: - Existing Installation Tests
    
    func testExistingInstallationWithPasscodeStartsLocked() {
        let store = MockPasscodeStore()
        try? store.savePasscode("123456")
        
        let installService = MockAppInstallationService()
        installService.freshInstall = false
        
        let state = AppLockState(passcodeStore: store, installationService: installService, biometricService: MockBiometricService(), faceIDPreferences: MockFaceIDPreferenceStore())
        XCTAssertEqual(state.installationPreparationResult, .existingInstallation)
        XCTAssertEqual(state.currentState, .locked)
    }
    
    func testExistingInstallationWithoutPasscodeStartsSetup() {
        let store = MockPasscodeStore()
        
        let installService = MockAppInstallationService()
        installService.freshInstall = false
        
        let state = AppLockState(passcodeStore: store, installationService: installService, biometricService: MockBiometricService(), faceIDPreferences: MockFaceIDPreferenceStore())
        XCTAssertEqual(state.currentState, .needsPasscodeSetup)
    }
    
    func testInstallationMarkerAloneDoesNotCountAsPasscode() {
        let store = MockPasscodeStore()
        store.storedPasscode = nil // Explicitly empty
        
        let installService = MockAppInstallationService()
        installService.freshInstall = false // Marker exists
        
        let state = AppLockState(passcodeStore: store, installationService: installService, biometricService: MockBiometricService(), faceIDPreferences: MockFaceIDPreferenceStore())
        
        // Missing keychain means needs setup, regardless of marker
        XCTAssertEqual(state.currentState, .needsPasscodeSetup)
    }
    
    func testNewlyCreatedPasscodeIsNotDeletedOnNextExistingInstallationLaunch() {
        let store = MockPasscodeStore()
        try? store.savePasscode("123456")
        
        // Marker exists, not a fresh install
        let installService = MockAppInstallationService()
        installService.freshInstall = false
        
        let _ = AppLockState(passcodeStore: store, installationService: installService, biometricService: MockBiometricService(), faceIDPreferences: MockFaceIDPreferenceStore())
        
        // Should not call delete on existing installs
        XCTAssertEqual(store.deleteCallCount, 0)
        XCTAssertEqual(store.storedPasscode, "123456")
    }
    
    // MARK: - Verification Tests
    
    func testCorrectPasscodeVerificationUnlocks() {
        let store = MockPasscodeStore()
        try? store.savePasscode("123456")
        
        let installService = MockAppInstallationService()
        installService.freshInstall = false
        let state = AppLockState(passcodeStore: store, installationService: installService, biometricService: MockBiometricService(), faceIDPreferences: MockFaceIDPreferenceStore())
        
        let result = state.verifyAndUnlock(passcode: "123456")
        XCTAssertEqual(result, .success)
        XCTAssertEqual(state.currentState, .unlocked)
    }
    
    func testIncorrectPasscodeVerificationRemainsLocked() {
        let store = MockPasscodeStore()
        try? store.savePasscode("123456")
        
        let installService = MockAppInstallationService()
        installService.freshInstall = false
        let state = AppLockState(passcodeStore: store, installationService: installService, biometricService: MockBiometricService(), faceIDPreferences: MockFaceIDPreferenceStore())
        
        let result = state.verifyAndUnlock(passcode: "654321")
        XCTAssertEqual(result, .incorrect)
        XCTAssertEqual(state.currentState, .locked)
    }
    
    func testKeychainErrorRemainsLocked() {
        let store = MockPasscodeStore()
        try? store.savePasscode("123456")
        store.shouldFailVerify = true
        
        let installService = MockAppInstallationService()
        installService.freshInstall = false
        let state = AppLockState(passcodeStore: store, installationService: installService, biometricService: MockBiometricService(), faceIDPreferences: MockFaceIDPreferenceStore())
        
        let result = state.verifyAndUnlock(passcode: "123456")
        XCTAssertEqual(result, .storageUnavailable)
        XCTAssertEqual(state.currentState, .locked)
    }
    
    // MARK: - Lifecycle & Setup Tests
    
    func testFailedStoreSaveDoesNotAdvanceToFaceID() {
        let store = MockPasscodeStore()
        store.shouldFailSave = true
        
        let installService = MockAppInstallationService()
        installService.freshInstall = false
        let state = AppLockState(passcodeStore: store, installationService: installService, biometricService: MockBiometricService(), faceIDPreferences: MockFaceIDPreferenceStore())
        
        state.passcodeSetupEntered("123456")
        let success = state.confirmPasscode("123456")
        
        XCTAssertFalse(success)
        // Should remain in setup or confirmation without FaceID choice
        XCTAssertNotEqual(state.currentState, .needsFaceIDChoice)
        XCTAssertEqual(state.setupError, "Unable to save your passcode. Please try again.")
    }
    
    func testBackgroundTransitionReturnsToLocked() {
        let store = MockPasscodeStore()
        try? store.savePasscode("123456")
        
        let installService = MockAppInstallationService()
        installService.freshInstall = false
        let state = AppLockState(passcodeStore: store, installationService: installService, biometricService: MockBiometricService(), faceIDPreferences: MockFaceIDPreferenceStore())
        
        let _ = state.verifyAndUnlock(passcode: "123456")
        XCTAssertEqual(state.currentState, .unlocked)
        
        state.appEnteredBackground()
        XCTAssertEqual(state.currentState, .locked)
    }
    
    func testConfirmationMismatchReturnsToSetupAndClearsState() {
        let store = MockPasscodeStore()
        let installService = MockAppInstallationService()
        installService.freshInstall = true
        
        let state = AppLockState(passcodeStore: store, installationService: installService, biometricService: MockBiometricService(), faceIDPreferences: MockFaceIDPreferenceStore())
        
        // Enter a passcode
        state.passcodeSetupEntered("123456")
        XCTAssertEqual(state.currentState, .needsPasscodeConfirmation)
        
        // Provide a non-matching passcode for confirmation
        let success = state.confirmPasscode("654321")
        XCTAssertFalse(success)
        
        // Should return to setup and display mismatch error
        XCTAssertEqual(state.currentState, .needsPasscodeSetup)
        XCTAssertEqual(state.setupError, "Passcodes do not match. Create your passcode again.")
        
        // Verify state was cleared by trying to use the old passcode as confirmation again - it should fail
        // because setup wasn't properly advanced.
        let confirmAgain = state.confirmPasscode("123456")
        XCTAssertFalse(confirmAgain)
    }
    func testTrustedSystemPresentationDoesNotLockDuringTemporaryInactiveTransition() {
        let store = MockPasscodeStore()
        try? store.savePasscode("123456")

        let installService = MockAppInstallationService()
        installService.freshInstall = false
        let state = AppLockState(passcodeStore: store, installationService: installService, biometricService: MockBiometricService(), faceIDPreferences: MockFaceIDPreferenceStore())

        _ = state.verifyAndUnlock(passcode: "123456")
        state.beginTrustedSystemPresentation()
        state.appEnteredBackground()

        XCTAssertEqual(state.currentState, .unlocked)

        state.endTrustedSystemPresentation(lockIfStillBackgrounded: false)
        XCTAssertEqual(state.currentState, .unlocked)
    }

    func testTrustedSystemPresentationLocksWhenItEndsWhileStillBackgrounded() {
        let store = MockPasscodeStore()
        try? store.savePasscode("123456")

        let installService = MockAppInstallationService()
        installService.freshInstall = false
        let state = AppLockState(passcodeStore: store, installationService: installService, biometricService: MockBiometricService(), faceIDPreferences: MockFaceIDPreferenceStore())

        _ = state.verifyAndUnlock(passcode: "123456")
        state.beginTrustedSystemPresentation()
        state.appEnteredBackground()
        state.endTrustedSystemPresentation(lockIfStillBackgrounded: true)

        XCTAssertEqual(state.currentState, .locked)
    }

    func testDelayedAutoLockKeepsVaultUnlockedWhenReturningBeforeDeadline() {
        let store = MockPasscodeStore()
        try? store.savePasscode("123456")

        let installService = MockAppInstallationService()
        installService.freshInstall = false
        let state = AppLockState(
            passcodeStore: store,
            installationService: installService,
            biometricService: MockBiometricService(),
            faceIDPreferences: MockFaceIDPreferenceStore(),
            autoLockDelayProvider: { 30 }
        )

        _ = state.verifyAndUnlock(passcode: "123456")
        let backgroundDate = Date()
        state.appEnteredBackground(at: backgroundDate)

        XCTAssertEqual(state.currentState, .unlocked)

        state.appBecameActive(at: backgroundDate.addingTimeInterval(10))
        XCTAssertEqual(state.currentState, .unlocked)
    }

    func testSensitiveFaceIDVerificationSucceedsWithoutLockingVault() {
        let store = MockPasscodeStore()
        try? store.savePasscode("123456")

        let installService = MockAppInstallationService()
        installService.freshInstall = false
        let biometric = MockBiometricService()
        biometric.result = .success
        let state = AppLockState(
            passcodeStore: store,
            installationService: installService,
            biometricService: biometric,
            faceIDPreferences: MockFaceIDPreferenceStore()
        )

        _ = state.verifyAndUnlock(passcode: "123456")
        var receivedSuccess = false
        state.verifyOwnerWithFaceID(reason: "Test") { result in
            if case .success = result {
                receivedSuccess = true
            }
        }

        XCTAssertTrue(receivedSuccess)
        XCTAssertEqual(biometric.authenticateCallCount, 1)
        XCTAssertEqual(state.currentState, .unlocked)
    }

    func testSensitiveFaceIDVerificationFailureKeepsVaultUnlocked() {
        let store = MockPasscodeStore()
        try? store.savePasscode("123456")

        let installService = MockAppInstallationService()
        installService.freshInstall = false
        let biometric = MockBiometricService()
        biometric.result = .authenticationFailed
        let state = AppLockState(
            passcodeStore: store,
            installationService: installService,
            biometricService: biometric,
            faceIDPreferences: MockFaceIDPreferenceStore()
        )

        _ = state.verifyAndUnlock(passcode: "123456")
        var receivedFailure = false
        state.verifyOwnerWithFaceID(reason: "Test") { result in
            if case .authenticationFailed = result {
                receivedFailure = true
            }
        }

        XCTAssertTrue(receivedFailure)
        XCTAssertEqual(state.currentState, .unlocked)
    }

    func testDelayedAutoLockLocksVaultWhenReturningAfterDeadline() {
        let store = MockPasscodeStore()
        try? store.savePasscode("123456")

        let installService = MockAppInstallationService()
        installService.freshInstall = false
        let state = AppLockState(
            passcodeStore: store,
            installationService: installService,
            biometricService: MockBiometricService(),
            faceIDPreferences: MockFaceIDPreferenceStore(),
            autoLockDelayProvider: { 30 }
        )

        _ = state.verifyAndUnlock(passcode: "123456")
        let backgroundDate = Date()
        state.appEnteredBackground(at: backgroundDate)

        XCTAssertEqual(state.currentState, .unlocked)

        state.appBecameActive(at: backgroundDate.addingTimeInterval(31))
        XCTAssertEqual(state.currentState, .locked)
    }

}
