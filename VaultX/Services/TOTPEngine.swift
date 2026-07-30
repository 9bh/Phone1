import Foundation
import CryptoKit

protocol TOTPGenerating {
    func generate(configuration: TOTPConfiguration, at date: Date) throws -> TOTPCode
}

enum TOTPError: Error, Equatable {
    case emptySecret
    case invalidPeriod
    case invalidDigits
    case invalidTimestamp
}

struct TOTPEngine: TOTPGenerating {
    func generate(configuration: TOTPConfiguration, at date: Date) throws -> TOTPCode {
        guard !configuration.secret.isEmpty else {
            throw TOTPError.emptySecret
        }
        guard configuration.period > 0 else {
            throw TOTPError.invalidPeriod
        }
        guard configuration.digits == 6 || configuration.digits == 8 else {
            throw TOTPError.invalidDigits
        }

        let unixTime = date.timeIntervalSince1970
        guard unixTime.isFinite, unixTime >= 0 else {
            throw TOTPError.invalidTimestamp
        }

        let counter = UInt64(floor(unixTime / Double(configuration.period)))
        var bigEndianCounter = counter.bigEndian
        let counterData = Data(
            bytes: &bigEndianCounter,
            count: MemoryLayout<UInt64>.size
        )

        let digest: Data
        let key = SymmetricKey(data: configuration.secret)

        switch configuration.algorithm {
        case .sha1:
            digest = Data(
                HMAC<Insecure.SHA1>.authenticationCode(
                    for: counterData,
                    using: key
                )
            )
        case .sha256:
            digest = Data(
                HMAC<SHA256>.authenticationCode(
                    for: counterData,
                    using: key
                )
            )
        case .sha512:
            digest = Data(
                HMAC<SHA512>.authenticationCode(
                    for: counterData,
                    using: key
                )
            )
        }

        guard let lastByte = digest.last else {
            throw TOTPError.emptySecret
        }

        let offset = Int(lastByte & 0x0F)
        guard offset + 3 < digest.count else {
            throw TOTPError.emptySecret
        }

        let binaryCode =
            (UInt32(digest[offset] & 0x7F) << 24) |
            (UInt32(digest[offset + 1]) << 16) |
            (UInt32(digest[offset + 2]) << 8) |
            UInt32(digest[offset + 3])

        let modulus: UInt32 = configuration.digits == 6 ? 1_000_000 : 100_000_000
        let numericCode = binaryCode % modulus
        let formattedCode = String(
            format: "%0*u",
            configuration.digits,
            numericCode
        )

        let validFromTimestamp = Double(counter * UInt64(configuration.period))
        let validFrom = Date(timeIntervalSince1970: validFromTimestamp)
        let validUntil = validFrom.addingTimeInterval(TimeInterval(configuration.period))
        let remainingSeconds = max(
            0,
            Int(ceil(validUntil.timeIntervalSince(date)))
        )

        return TOTPCode(
            value: formattedCode,
            validFrom: validFrom,
            validUntil: validUntil,
            remainingSeconds: remainingSeconds
        )
    }
}
