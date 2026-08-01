import Foundation
import CryptoKit
import Security

struct VaultBackupCryptoService {
    static let defaultIterationCount: UInt32 = 210_000
    static let maximumFileSize = 50 * 1024 * 1024

    private let iterationCount: UInt32
    private let minimumAcceptedIterations: UInt32
    private let maximumAcceptedIterations: UInt32

    init(
        iterationCount: UInt32 = VaultBackupCryptoService.defaultIterationCount,
        minimumAcceptedIterations: UInt32 = 100_000,
        maximumAcceptedIterations: UInt32 = 2_000_000
    ) {
        self.iterationCount = iterationCount
        self.minimumAcceptedIterations = minimumAcceptedIterations
        self.maximumAcceptedIterations = maximumAcceptedIterations
    }

    func createBackup(
        accounts: [VaultAccount],
        appVersion: String,
        password: String
    ) async throws -> Data {
        guard !accounts.isEmpty else {
            throw VaultBackupError.noAccountsAvailable
        }
        try validateNewPassword(password)

        let payload = VaultBackupPayload(
            sourceAppVersion: appVersion,
            accounts: accounts
        )

        let payloadData: Data
        do {
            payloadData = try JSONEncoder().encode(payload)
        } catch {
            throw VaultBackupError.encodingFailed
        }

        let iterations = iterationCount
        return try await Task.detached(priority: .userInitiated) {
            let salt = try Self.secureRandomData(count: 16)
            let key = try Self.deriveKey(
                password: password,
                salt: salt,
                iterations: iterations
            )
            let aad = Self.authenticatedData(
                formatVersion: VaultBackupEnvelope.currentFormatVersion,
                keyDerivation: VaultBackupEnvelope.kdfIdentifier,
                iterationCount: iterations,
                salt: salt
            )

            let sealedBox: AES.GCM.SealedBox
            do {
                sealedBox = try AES.GCM.seal(
                    payloadData,
                    using: key,
                    authenticating: aad
                )
            } catch {
                throw VaultBackupError.encryptionFailed
            }

            guard let combined = sealedBox.combined else {
                throw VaultBackupError.encryptionFailed
            }

            let envelope = VaultBackupEnvelope(
                magic: VaultBackupEnvelope.magic,
                formatVersion: VaultBackupEnvelope.currentFormatVersion,
                keyDerivation: VaultBackupEnvelope.kdfIdentifier,
                iterationCount: iterations,
                salt: salt,
                sealedPayload: combined
            )

            do {
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                return try encoder.encode(envelope)
            } catch {
                throw VaultBackupError.encodingFailed
            }
        }.value
    }

    func decryptBackup(
        _ backupData: Data,
        password: String
    ) async throws -> VaultBackupPayload {
        guard backupData.count <= Self.maximumFileSize else {
            throw VaultBackupError.fileTooLarge
        }
        guard !password.isEmpty else {
            throw VaultBackupError.invalidPasswordOrCorruptedFile
        }
        guard password.utf8.count <= 4_096 else {
            throw VaultBackupError.passwordTooLong
        }

        let envelope: VaultBackupEnvelope
        do {
            envelope = try PropertyListDecoder().decode(
                VaultBackupEnvelope.self,
                from: backupData
            )
        } catch {
            throw VaultBackupError.invalidBackupFile
        }

        guard envelope.magic == VaultBackupEnvelope.magic else {
            throw VaultBackupError.invalidBackupFile
        }
        guard envelope.formatVersion == VaultBackupEnvelope.currentFormatVersion else {
            throw VaultBackupError.unsupportedFormatVersion(envelope.formatVersion)
        }
        guard envelope.keyDerivation == VaultBackupEnvelope.kdfIdentifier else {
            throw VaultBackupError.unsupportedKeyDerivation
        }
        guard envelope.iterationCount >= minimumAcceptedIterations,
              envelope.iterationCount <= maximumAcceptedIterations,
              (16...64).contains(envelope.salt.count),
              envelope.sealedPayload.count >= 28 else {
            throw VaultBackupError.invalidKeyDerivationParameters
        }

        let decryptedData = try await Task.detached(priority: .userInitiated) {
            let key = try Self.deriveKey(
                password: password,
                salt: envelope.salt,
                iterations: envelope.iterationCount
            )
            let aad = Self.authenticatedData(
                formatVersion: envelope.formatVersion,
                keyDerivation: envelope.keyDerivation,
                iterationCount: envelope.iterationCount,
                salt: envelope.salt
            )

            do {
                let sealedBox = try AES.GCM.SealedBox(combined: envelope.sealedPayload)
                return try AES.GCM.open(
                    sealedBox,
                    using: key,
                    authenticating: aad
                )
            } catch {
                throw VaultBackupError.invalidPasswordOrCorruptedFile
            }
        }.value

        let payload: VaultBackupPayload
        do {
            payload = try JSONDecoder().decode(VaultBackupPayload.self, from: decryptedData)
        } catch {
            throw VaultBackupError.invalidPasswordOrCorruptedFile
        }

        guard payload.payloadVersion == VaultBackupPayload.currentVersion else {
            throw VaultBackupError.unsupportedPayloadVersion(payload.payloadVersion)
        }

        return payload
    }

    private func validateNewPassword(_ password: String) throws {
        guard password.count >= 10 else {
            throw VaultBackupError.passwordTooShort
        }
        guard password.utf8.count <= 4_096 else {
            throw VaultBackupError.passwordTooLong
        }
    }

    private static func secureRandomData(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw VaultBackupError.randomGenerationFailed
        }
        return Data(bytes)
    }

    private static func authenticatedData(
        formatVersion: UInt16,
        keyDerivation: String,
        iterationCount: UInt32,
        salt: Data
    ) -> Data {
        var data = Data(VaultBackupEnvelope.magic.utf8)
        data.append(0)
        data.append(contentsOf: withUnsafeBytes(of: formatVersion.bigEndian, Array.init))
        data.append(0)
        data.append(Data(keyDerivation.utf8))
        data.append(0)
        data.append(contentsOf: withUnsafeBytes(of: iterationCount.bigEndian, Array.init))
        data.append(salt)
        return data
    }

    private static func deriveKey(
        password: String,
        salt: Data,
        iterations: UInt32
    ) throws -> SymmetricKey {
        guard iterations > 0 else {
            throw VaultBackupError.invalidKeyDerivationParameters
        }

        let normalizedPassword = password.precomposedStringWithCanonicalMapping
        let passwordData = Data(normalizedPassword.utf8)
        guard !passwordData.isEmpty else {
            throw VaultBackupError.invalidPasswordOrCorruptedFile
        }

        let hmacKey = SymmetricKey(data: passwordData)
        var saltBlock = [UInt8](salt)
        saltBlock.append(contentsOf: [0, 0, 0, 1])

        var u = Array(
            HMAC<SHA256>.authenticationCode(
                for: Data(saltBlock),
                using: hmacKey
            )
        )
        var output = u

        if iterations > 1 {
            for _ in 1..<iterations {
                u = Array(
                    HMAC<SHA256>.authenticationCode(
                        for: Data(u),
                        using: hmacKey
                    )
                )
                for index in output.indices {
                    output[index] ^= u[index]
                }
            }
        }

        let key = SymmetricKey(data: Data(output.prefix(32)))
        u.replaceSubrange(u.indices, with: repeatElement(0, count: u.count))
        output.replaceSubrange(output.indices, with: repeatElement(0, count: output.count))
        return key
    }
}
