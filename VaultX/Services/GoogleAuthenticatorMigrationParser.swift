import Foundation

enum GoogleAuthenticatorMigrationError: Error, Equatable {
    case invalidURL
    case missingPayload
    case invalidBase64
    case malformedPayload
    case emptyPayload
    case unsupportedAlgorithm
    case unsupportedDigits
    case unsupportedOTPType
    case invalidBatchMetadata
    case batchMismatch
    case duplicateBatchPart

    var arabicMessage: String {
        switch self {
        case .invalidURL:
            return "هذا الرمز ليس رمز تصدير صالحًا من Google Authenticator."
        case .missingPayload:
            return "رمز التصدير لا يحتوي على بيانات قابلة للاستيراد."
        case .invalidBase64, .malformedPayload:
            return "تعذر قراءة بيانات التصدير. أعد إنشاء رمز التصدير من Google Authenticator."
        case .emptyPayload:
            return "رمز التصدير لا يحتوي على حسابات."
        case .unsupportedAlgorithm:
            return "يحتوي التصدير على خوارزمية غير مدعومة."
        case .unsupportedDigits:
            return "يحتوي التصدير على عدد خانات غير مدعوم."
        case .unsupportedOTPType:
            return "يحتوي التصدير على حساب HOTP غير مدعوم حاليًا."
        case .invalidBatchMetadata:
            return "بيانات مجموعة التصدير غير مكتملة أو غير صالحة."
        case .batchMismatch:
            return "هذا الرمز ينتمي إلى مجموعة تصدير مختلفة. أكمل الرموز التابعة للمجموعة نفسها."
        case .duplicateBatchPart:
            return "تم مسح هذا الجزء من مجموعة التصدير مسبقًا."
        }
    }
}

struct GoogleAuthenticatorMigrationParser {
    static func parse(_ rawValue: String) throws -> GoogleAuthenticatorMigrationBatch {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "otpauth-migration",
              components.host?.lowercased() == "offline" else {
            throw GoogleAuthenticatorMigrationError.invalidURL
        }

        guard let rawData = components.queryItems?.first(where: { $0.name.lowercased() == "data" })?.value,
              !rawData.isEmpty else {
            throw GoogleAuthenticatorMigrationError.missingPayload
        }

        var base64 = rawData.replacingOccurrences(of: " ", with: "+")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }

        guard let payload = Data(base64Encoded: base64) else {
            throw GoogleAuthenticatorMigrationError.invalidBase64
        }

        do {
            return try parsePayload(payload)
        } catch let error as GoogleAuthenticatorMigrationError {
            throw error
        } catch {
            throw GoogleAuthenticatorMigrationError.malformedPayload
        }
    }

    private static func parsePayload(_ data: Data) throws -> GoogleAuthenticatorMigrationBatch {
        var reader = ProtobufReader(data: data)
        var accounts: [GoogleAuthenticatorImportedAccount] = []
        var version = 0
        var batchSize = 1
        var batchIndex = 0
        var batchID = 0

        while !reader.isAtEnd {
            let tag = try reader.readVarint()
            let fieldNumber = Int(tag >> 3)
            let wireType = Int(tag & 0x07)

            switch (fieldNumber, wireType) {
            case (1, 2):
                let accountData = try reader.readLengthDelimited()
                accounts.append(try parseOTPParameters(accountData))
            case (2, 0):
                version = Int(try reader.readVarint())
            case (3, 0):
                batchSize = Int(try reader.readVarint())
            case (4, 0):
                batchIndex = Int(try reader.readVarint())
            case (5, 0):
                batchID = Int(try reader.readVarint())
            default:
                try reader.skipField(wireType: wireType)
            }
        }

        guard !accounts.isEmpty else {
            throw GoogleAuthenticatorMigrationError.emptyPayload
        }
        guard batchSize > 0, batchIndex >= 0, batchIndex < batchSize else {
            throw GoogleAuthenticatorMigrationError.invalidBatchMetadata
        }

        return GoogleAuthenticatorMigrationBatch(
            accounts: accounts,
            version: version,
            batchSize: batchSize,
            batchIndex: batchIndex,
            batchID: batchID
        )
    }

    private static func parseOTPParameters(_ data: Data) throws -> GoogleAuthenticatorImportedAccount {
        var reader = ProtobufReader(data: data)
        var secret = Data()
        var name = ""
        var issuer = ""
        var algorithmRaw = 0
        var digitsRaw = 0
        var typeRaw = 0

        while !reader.isAtEnd {
            let tag = try reader.readVarint()
            let fieldNumber = Int(tag >> 3)
            let wireType = Int(tag & 0x07)

            switch (fieldNumber, wireType) {
            case (1, 2):
                secret = try reader.readLengthDelimited()
            case (2, 2):
                name = try reader.readString()
            case (3, 2):
                issuer = try reader.readString()
            case (4, 0):
                algorithmRaw = Int(try reader.readVarint())
            case (5, 0):
                digitsRaw = Int(try reader.readVarint())
            case (6, 0):
                typeRaw = Int(try reader.readVarint())
            default:
                try reader.skipField(wireType: wireType)
            }
        }

        guard !secret.isEmpty else {
            throw GoogleAuthenticatorMigrationError.malformedPayload
        }

        let algorithm: TOTPAlgorithm
        switch algorithmRaw {
        case 0, 1: algorithm = .sha1
        case 2: algorithm = .sha256
        case 3: algorithm = .sha512
        default: throw GoogleAuthenticatorMigrationError.unsupportedAlgorithm
        }

        let digits: Int
        switch digitsRaw {
        case 0, 1: digits = 6
        case 2: digits = 8
        default: throw GoogleAuthenticatorMigrationError.unsupportedDigits
        }

        guard typeRaw == 0 || typeRaw == 2 else {
            throw GoogleAuthenticatorMigrationError.unsupportedOTPType
        }

        let normalizedIssuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = normalizedAccountName(name, issuer: normalizedIssuer)

        return GoogleAuthenticatorImportedAccount(
            name: normalizedName,
            issuer: normalizedIssuer,
            secret: Base32Encoder.encode(secret),
            algorithm: algorithm,
            digits: digits,
            period: 30
        )
    }

    private static func normalizedAccountName(_ value: String, issuer: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !issuer.isEmpty {
            let prefix = issuer + ":"
            if result.lowercased().hasPrefix(prefix.lowercased()) {
                result = String(result.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return result
    }
}

struct GoogleAuthenticatorMigrationCollector: Equatable {
    private(set) var batchID: Int?
    private(set) var batchSize: Int?
    private(set) var parts: [Int: GoogleAuthenticatorMigrationBatch] = [:]

    var scannedPartCount: Int { parts.count }
    var expectedPartCount: Int { batchSize ?? 0 }
    var isComplete: Bool { batchSize != nil && parts.count == batchSize }

    var accounts: [GoogleAuthenticatorImportedAccount] {
        parts.keys.sorted().flatMap { parts[$0]?.accounts ?? [] }
    }

    mutating func add(_ batch: GoogleAuthenticatorMigrationBatch) throws {
        if let existingBatchID = batchID {
            guard existingBatchID == batch.batchID, batchSize == batch.batchSize else {
                throw GoogleAuthenticatorMigrationError.batchMismatch
            }
        } else {
            batchID = batch.batchID
            batchSize = batch.batchSize
        }

        guard parts[batch.batchIndex] == nil else {
            throw GoogleAuthenticatorMigrationError.duplicateBatchPart
        }
        parts[batch.batchIndex] = batch
    }

    mutating func reset() {
        batchID = nil
        batchSize = nil
        parts = [:]
    }
}

struct GoogleAuthenticatorAccountMatcher {
    static func suggestion(
        for imported: GoogleAuthenticatorImportedAccount,
        among accounts: [VaultAccount]
    ) -> GoogleAuthenticatorMatchSuggestion {
        let importedSecret = TOTPQRCodeParser.normalizeSecret(imported.secret)
        if let existing = accounts.first(where: {
            guard let secret = $0.totpSecret else { return false }
            return TOTPQRCodeParser.normalizeSecret(secret) == importedSecret
        }) {
            return GoogleAuthenticatorMatchSuggestion(
                accountID: existing.id,
                strength: .alreadyImported,
                reason: "المفتاح السري موجود مسبقًا في هذا الحساب."
            )
        }

        let importedIdentity = normalize(imported.name)
        let importedIssuer = normalize(imported.issuer)

        var best: (VaultAccount, Int, String)?
        for account in accounts {
            let email = normalize(account.email)
            let username = normalize(account.username)
            let service = normalize(account.serviceName)
            let site = normalize(account.siteURL)
            let totpIssuer = normalize(account.totpIssuer ?? "")

            let identityExact = !importedIdentity.isEmpty && (importedIdentity == email || importedIdentity == username)
            let issuerExact = !importedIssuer.isEmpty
                && (importedIssuer == service || importedIssuer == site || importedIssuer == totpIssuer
                    || site.contains(importedIssuer) || importedIssuer.contains(service))

            let score: Int
            let reason: String
            if identityExact && issuerExact {
                score = 100
                reason = "تطابق اسم الحساب والجهة."
            } else if identityExact {
                score = 75
                reason = "تطابق البريد أو اسم المستخدم."
            } else if issuerExact {
                score = 45
                reason = "تطابق محتمل في اسم الخدمة."
            } else {
                score = 0
                reason = ""
            }

            if score > (best?.1 ?? 0) {
                best = (account, score, reason)
            }
        }

        guard let best else {
            return GoogleAuthenticatorMatchSuggestion(accountID: nil, strength: .none, reason: nil)
        }

        return GoogleAuthenticatorMatchSuggestion(
            accountID: best.0.id,
            strength: best.1 >= 75 ? .strong : .possible,
            reason: best.2
        )
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private struct Base32Encoder {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func encode(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        var result = ""
        var buffer: UInt64 = 0
        var bitCount = 0

        for byte in data {
            buffer = (buffer << 8) | UInt64(byte)
            bitCount += 8
            while bitCount >= 5 {
                let shift = bitCount - 5
                let index = Int((buffer >> UInt64(shift)) & 0x1F)
                result.append(alphabet[index])
                bitCount -= 5
                if bitCount == 0 {
                    buffer = 0
                } else {
                    buffer &= (UInt64(1) << UInt64(bitCount)) - 1
                }
            }
        }

        if bitCount > 0 {
            let index = Int((buffer << UInt64(5 - bitCount)) & 0x1F)
            result.append(alphabet[index])
        }
        return result
    }
}

private struct ProtobufReader {
    let data: Data
    private(set) var index = 0

    var isAtEnd: Bool { index >= data.count }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        for _ in 0..<10 {
            guard index < data.count else {
                throw GoogleAuthenticatorMigrationError.malformedPayload
            }
            let byte = data[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
        }
        throw GoogleAuthenticatorMigrationError.malformedPayload
    }

    mutating func readLengthDelimited() throws -> Data {
        let length = try readVarint()
        guard length <= UInt64(Int.max) else {
            throw GoogleAuthenticatorMigrationError.malformedPayload
        }
        let intLength = Int(length)
        guard intLength >= 0, index + intLength <= data.count else {
            throw GoogleAuthenticatorMigrationError.malformedPayload
        }
        let result = data.subdata(in: index..<(index + intLength))
        index += intLength
        return result
    }

    mutating func readString() throws -> String {
        let value = try readLengthDelimited()
        guard let string = String(data: value, encoding: .utf8) else {
            throw GoogleAuthenticatorMigrationError.malformedPayload
        }
        return string
    }

    mutating func skipField(wireType: Int) throws {
        switch wireType {
        case 0:
            _ = try readVarint()
        case 1:
            try skip(bytes: 8)
        case 2:
            let length = try readVarint()
            guard length <= UInt64(Int.max) else {
                throw GoogleAuthenticatorMigrationError.malformedPayload
            }
            try skip(bytes: Int(length))
        case 5:
            try skip(bytes: 4)
        default:
            throw GoogleAuthenticatorMigrationError.malformedPayload
        }
    }

    private mutating func skip(bytes: Int) throws {
        guard bytes >= 0, index + bytes <= data.count else {
            throw GoogleAuthenticatorMigrationError.malformedPayload
        }
        index += bytes
    }
}
