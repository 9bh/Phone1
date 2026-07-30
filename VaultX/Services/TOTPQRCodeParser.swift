import Foundation

struct ScannedTOTPAccount: Identifiable, Equatable {
    let id = UUID()
    let accountName: String
    let issuer: String
    let secret: String
    let algorithm: TOTPAlgorithm
    let digits: Int
    let period: Int

    var maskedSecret: String {
        guard secret.count > 4 else { return String(repeating: "•", count: secret.count) }
        return String(repeating: "•", count: max(8, secret.count - 4)) + secret.suffix(4)
    }
}

enum TOTPQRCodeParserError: Error, Equatable {
    case unsupportedMigrationFormat
    case invalidScheme
    case unsupportedOTPType
    case missingAccountName
    case missingSecret
    case invalidSecret
    case unsupportedAlgorithm
    case unsupportedDigits
    case invalidPeriod

    var arabicMessage: String {
        switch self {
        case .unsupportedMigrationFormat:
            return "هذا رمز تصدير من Google Authenticator. سيتم دعمه في مرحلة الاستيراد الجماعي التالية."
        case .invalidScheme:
            return "هذا الرمز ليس رمز مصادقة ثنائية صالحًا."
        case .unsupportedOTPType:
            return "يدعم VaultX حاليًا رموز TOTP فقط."
        case .missingAccountName:
            return "رمز QR لا يحتوي على اسم حساب صالح."
        case .missingSecret:
            return "رمز QR لا يحتوي على مفتاح سري."
        case .invalidSecret:
            return "المفتاح السري داخل رمز QR غير صالح."
        case .unsupportedAlgorithm:
            return "الخوارزمية الموجودة في رمز QR غير مدعومة."
        case .unsupportedDigits:
            return "عدد خانات الرمز الموجود في QR غير مدعوم."
        case .invalidPeriod:
            return "الفترة الزمنية الموجودة في رمز QR غير صالحة."
        }
    }
}

struct TOTPQRCodeParser {
    static func parse(_ rawValue: String) throws -> ScannedTOTPAccount {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        if lowercased.hasPrefix("otpauth-migration://") {
            throw TOTPQRCodeParserError.unsupportedMigrationFormat
        }

        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "otpauth" else {
            throw TOTPQRCodeParserError.invalidScheme
        }

        guard components.host?.lowercased() == "totp" else {
            throw TOTPQRCodeParserError.unsupportedOTPType
        }

        let queryItems = (components.queryItems ?? []).reduce(into: [String: String]()) { result, item in
            let key = item.name.lowercased()
            if result[key] == nil {
                result[key] = item.value ?? ""
            }
        }

        guard let rawSecret = queryItems["secret"],
              !rawSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TOTPQRCodeParserError.missingSecret
        }

        let normalizedSecret = normalizeSecret(rawSecret)
        do {
            _ = try Base32Decoder.decode(normalizedSecret)
        } catch {
            throw TOTPQRCodeParserError.invalidSecret
        }

        let decodedPath = components.percentEncodedPath.removingPercentEncoding ?? components.path
        let label = decodedPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !label.isEmpty else {
            throw TOTPQRCodeParserError.missingAccountName
        }

        let labelParts = label.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let labelIssuer = labelParts.count == 2
            ? String(labelParts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let accountName = String(labelParts.last ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !accountName.isEmpty else {
            throw TOTPQRCodeParserError.missingAccountName
        }

        let queryIssuer = (queryItems["issuer"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let issuer = queryIssuer.isEmpty ? labelIssuer : queryIssuer

        let algorithm = try parseAlgorithm(queryItems["algorithm"])
        let digits = try parseDigits(queryItems["digits"])
        let period = try parsePeriod(queryItems["period"])

        return ScannedTOTPAccount(
            accountName: accountName,
            issuer: issuer,
            secret: normalizedSecret,
            algorithm: algorithm,
            digits: digits,
            period: period
        )
    }

    static func normalizeSecret(_ value: String) -> String {
        var normalized = value
            .filter { !$0.isWhitespace && $0 != "-" }
            .uppercased()

        while normalized.last == "=" {
            normalized.removeLast()
        }

        return normalized
    }

    private static func parseAlgorithm(_ rawValue: String?) throws -> TOTPAlgorithm {
        guard let rawValue, !rawValue.isEmpty else { return .sha1 }

        switch rawValue
            .replacingOccurrences(of: "-", with: "")
            .uppercased() {
        case "SHA1", "HMACSHA1":
            return .sha1
        case "SHA256", "HMACSHA256":
            return .sha256
        case "SHA512", "HMACSHA512":
            return .sha512
        default:
            throw TOTPQRCodeParserError.unsupportedAlgorithm
        }
    }

    private static func parseDigits(_ rawValue: String?) throws -> Int {
        guard let rawValue, !rawValue.isEmpty else { return 6 }
        guard let digits = Int(rawValue), digits == 6 || digits == 8 else {
            throw TOTPQRCodeParserError.unsupportedDigits
        }
        return digits
    }

    private static func parsePeriod(_ rawValue: String?) throws -> Int {
        guard let rawValue, !rawValue.isEmpty else { return 30 }
        guard let period = Int(rawValue), (1...300).contains(period) else {
            throw TOTPQRCodeParserError.invalidPeriod
        }
        return period
    }
}
