import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let vaultXBackup = UTType(
        exportedAs: "com.smartsphere.vaultx.backup",
        conformingTo: .data
    )
}

struct VaultBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.vaultXBackup] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw VaultBackupError.invalidBackupFile
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum VaultBackupFileAccess {
    static func isSupportedBackupURL(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("vaultx") == .orderedSame
    }

    static func readBackupData(from url: URL) async throws -> Data {
        guard isSupportedBackupURL(url) else {
            throw VaultBackupError.invalidBackupFile
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try await Task.detached(priority: .userInitiated) {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile != false else {
                throw VaultBackupError.fileReadFailed
            }
            if let size = values.fileSize,
               size > VaultBackupCryptoService.maximumFileSize {
                throw VaultBackupError.fileTooLarge
            }

            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= VaultBackupCryptoService.maximumFileSize else {
                throw VaultBackupError.fileTooLarge
            }
            return data
        }.value
    }
}
