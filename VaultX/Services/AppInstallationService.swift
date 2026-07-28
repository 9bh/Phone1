import Foundation

class AppInstallationService {
    private let installMarkerKey = "VaultX.InstallMarker"
    
    func isFreshInstall() -> Bool {
        // If the marker doesn't exist, it's a fresh install
        return !UserDefaults.standard.bool(forKey: installMarkerKey)
    }
    
    func markAsInstalled() {
        // Create the non-sensitive marker
        UserDefaults.standard.set(true, forKey: installMarkerKey)
    }
}
