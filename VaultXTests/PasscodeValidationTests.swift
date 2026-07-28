import XCTest
@testable import VaultX

@MainActor
final class PasscodeValidationTests: XCTestCase {
    
    // MARK: - Validation Function Tests
    
    func testValidPasscodeReturnsTrue() {
        XCTAssertTrue(PasscodeValidator.isValidPasscode("123456"))
        XCTAssertTrue(PasscodeValidator.isValidPasscode("000000"))
        XCTAssertTrue(PasscodeValidator.isValidPasscode("987654"))
    }
    
    func testShortPasscodeReturnsFalse() {
        XCTAssertFalse(PasscodeValidator.isValidPasscode("12345"))
        XCTAssertFalse(PasscodeValidator.isValidPasscode("1"))
        XCTAssertFalse(PasscodeValidator.isValidPasscode(""))
    }
    
    func testLongPasscodeReturnsFalse() {
        XCTAssertFalse(PasscodeValidator.isValidPasscode("1234567"))
    }
    
    func testNonNumericCharactersReturnsFalse() {
        XCTAssertFalse(PasscodeValidator.isValidPasscode("123a56"))
        XCTAssertFalse(PasscodeValidator.isValidPasscode("abcdef"))
        XCTAssertFalse(PasscodeValidator.isValidPasscode("12 456"))
        XCTAssertFalse(PasscodeValidator.isValidPasscode("12-456"))
    }
    
    func testNonASCIIArabicNumeralsReturnsFalse() {
        // App expects exact ASCII 0-9 for predictability
        XCTAssertFalse(PasscodeValidator.isValidPasscode("١٢٣٤٥٦"))
    }
    
    // MARK: - AppLockState Integration Tests
    
    func testAppLockStateRejectsInvalidPasscodesInSetup() {
        let installService = MockAppInstallationService()
        installService.freshInstall = true
        let state = AppLockState(passcodeStore: MockPasscodeStore(), installationService: installService, biometricService: MockBiometricService(), faceIDPreferences: MockFaceIDPreferenceStore())
        
        state.passcodeSetupEntered("12345") // Too short
        XCTAssertEqual(state.currentState, .needsPasscodeSetup)
        
        state.passcodeSetupEntered("123a56") // Invalid chars
        XCTAssertEqual(state.currentState, .needsPasscodeSetup)
        
        state.passcodeSetupEntered("123456") // Valid
        XCTAssertEqual(state.currentState, .needsPasscodeConfirmation)
    }
    
    func testAppLockStateRejectsInvalidPasscodesInConfirmation() {
        let installService = MockAppInstallationService()
        installService.freshInstall = true
        let state = AppLockState(passcodeStore: MockPasscodeStore(), installationService: installService, biometricService: MockBiometricService(), faceIDPreferences: MockFaceIDPreferenceStore())
        
        state.passcodeSetupEntered("123456")
        XCTAssertEqual(state.currentState, .needsPasscodeConfirmation)
        
        // Pass invalid string to confirm
        let success = state.confirmPasscode("12345")
        XCTAssertFalse(success)
        
        // Since confirm didn't match temp and invalid format just returns false,
        // it shouldn't proceed. We confirm it returns false.
        XCTAssertEqual(state.currentState, .needsPasscodeConfirmation)
    }
}
