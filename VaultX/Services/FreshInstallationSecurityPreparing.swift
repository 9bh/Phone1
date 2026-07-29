import Foundation

protocol FreshInstallationSecurityPreparing: Sendable {
    func prepareVerifiedFreshInstallation() async throws
}
