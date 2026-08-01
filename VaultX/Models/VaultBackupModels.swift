import Foundation
import Combine

struct VaultBackupPayload: Codable, Equatable {
    static let currentVersion: UInt16 = 1

    let payloadVersion: UInt16
    let createdAt: Date
    let sourceAppVersion: String
    let accounts: [VaultAccount]

    init(
        payloadVersion: UInt16 = VaultBackupPayload.currentVersion,
        createdAt: Date = Date(),
        sourceAppVersion: String,
        accounts: [VaultAccount]
    ) {
        self.payloadVersion = payloadVersion
        self.createdAt = createdAt
        self.sourceAppVersion = sourceAppVersion
        self.accounts = accounts
    }
}

struct VaultBackupEnvelope: Codable, Equatable {
    static let magic = "VaultX.EncryptedBackup"
    static let currentFormatVersion: UInt16 = 1
    static let kdfIdentifier = "PBKDF2-HMAC-SHA256"

    let magic: String
    let formatVersion: UInt16
    let keyDerivation: String
    let iterationCount: UInt32
    let salt: Data
    let sealedPayload: Data
}

enum VaultBackupError: Error, Equatable, LocalizedError {
    case passwordTooShort
    case passwordTooLong
    case encodingFailed
    case invalidBackupFile
    case unsupportedFormatVersion(UInt16)
    case unsupportedPayloadVersion(UInt16)
    case unsupportedKeyDerivation
    case invalidKeyDerivationParameters
    case randomGenerationFailed
    case encryptionFailed
    case invalidPasswordOrCorruptedFile
    case fileTooLarge
    case fileReadFailed
    case noAccountsAvailable

    var errorDescription: String? {
        switch self {
        case .passwordTooShort:
            return "يجب أن تتكون كلمة مرور النسخة الاحتياطية من 10 أحرف على الأقل."
        case .passwordTooLong:
            return "كلمة مرور النسخة الاحتياطية طويلة جدًا."
        case .encodingFailed:
            return "تعذر تجهيز بيانات النسخة الاحتياطية بأمان."
        case .invalidBackupFile:
            return "الملف المحدد ليس نسخة VaultX احتياطية صالحة."
        case .unsupportedFormatVersion:
            return "إصدار ملف النسخة الاحتياطية غير مدعوم في هذه النسخة من VaultX."
        case .unsupportedPayloadVersion:
            return "محتوى النسخة الاحتياطية أُنشئ بإصدار غير مدعوم."
        case .unsupportedKeyDerivation:
            return "طريقة حماية كلمة المرور داخل الملف غير مدعومة."
        case .invalidKeyDerivationParameters:
            return "إعدادات حماية النسخة الاحتياطية غير صالحة."
        case .randomGenerationFailed:
            return "تعذر إنشاء القيم الأمنية العشوائية. حاول مرة أخرى."
        case .encryptionFailed:
            return "تعذر تشفير النسخة الاحتياطية."
        case .invalidPasswordOrCorruptedFile:
            return "كلمة المرور غير صحيحة أو أن ملف النسخة الاحتياطية تالف."
        case .fileTooLarge:
            return "حجم ملف النسخة الاحتياطية أكبر من الحد المسموح."
        case .fileReadFailed:
            return "تعذر قراءة ملف النسخة الاحتياطية."
        case .noAccountsAvailable:
            return "لا توجد حسابات لإنشاء نسخة احتياطية منها."
        }
    }
}

enum VaultBackupReviewStatus: Equatable {
    case new
    case identical(existingID: UUID)
    case conflict(existingID: UUID)
    case ambiguous(candidateIDs: [UUID])
}

enum VaultBackupDecision: Hashable {
    case skip
    case add
    case replace(existingID: UUID)
    case addSeparate
}

struct VaultBackupReviewItem: Identifiable, Equatable {
    let id: UUID
    let incomingAccount: VaultAccount
    let status: VaultBackupReviewStatus
    var decision: VaultBackupDecision

    init(
        id: UUID = UUID(),
        incomingAccount: VaultAccount,
        status: VaultBackupReviewStatus,
        decision: VaultBackupDecision
    ) {
        self.id = id
        self.incomingAccount = incomingAccount
        self.status = status
        self.decision = decision
    }
}

struct VaultBackupSummary: Equatable {
    let totalAccounts: Int
    let passwordAccounts: Int
    let twoFactorAccounts: Int
    let newAccounts: Int
    let identicalAccounts: Int
    let conflicts: Int
    let ambiguousAccounts: Int

    init(payload: VaultBackupPayload, reviewItems: [VaultBackupReviewItem]) {
        totalAccounts = payload.accounts.count
        passwordAccounts = payload.accounts.filter { !$0.password.isEmpty }.count
        twoFactorAccounts = payload.accounts.filter {
            $0.has2FA || !($0.totpSecret?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }.count
        newAccounts = reviewItems.filter {
            if case .new = $0.status { return true }
            return false
        }.count
        identicalAccounts = reviewItems.filter {
            if case .identical = $0.status { return true }
            return false
        }.count
        conflicts = reviewItems.filter {
            if case .conflict = $0.status { return true }
            return false
        }.count
        ambiguousAccounts = reviewItems.filter {
            if case .ambiguous = $0.status { return true }
            return false
        }.count
    }
}

@MainActor
final class VaultBackupRestoreSession: ObservableObject {
    @Published var encryptedFileData: Data?
    @Published var sourceFilename = ""
    @Published var payload: VaultBackupPayload?
    @Published var reviewItems: [VaultBackupReviewItem] = []
    @Published var isBusy = false
    @Published var resultMessage: String?

    var summary: VaultBackupSummary? {
        guard let payload else { return nil }
        return VaultBackupSummary(payload: payload, reviewItems: reviewItems)
    }

    func prepare(
        encryptedData: Data,
        filename: String
    ) {
        encryptedFileData = encryptedData
        sourceFilename = filename
        payload = nil
        reviewItems = []
        resultMessage = nil
    }

    func setDecryptedPayload(
        _ payload: VaultBackupPayload,
        currentAccounts: [VaultAccount]
    ) {
        self.payload = payload
        reviewItems = VaultBackupMergePlanner.makeReviewItems(
            importedAccounts: payload.accounts,
            currentAccounts: currentAccounts
        )
    }

    func reset() {
        encryptedFileData = nil
        sourceFilename = ""
        payload = nil
        reviewItems = []
        isBusy = false
    }
}
