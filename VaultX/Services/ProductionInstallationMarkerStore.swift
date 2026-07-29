import Foundation

actor ProductionInstallationMarkerStore: InstallationMarkerStoring {
    private let defaults: UserDefaults
    private let markerKey = "VaultX.InstallMarker"
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    func isInstallationMarked() async throws -> Bool {
        defaults.bool(forKey: markerKey)
    }
    
    func markInstallationCompleted() async throws {
        defaults.set(true, forKey: markerKey)
    }
}
