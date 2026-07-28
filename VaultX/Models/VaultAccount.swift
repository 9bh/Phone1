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
        return "123 456"
    }
}
