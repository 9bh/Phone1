import Foundation

struct VaultBackupMergePlanner {
    static func makeReviewItems(
        importedAccounts: [VaultAccount],
        currentAccounts: [VaultAccount]
    ) -> [VaultBackupReviewItem] {
        importedAccounts.map { incoming in
            let matches = candidateMatches(
                for: incoming,
                currentAccounts: currentAccounts
            )

            if matches.count > 1 {
                return VaultBackupReviewItem(
                    incomingAccount: incoming,
                    status: .ambiguous(candidateIDs: matches.map(\.id)),
                    decision: .skip
                )
            }

            guard let match = matches.first else {
                return VaultBackupReviewItem(
                    incomingAccount: incoming,
                    status: .new,
                    decision: .add
                )
            }

            if contentEquivalent(incoming, match) {
                return VaultBackupReviewItem(
                    incomingAccount: incoming,
                    status: .identical(existingID: match.id),
                    decision: .skip
                )
            }

            return VaultBackupReviewItem(
                incomingAccount: incoming,
                status: .conflict(existingID: match.id),
                decision: .skip
            )
        }
    }

    static func finalAccounts(
        currentAccounts: [VaultAccount],
        reviewItems: [VaultBackupReviewItem]
    ) -> [VaultAccount] {
        var final = currentAccounts
        var usedIDs = Set(final.map(\.id))

        for item in reviewItems {
            switch item.decision {
            case .skip:
                continue

            case .add:
                var incoming = item.incomingAccount
                if usedIDs.contains(incoming.id) {
                    incoming.id = UUID()
                }
                usedIDs.insert(incoming.id)
                final.append(incoming)

            case .replace(let existingID):
                guard let index = final.firstIndex(where: { $0.id == existingID }) else {
                    continue
                }
                var replacement = item.incomingAccount
                replacement.id = existingID
                final[index] = replacement

            case .addSeparate:
                var incoming = item.incomingAccount
                incoming.id = UUID()
                usedIDs.insert(incoming.id)
                final.append(incoming)
            }
        }

        return final
    }

    static func replacementAccounts(from importedAccounts: [VaultAccount]) -> [VaultAccount] {
        var usedIDs: Set<UUID> = []
        return importedAccounts.map { account in
            var normalized = account
            if usedIDs.contains(normalized.id) {
                normalized.id = UUID()
            }
            usedIDs.insert(normalized.id)
            return normalized
        }
    }

    private static func candidateMatches(
        for incoming: VaultAccount,
        currentAccounts: [VaultAccount]
    ) -> [VaultAccount] {
        if let idMatch = currentAccounts.first(where: { $0.id == incoming.id }) {
            return [idMatch]
        }

        let incomingSecret = normalizedSecret(incoming.totpSecret)
        if !incomingSecret.isEmpty {
            let secretMatches = currentAccounts.filter {
                normalizedSecret($0.totpSecret) == incomingSecret
                    && $0.totpAlgorithm == incoming.totpAlgorithm
                    && $0.totpDigits == incoming.totpDigits
                    && $0.totpPeriod == incoming.totpPeriod
            }
            if !secretMatches.isEmpty {
                return secretMatches
            }
        }

        let service = serviceIdentity(incoming)
        let identifier = accountIdentifier(incoming)
        guard !service.isEmpty, !identifier.isEmpty else {
            return []
        }

        return currentAccounts.filter {
            serviceIdentity($0) == service
                && accountIdentifier($0) == identifier
        }
    }

    private static func contentEquivalent(
        _ lhs: VaultAccount,
        _ rhs: VaultAccount
    ) -> Bool {
        lhs.siteURL == rhs.siteURL
            && lhs.email == rhs.email
            && lhs.password == rhs.password
            && lhs.username == rhs.username
            && lhs.notes == rhs.notes
            && lhs.has2FA == rhs.has2FA
            && lhs.hasBackupFile == rhs.hasBackupFile
            && normalizedSecret(lhs.totpSecret) == normalizedSecret(rhs.totpSecret)
            && normalizedText(lhs.totpIssuer) == normalizedText(rhs.totpIssuer)
            && lhs.totpAlgorithm == rhs.totpAlgorithm
            && lhs.totpDigits == rhs.totpDigits
            && lhs.totpPeriod == rhs.totpPeriod
    }

    private static func accountIdentifier(_ account: VaultAccount) -> String {
        let email = normalizedText(account.email)
        if !email.isEmpty { return email }
        return normalizedText(account.username)
    }

    private static func serviceIdentity(_ account: VaultAccount) -> String {
        let issuer = normalizedText(account.totpIssuer)
        if !issuer.isEmpty { return issuer }

        let rawURL = account.siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawURL.isEmpty {
            let candidate = rawURL.contains("://") ? rawURL : "https://\(rawURL)"
            if let host = URL(string: candidate)?.host {
                return normalizedText(host.replacingOccurrences(of: "www.", with: ""))
            }
        }

        return normalizedText(account.serviceName)
    }

    private static func normalizedSecret(_ value: String?) -> String {
        (value ?? "")
            .uppercased()
            .filter { !$0.isWhitespace && $0 != "-" }
    }

    private static func normalizedText(_ value: String?) -> String {
        (value ?? "")
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
