import UIKit
import UniformTypeIdentifiers

enum SecureClipboardService {
    @MainActor
    static func copy(_ text: String, expiresAfter delay: TimeInterval) {
        guard !text.isEmpty else { return }

        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: text]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(delay)
            ]
        )
    }
}
