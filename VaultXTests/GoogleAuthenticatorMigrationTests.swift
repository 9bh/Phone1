import Foundation
import XCTest
@testable import VaultX

final class GoogleAuthenticatorMigrationTests: XCTestCase {
    func testParsesSingleGoogleMigrationPayload() throws {
        let url = makeMigrationURL(
            accounts: [
                TestOTP(
                    secret: Data([1, 2, 3, 4, 5]),
                    name: "Google:user@example.com",
                    issuer: "Google",
                    algorithm: 1,
                    digits: 1,
                    type: 2
                )
            ]
        )

        let batch = try GoogleAuthenticatorMigrationParser.parse(url)

        XCTAssertEqual(batch.batchSize, 1)
        XCTAssertEqual(batch.batchIndex, 0)
        XCTAssertEqual(batch.accounts.count, 1)
        XCTAssertEqual(batch.accounts[0].name, "user@example.com")
        XCTAssertEqual(batch.accounts[0].issuer, "Google")
        XCTAssertEqual(batch.accounts[0].secret, "AEBAGBAF")
        XCTAssertEqual(batch.accounts[0].algorithm, .sha1)
        XCTAssertEqual(batch.accounts[0].digits, 6)
        XCTAssertEqual(batch.accounts[0].period, 30)
    }

    func testParsesSHA256AndEightDigits() throws {
        let url = makeMigrationURL(
            accounts: [
                TestOTP(
                    secret: Data("secret-value".utf8),
                    name: "employee@example.com",
                    issuer: "Work",
                    algorithm: 2,
                    digits: 2,
                    type: 2
                )
            ]
        )

        let account = try GoogleAuthenticatorMigrationParser.parse(url).accounts[0]
        XCTAssertEqual(account.algorithm, .sha256)
        XCTAssertEqual(account.digits, 8)
    }

    func testParsesSHA512() throws {
        let url = makeMigrationURL(
            accounts: [
                TestOTP(
                    secret: Data("another-secret".utf8),
                    name: "user",
                    issuer: "Example",
                    algorithm: 3,
                    digits: 1,
                    type: 2
                )
            ]
        )

        XCTAssertEqual(
            try GoogleAuthenticatorMigrationParser.parse(url).accounts[0].algorithm,
            .sha512
        )
    }

    func testRejectsHOTP() {
        let url = makeMigrationURL(
            accounts: [
                TestOTP(
                    secret: Data([1, 2, 3]),
                    name: "hotp-user",
                    issuer: "Legacy",
                    algorithm: 1,
                    digits: 1,
                    type: 1
                )
            ]
        )

        XCTAssertThrowsError(try GoogleAuthenticatorMigrationParser.parse(url)) { error in
            XCTAssertEqual(error as? GoogleAuthenticatorMigrationError, .unsupportedOTPType)
        }
    }

    func testRejectsUnsupportedAlgorithm() {
        let url = makeMigrationURL(
            accounts: [
                TestOTP(
                    secret: Data([1, 2, 3]),
                    name: "user",
                    issuer: "Legacy",
                    algorithm: 4,
                    digits: 1,
                    type: 2
                )
            ]
        )

        XCTAssertThrowsError(try GoogleAuthenticatorMigrationParser.parse(url)) { error in
            XCTAssertEqual(error as? GoogleAuthenticatorMigrationError, .unsupportedAlgorithm)
        }
    }

    func testCollectorCombinesPartsInBatchIndexOrder() throws {
        var collector = GoogleAuthenticatorMigrationCollector()
        let second = try GoogleAuthenticatorMigrationParser.parse(
            makeMigrationURL(
                accounts: [TestOTP.basic(name: "second")],
                batchSize: 2,
                batchIndex: 1,
                batchID: 77
            )
        )
        let first = try GoogleAuthenticatorMigrationParser.parse(
            makeMigrationURL(
                accounts: [TestOTP.basic(name: "first")],
                batchSize: 2,
                batchIndex: 0,
                batchID: 77
            )
        )

        try collector.add(second)
        XCTAssertFalse(collector.isComplete)
        try collector.add(first)

        XCTAssertTrue(collector.isComplete)
        XCTAssertEqual(collector.accounts.map(\.name), ["first", "second"])
    }

    func testCollectorRejectsDuplicatePart() throws {
        var collector = GoogleAuthenticatorMigrationCollector()
        let batch = try GoogleAuthenticatorMigrationParser.parse(
            makeMigrationURL(
                accounts: [TestOTP.basic(name: "one")],
                batchSize: 2,
                batchIndex: 0,
                batchID: 99
            )
        )

        try collector.add(batch)
        XCTAssertThrowsError(try collector.add(batch)) { error in
            XCTAssertEqual(error as? GoogleAuthenticatorMigrationError, .duplicateBatchPart)
        }
    }

    func testCollectorRejectsDifferentBatch() throws {
        var collector = GoogleAuthenticatorMigrationCollector()
        let first = try GoogleAuthenticatorMigrationParser.parse(
            makeMigrationURL(
                accounts: [TestOTP.basic(name: "one")],
                batchSize: 2,
                batchIndex: 0,
                batchID: 10
            )
        )
        let different = try GoogleAuthenticatorMigrationParser.parse(
            makeMigrationURL(
                accounts: [TestOTP.basic(name: "two")],
                batchSize: 2,
                batchIndex: 1,
                batchID: 11
            )
        )

        try collector.add(first)
        XCTAssertThrowsError(try collector.add(different)) { error in
            XCTAssertEqual(error as? GoogleAuthenticatorMigrationError, .batchMismatch)
        }
    }

    func testMatcherFindsStrongEmailAndIssuerMatch() {
        let account = VaultAccount(
            siteURL: "google.com",
            email: "user@example.com",
            password: "password",
            username: "",
            notes: ""
        )
        let imported = GoogleAuthenticatorImportedAccount(
            name: "user@example.com",
            issuer: "Google",
            secret: "JBSWY3DPEHPK3PXP",
            algorithm: .sha1,
            digits: 6
        )

        let suggestion = GoogleAuthenticatorAccountMatcher.suggestion(
            for: imported,
            among: [account]
        )

        XCTAssertEqual(suggestion.accountID, account.id)
        XCTAssertEqual(suggestion.strength, .strong)
    }

    func testMatcherDetectsSecretAlreadyStored() {
        let account = VaultAccount(
            siteURL: "example.com",
            email: "user@example.com",
            password: "",
            username: "",
            notes: "",
            has2FA: true,
            totpSecret: "JBSW-Y3DP EHPK3PXP"
        )
        let imported = GoogleAuthenticatorImportedAccount(
            name: "different@example.com",
            issuer: "Other",
            secret: "jbswy3dpehpk3pxp",
            algorithm: .sha1,
            digits: 6
        )

        let suggestion = GoogleAuthenticatorAccountMatcher.suggestion(
            for: imported,
            among: [account]
        )

        XCTAssertEqual(suggestion.accountID, account.id)
        XCTAssertEqual(suggestion.strength, .alreadyImported)
    }

    func testRejectsNormalOTPAuthURL() {
        XCTAssertThrowsError(
            try GoogleAuthenticatorMigrationParser.parse(
                "otpauth://totp/Example:user?secret=JBSWY3DPEHPK3PXP"
            )
        ) { error in
            XCTAssertEqual(error as? GoogleAuthenticatorMigrationError, .invalidURL)
        }
    }

    private struct TestOTP {
        let secret: Data
        let name: String
        let issuer: String
        let algorithm: UInt64
        let digits: UInt64
        let type: UInt64

        static func basic(name: String) -> TestOTP {
            TestOTP(
                secret: Data([1, 2, 3, 4]),
                name: name,
                issuer: "Example",
                algorithm: 1,
                digits: 1,
                type: 2
            )
        }
    }

    private func makeMigrationURL(
        accounts: [TestOTP],
        version: UInt64 = 1,
        batchSize: UInt64 = 1,
        batchIndex: UInt64 = 0,
        batchID: UInt64 = 1
    ) -> String {
        var payload = Data()
        for account in accounts {
            appendLengthDelimited(field: 1, value: encodeOTP(account), to: &payload)
        }
        appendVarintField(2, version, to: &payload)
        appendVarintField(3, batchSize, to: &payload)
        appendVarintField(4, batchIndex, to: &payload)
        appendVarintField(5, batchID, to: &payload)

        var components = URLComponents()
        components.scheme = "otpauth-migration"
        components.host = "offline"
        components.queryItems = [URLQueryItem(name: "data", value: payload.base64EncodedString())]
        return components.string!
    }

    private func encodeOTP(_ account: TestOTP) -> Data {
        var data = Data()
        appendLengthDelimited(field: 1, value: account.secret, to: &data)
        appendLengthDelimited(field: 2, value: Data(account.name.utf8), to: &data)
        appendLengthDelimited(field: 3, value: Data(account.issuer.utf8), to: &data)
        appendVarintField(4, account.algorithm, to: &data)
        appendVarintField(5, account.digits, to: &data)
        appendVarintField(6, account.type, to: &data)
        return data
    }

    private func appendLengthDelimited(field: UInt64, value: Data, to data: inout Data) {
        appendVarint((field << 3) | 2, to: &data)
        appendVarint(UInt64(value.count), to: &data)
        data.append(value)
    }

    private func appendVarintField(_ field: UInt64, _ value: UInt64, to data: inout Data) {
        appendVarint(field << 3, to: &data)
        appendVarint(value, to: &data)
    }

    private func appendVarint(_ value: UInt64, to data: inout Data) {
        var remaining = value
        while remaining >= 0x80 {
            data.append(UInt8(remaining & 0x7F) | 0x80)
            remaining >>= 7
        }
        data.append(UInt8(remaining))
    }
}
