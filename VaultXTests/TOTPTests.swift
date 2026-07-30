import Foundation
import XCTest
@testable import VaultX

final class TOTPTests: XCTestCase {
    private let sha1Seed = Data("12345678901234567890".utf8)
    private let sha256Seed = Data("12345678901234567890123456789012".utf8)
    private let sha512Seed = Data("1234567890123456789012345678901234567890123456789012345678901234".utf8)

    // MARK: - Base32

    func testBase32DecodesValidUnpaddedValue() throws {
        let decoded = try Base32Decoder.decode("JBSWY3DP")
        XCTAssertEqual(decoded, Data("Hello".utf8))
    }

    func testBase32AcceptsLowercase() throws {
        let decoded = try Base32Decoder.decode("jbswy3dp")
        XCTAssertEqual(decoded, Data("Hello".utf8))
    }

    func testBase32IgnoresWhitespaceAndHyphens() throws {
        let decoded = try Base32Decoder.decode("JBSW Y3-DP\n")
        XCTAssertEqual(decoded, Data("Hello".utf8))
    }

    func testBase32AcceptsValidPadding() throws {
        let decoded = try Base32Decoder.decode("MZXW6===")
        XCTAssertEqual(decoded, Data("foo".utf8))
    }

    func testBase32RejectsInvalidCharacter() {
        XCTAssertThrowsError(try Base32Decoder.decode("JBSWY3D8")) { error in
            XCTAssertEqual(error as? Base32DecodingError, .invalidCharacter("8"))
        }
    }

    func testBase32RejectsEmptyInput() {
        XCTAssertThrowsError(try Base32Decoder.decode("  - \n")) { error in
            XCTAssertEqual(error as? Base32DecodingError, .emptyInput)
        }
    }

    func testBase32RejectsPaddingInMiddle() {
        XCTAssertThrowsError(try Base32Decoder.decode("MZX=6===")) { error in
            XCTAssertEqual(error as? Base32DecodingError, .invalidLength)
        }
    }

    func testBase32RejectsImpossibleLength() {
        XCTAssertThrowsError(try Base32Decoder.decode("A")) { error in
            XCTAssertEqual(error as? Base32DecodingError, .invalidLength)
        }
    }

    func testBase32RejectsNonZeroTrailingBits() {
        XCTAssertThrowsError(try Base32Decoder.decode("MZ")) { error in
            XCTAssertEqual(error as? Base32DecodingError, .invalidLength)
        }
    }

    // MARK: - RFC 6238

    func testRFC6238SHA1Vectors() throws {
        try assertVectors(
            secret: sha1Seed,
            algorithm: .sha1,
            expected: [
                59: "94287082",
                1_111_111_109: "07081804",
                1_111_111_111: "14050471",
                1_234_567_890: "89005924",
                2_000_000_000: "69279037",
                20_000_000_000: "65353130"
            ]
        )
    }

    func testRFC6238SHA256Vectors() throws {
        try assertVectors(
            secret: sha256Seed,
            algorithm: .sha256,
            expected: [
                59: "46119246",
                1_111_111_109: "68084774",
                1_111_111_111: "67062674",
                1_234_567_890: "91819424",
                2_000_000_000: "90698825",
                20_000_000_000: "77737706"
            ]
        )
    }

    func testRFC6238SHA512Vectors() throws {
        try assertVectors(
            secret: sha512Seed,
            algorithm: .sha512,
            expected: [
                59: "90693936",
                1_111_111_109: "25091201",
                1_111_111_111: "99943326",
                1_234_567_890: "93441116",
                2_000_000_000: "38618901",
                20_000_000_000: "47863826"
            ]
        )
    }

    // MARK: - Engine behavior

    func testSixDigitCodePreservesLeadingZero() throws {
        let configuration = TOTPConfiguration(
            secret: sha1Seed,
            algorithm: .sha1,
            digits: 6,
            period: 30
        )

        let code = try TOTPEngine().generate(
            configuration: configuration,
            at: Date(timeIntervalSince1970: 1_111_111_109)
        )

        XCTAssertEqual(code.value, "081804")
        XCTAssertEqual(code.value.count, 6)
    }

    func testEightDigitCodeHasExpectedLength() throws {
        let configuration = TOTPConfiguration(
            secret: sha1Seed,
            algorithm: .sha1,
            digits: 8,
            period: 30
        )

        let code = try TOTPEngine().generate(
            configuration: configuration,
            at: Date(timeIntervalSince1970: 59)
        )

        XCTAssertEqual(code.value, "94287082")
        XCTAssertEqual(code.value.count, 8)
    }

    func testThirtySecondPeriod() throws {
        let configuration = TOTPConfiguration(
            secret: sha1Seed,
            algorithm: .sha1,
            digits: 6,
            period: 30
        )

        let code = try TOTPEngine().generate(
            configuration: configuration,
            at: Date(timeIntervalSince1970: 35)
        )

        XCTAssertEqual(code.value, "287082")
        XCTAssertEqual(code.remainingSeconds, 25)
    }

    func testSixtySecondPeriod() throws {
        let configuration = TOTPConfiguration(
            secret: sha1Seed,
            algorithm: .sha1,
            digits: 6,
            period: 60
        )

        let code = try TOTPEngine().generate(
            configuration: configuration,
            at: Date(timeIntervalSince1970: 59)
        )

        XCTAssertEqual(code.value, "755224")
        XCTAssertEqual(code.remainingSeconds, 1)
    }

    func testExactBoundaryStartsFreshPeriod() throws {
        let configuration = TOTPConfiguration(
            secret: sha1Seed,
            algorithm: .sha1,
            digits: 6,
            period: 30
        )

        let code = try TOTPEngine().generate(
            configuration: configuration,
            at: Date(timeIntervalSince1970: 60)
        )

        XCTAssertEqual(code.value, "359152")
        XCTAssertEqual(code.remainingSeconds, 30)
    }

    func testFractionalSecondRoundsRemainingTimeUp() throws {
        let configuration = TOTPConfiguration(
            secret: sha1Seed,
            algorithm: .sha1,
            digits: 6,
            period: 30
        )

        let code = try TOTPEngine().generate(
            configuration: configuration,
            at: Date(timeIntervalSince1970: 59.75)
        )

        XCTAssertEqual(code.remainingSeconds, 1)
    }

    func testInvalidDigitsFail() {
        for digits in [0, 5, 7, 9] {
            let configuration = TOTPConfiguration(
                secret: sha1Seed,
                algorithm: .sha1,
                digits: digits,
                period: 30
            )

            XCTAssertThrowsError(
                try TOTPEngine().generate(configuration: configuration, at: Date())
            ) { error in
                XCTAssertEqual(error as? TOTPError, .invalidDigits)
            }
        }
    }

    func testInvalidPeriodFails() {
        let configuration = TOTPConfiguration(
            secret: sha1Seed,
            algorithm: .sha1,
            digits: 6,
            period: 0
        )

        XCTAssertThrowsError(
            try TOTPEngine().generate(configuration: configuration, at: Date())
        ) { error in
            XCTAssertEqual(error as? TOTPError, .invalidPeriod)
        }
    }

    func testEmptySecretFails() {
        let configuration = TOTPConfiguration(
            secret: Data(),
            algorithm: .sha1,
            digits: 6,
            period: 30
        )

        XCTAssertThrowsError(
            try TOTPEngine().generate(configuration: configuration, at: Date())
        ) { error in
            XCTAssertEqual(error as? TOTPError, .emptySecret)
        }
    }

    func testNegativeTimestampFails() {
        let configuration = TOTPConfiguration(
            secret: sha1Seed,
            algorithm: .sha1,
            digits: 6,
            period: 30
        )

        XCTAssertThrowsError(
            try TOTPEngine().generate(
                configuration: configuration,
                at: Date(timeIntervalSince1970: -1)
            )
        ) { error in
            XCTAssertEqual(error as? TOTPError, .invalidTimestamp)
        }
    }

    // MARK: - Codable compatibility

    func testLegacyAccountWithoutTOTPDecodesWithDefaults() throws {
        struct LegacyAccount: Codable {
            let id: UUID
            let siteURL: String
            let email: String
            let password: String
            let username: String
            let notes: String
            let has2FA: Bool
            let hasBackupFile: Bool
        }

        let legacy = LegacyAccount(
            id: UUID(),
            siteURL: "example.com",
            email: "user@example.com",
            password: "secret",
            username: "user",
            notes: "note",
            has2FA: false,
            hasBackupFile: false
        )

        let data = try PropertyListEncoder().encode(legacy)
        let decoded = try PropertyListDecoder().decode(VaultAccount.self, from: data)

        XCTAssertNil(decoded.totpSecret)
        XCTAssertNil(decoded.totpIssuer)
        XCTAssertEqual(decoded.totpAlgorithm, .sha1)
        XCTAssertEqual(decoded.totpDigits, 6)
        XCTAssertEqual(decoded.totpPeriod, 30)
    }

    func testTOTPAccountRoundTripsThroughPropertyList() throws {
        let account = makeTOTPAccount()
        let data = try PropertyListEncoder().encode(account)
        let decoded = try PropertyListDecoder().decode(VaultAccount.self, from: data)

        XCTAssertEqual(decoded, account)
    }

    // MARK: - otpauth QR parsing

    func testQRCodeParserUsesManualDefaultsWhenParametersAreMissing() throws {
        let parsed = try TOTPQRCodeParser.parse(
            "otpauth://totp/Example:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example"
        )

        XCTAssertEqual(parsed.accountName, "user@example.com")
        XCTAssertEqual(parsed.issuer, "Example")
        XCTAssertEqual(parsed.secret, "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(parsed.algorithm, .sha1)
        XCTAssertEqual(parsed.digits, 6)
        XCTAssertEqual(parsed.period, 30)
    }

    func testQRCodeParserHonorsExplicitQRCodeSettings() throws {
        let parsed = try TOTPQRCodeParser.parse(
            "otpauth://totp/Secure:user?secret=JBSWY3DPEHPK3PXP&issuer=Secure&algorithm=SHA256&digits=8&period=60"
        )

        XCTAssertEqual(parsed.algorithm, .sha256)
        XCTAssertEqual(parsed.digits, 8)
        XCTAssertEqual(parsed.period, 60)
    }

    func testQRCodeParserAcceptsSHA512AndCustomPositivePeriod() throws {
        let parsed = try TOTPQRCodeParser.parse(
            "otpauth://totp/Service:user?secret=JBSWY3DPEHPK3PXP&algorithm=SHA512&digits=6&period=45"
        )

        XCTAssertEqual(parsed.algorithm, .sha512)
        XCTAssertEqual(parsed.digits, 6)
        XCTAssertEqual(parsed.period, 45)
    }

    func testQRCodeParserDecodesPercentEncodedLabel() throws {
        let parsed = try TOTPQRCodeParser.parse(
            "otpauth://totp/My%20Service:user%2Btest%40example.com?secret=JBSWY3DPEHPK3PXP"
        )

        XCTAssertEqual(parsed.issuer, "My Service")
        XCTAssertEqual(parsed.accountName, "user+test@example.com")
    }

    func testQRCodeParserNormalizesSecretFormatting() throws {
        let parsed = try TOTPQRCodeParser.parse(
            "otpauth://totp/Example:user?secret=jbsw-y3dp-ehpk3pxp%3D"
        )

        XCTAssertEqual(parsed.secret, "JBSWY3DPEHPK3PXP")
    }

    func testQRCodeParserRejectsHOTP() {
        XCTAssertThrowsError(
            try TOTPQRCodeParser.parse(
                "otpauth://hotp/Example:user?secret=JBSWY3DPEHPK3PXP&counter=1"
            )
        ) { error in
            XCTAssertEqual(error as? TOTPQRCodeParserError, .unsupportedOTPType)
        }
    }

    func testQRCodeParserRejectsMissingSecret() {
        XCTAssertThrowsError(
            try TOTPQRCodeParser.parse("otpauth://totp/Example:user?issuer=Example")
        ) { error in
            XCTAssertEqual(error as? TOTPQRCodeParserError, .missingSecret)
        }
    }

    func testQRCodeParserRejectsUnsupportedDigits() {
        XCTAssertThrowsError(
            try TOTPQRCodeParser.parse(
                "otpauth://totp/Example:user?secret=JBSWY3DPEHPK3PXP&digits=7"
            )
        ) { error in
            XCTAssertEqual(error as? TOTPQRCodeParserError, .unsupportedDigits)
        }
    }

    func testQRCodeParserRejectsGoogleMigrationUntilNextPhase() {
        XCTAssertThrowsError(
            try TOTPQRCodeParser.parse("otpauth-migration://offline?data=abc")
        ) { error in
            XCTAssertEqual(error as? TOTPQRCodeParserError, .unsupportedMigrationFormat)
        }
    }

    private func assertVectors(
        secret: Data,
        algorithm: TOTPAlgorithm,
        expected: [TimeInterval: String]
    ) throws {
        let configuration = TOTPConfiguration(
            secret: secret,
            algorithm: algorithm,
            digits: 8,
            period: 30
        )

        for timestamp in expected.keys.sorted() {
            let code = try TOTPEngine().generate(
                configuration: configuration,
                at: Date(timeIntervalSince1970: timestamp)
            )
            XCTAssertEqual(code.value, expected[timestamp]!, "Timestamp: \(timestamp)")
        }
    }

    private func makeTOTPAccount(id: UUID = UUID()) -> VaultAccount {
        VaultAccount(
            id: id,
            siteURL: "example.com",
            email: "user@example.com",
            password: "secret",
            username: "user",
            notes: "note",
            has2FA: true,
            hasBackupFile: false,
            totpSecret: "JBSWY3DPEHPK3PXP",
            totpIssuer: "Example",
            totpAlgorithm: .sha256,
            totpDigits: 8,
            totpPeriod: 60
        )
    }
}

private actor TOTPTestPersistence: VaultAccountsPersisting {
    private var accounts: [VaultAccount]

    init(accounts: [VaultAccount] = []) {
        self.accounts = accounts
    }

    func vaultExists() async throws -> Bool {
        !accounts.isEmpty
    }

    func loadAccounts() async throws -> [VaultAccount] {
        accounts
    }

    func saveAccounts(_ accounts: [VaultAccount]) async throws {
        self.accounts = accounts
    }
}

@MainActor
final class TOTPPersistenceIntegrationTests: XCTestCase {
    func testTOTPAccountPersistsAcrossFreshStoreInstance() async {
        let account = makeAccount()
        let persistence = TOTPTestPersistence()
        let firstStore = VaultAccountsStore(persistence: persistence)

        await firstStore.unlockAndLoad()
        let result = await firstStore.addAccount(account)
        guard case .success = result else {
            return XCTFail("TOTP account failed to save")
        }

        let freshStore = VaultAccountsStore(persistence: persistence)
        await freshStore.unlockAndLoad()
        XCTAssertEqual(freshStore.accounts, [account])
    }

    func testEditingTOTPSettingsPersistsAcrossFreshStoreInstance() async {
        let original = makeAccount()
        var edited = original
        edited.totpAlgorithm = .sha512
        edited.totpDigits = 6
        edited.totpPeriod = 30

        let persistence = TOTPTestPersistence(accounts: [original])
        let store = VaultAccountsStore(persistence: persistence)
        await store.unlockAndLoad()

        let result = await store.updateAccount(edited)
        guard case .success = result else {
            return XCTFail("TOTP account failed to update")
        }

        let freshStore = VaultAccountsStore(persistence: persistence)
        await freshStore.unlockAndLoad()
        XCTAssertEqual(freshStore.accounts, [edited])
    }

    func testDeletingTOTPAccountRemovesSecretWithAccount() async {
        let account = makeAccount()
        let persistence = TOTPTestPersistence(accounts: [account])
        let store = VaultAccountsStore(persistence: persistence)
        await store.unlockAndLoad()

        let result = await store.deleteAccount(id: account.id)
        guard case .success = result else {
            return XCTFail("TOTP account failed to delete")
        }

        let freshStore = VaultAccountsStore(persistence: persistence)
        await freshStore.unlockAndLoad()
        XCTAssertTrue(freshStore.accounts.isEmpty)
    }

    func testLockClearsTOTPAccountFromObservableMemory() async {
        let account = makeAccount()
        let persistence = TOTPTestPersistence(accounts: [account])
        let store = VaultAccountsStore(persistence: persistence)
        await store.unlockAndLoad()

        store.lockAndClear()

        XCTAssertEqual(store.loadState, .locked)
        XCTAssertTrue(store.accounts.isEmpty)
    }

    private func makeAccount(id: UUID = UUID()) -> VaultAccount {
        VaultAccount(
            id: id,
            siteURL: "example.com",
            email: "user@example.com",
            password: "secret",
            username: "user",
            notes: "note",
            has2FA: true,
            hasBackupFile: false,
            totpSecret: "JBSWY3DPEHPK3PXP",
            totpIssuer: "Example",
            totpAlgorithm: .sha1,
            totpDigits: 6,
            totpPeriod: 30
        )
    }
}
