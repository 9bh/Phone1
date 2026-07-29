import Foundation

protocol InstallationMarkerStoring: Sendable {
    func isInstallationMarked() async throws -> Bool
    func markInstallationCompleted() async throws
}
