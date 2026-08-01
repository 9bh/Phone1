import XCTest
@testable import VaultX

final class VaultSecuritySettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "VaultSecuritySettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsPreserveExistingVaultXBehavior() {
        let settings = VaultSecuritySettings(defaults: defaults)

        XCTAssertFalse(settings.isFaceIDEnabled)
        XCTAssertEqual(settings.autoLockDelay, .immediately)
        XCTAssertEqual(settings.clipboardClearDelay, .seconds45)
        XCTAssertFalse(settings.hideTOTPCodesByDefault)
    }

    func testSettingsPersistAcrossStoreInstances() {
        let settings = VaultSecuritySettings(defaults: defaults)
        settings.isFaceIDEnabled = true
        settings.autoLockDelay = .seconds30
        settings.clipboardClearDelay = .seconds60
        settings.hideTOTPCodesByDefault = true

        let reloaded = VaultSecuritySettings(defaults: defaults)

        XCTAssertTrue(reloaded.isFaceIDEnabled)
        XCTAssertEqual(reloaded.autoLockDelay, .seconds30)
        XCTAssertEqual(reloaded.clipboardClearDelay, .seconds60)
        XCTAssertTrue(reloaded.hideTOTPCodesByDefault)
    }

    func testInvalidStoredValuesFallBackToSecureDefaults() {
        defaults.set(999, forKey: "VaultX.AutoLockDelay")
        defaults.set(999, forKey: "VaultX.ClipboardClearDelay")

        let settings = VaultSecuritySettings(defaults: defaults)

        XCTAssertEqual(settings.autoLockDelay, .immediately)
        XCTAssertEqual(settings.clipboardClearDelay, .seconds45)
    }
}
