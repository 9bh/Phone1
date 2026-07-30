import Foundation

struct VaultAccount: Identifiable, Codable, Hashable {
    var id = UUID()
    var siteURL: String
    var email: String
    var password: String
    var username: String
    var notes: String
    var has2FA: Bool = false
    var hasBackupFile: Bool = false
    
    // TOTP Fields
    var totpSecret: String?
    var totpIssuer: String?
    var totpAlgorithm: TOTPAlgorithm = .sha1
    var totpDigits: Int = 6
    var totpPeriod: Int = 30
    
    var serviceName: String {
        let source = !siteURL.isEmpty ? siteURL : email
        if source.isEmpty {
            return "New Account"
        }
        
        let lower = source.lowercased()
        if lower.contains("google") { return "Google" }
        if lower.contains("microsoft") { return "Microsoft" }
        if lower.contains("github") { return "GitHub" }
        if lower.contains("facebook") { return "Facebook" }
        if lower.contains("instagram") { return "Instagram" }
        if lower.contains("apple") { return "Apple" }
        if lower.contains("amazon") { return "Amazon" }
        if lower.contains("x.com") || lower.contains("twitter") { return "X" }
        
        if let atIndex = lower.firstIndex(of: "@") {
            let domain = lower[lower.index(after: atIndex)...]
            let name = domain.split(separator: ".").first ?? "Account"
            return name.capitalized
        }
        
        let name = lower.replacingOccurrences(of: "https://", with: "")
                        .replacingOccurrences(of: "http://", with: "")
                        .replacingOccurrences(of: "www.", with: "")
                        .split(separator: ".")
                        .first ?? "Account"
        return name.capitalized
    }
    
    var iconName: String {
        let name = serviceName.lowercased()
        switch name {
        case "google": return "g.circle.fill"
        case "apple": return "applelogo"
        case "microsoft": return "window.casement.closed"
        case "github": return "curlybraces"
        case "amazon": return "cart.fill"
        case "facebook": return "f.circle.fill"
        case "instagram": return "camera.fill"
        case "x": return "xmark"
        default: return "globe"
        }
    }
    
    var displayCode: String {
        return "123 456" // Fallback or placeholder if needed elsewhere
    }
    
    // Custom decoding to support backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        siteURL = try container.decodeIfPresent(String.self, forKey: .siteURL) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        has2FA = try container.decodeIfPresent(Bool.self, forKey: .has2FA) ?? false
        hasBackupFile = try container.decodeIfPresent(Bool.self, forKey: .hasBackupFile) ?? false
        
        totpSecret = try container.decodeIfPresent(String.self, forKey: .totpSecret)
        totpIssuer = try container.decodeIfPresent(String.self, forKey: .totpIssuer)
        totpAlgorithm = try container.decodeIfPresent(TOTPAlgorithm.self, forKey: .totpAlgorithm) ?? .sha1
        totpDigits = try container.decodeIfPresent(Int.self, forKey: .totpDigits) ?? 6
        totpPeriod = try container.decodeIfPresent(Int.self, forKey: .totpPeriod) ?? 30
    }
    
    // Default initializer for new instances
    init(id: UUID = UUID(), siteURL: String = "", email: String = "", password: String = "", username: String = "", notes: String = "", has2FA: Bool = false, hasBackupFile: Bool = false, totpSecret: String? = nil, totpIssuer: String? = nil, totpAlgorithm: TOTPAlgorithm = .sha1, totpDigits: Int = 6, totpPeriod: Int = 30) {
        self.id = id
        self.siteURL = siteURL
        self.email = email
        self.password = password
        self.username = username
        self.notes = notes
        self.has2FA = has2FA
        self.hasBackupFile = hasBackupFile
        self.totpSecret = totpSecret
        self.totpIssuer = totpIssuer
        self.totpAlgorithm = totpAlgorithm
        self.totpDigits = totpDigits
        self.totpPeriod = totpPeriod
    }
}
