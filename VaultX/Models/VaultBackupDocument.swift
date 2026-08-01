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
