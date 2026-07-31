import Foundation

struct GoogleAuthenticatorImportedAccount: Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let issuer: String
    let secret: String
    let algorithm: TOTPAlgorithm
    let digits: Int
    let period: Int

    init(
        id: UUID = UUID(),
        name: String,
        issuer: String,
        secret: String,
        algorithm: TOTPAlgorithm,
        digits: Int,
        period: Int = 30
    ) {
        self.id = id
        self.name = name
        self.issuer = issuer
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
    }

    var displayIssuer: String {
        issuer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "حساب مصادقة" : issuer
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "حساب بدون اسم" : trimmed
    }

    var maskedSecret: String {
        guard secret.count > 4 else { return String(repeating: "•", count: secret.count) }
        return String(repeating: "•", count: max(8, secret.count - 4)) + secret.suffix(4)
    }
}

struct GoogleAuthenticatorMigrationBatch: Equatable {
    let accounts: [GoogleAuthenticatorImportedAccount]
    let version: Int
    let batchSize: Int
    let batchIndex: Int
    let batchID: Int
}

enum GoogleAuthenticatorImportDecision: Equatable {
    case unresolved
    case createNew
    case skip
    case link(UUID)
    case replace(UUID)
}

struct GoogleAuthenticatorImportRow: Identifiable, Equatable {
    let account: GoogleAuthenticatorImportedAccount
    var decision: GoogleAuthenticatorImportDecision
    var suggestedAccountID: UUID?
    var suggestionReason: String?

    var id: UUID { account.id }
}

enum GoogleAuthenticatorMatchStrength: Equatable {
    case none
    case possible
    case strong
    case alreadyImported
}

struct GoogleAuthenticatorMatchSuggestion: Equatable {
    let accountID: UUID?
    let strength: GoogleAuthenticatorMatchStrength
    let reason: String?
}
