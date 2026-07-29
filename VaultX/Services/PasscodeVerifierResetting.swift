import Foundation

protocol PasscodeVerifierResetting: Sendable {
    func deletePasscodeVerifierForVerifiedFreshInstall() async throws
}
