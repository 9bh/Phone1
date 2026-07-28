import Foundation

enum BiometricAuthResult {
    case success
    case cancelled
    case authenticationFailed
    case lockedOut
    case notEnrolled
    case notAvailable
}

protocol BiometricAuthenticating {
    func canEvaluateFaceID() -> Bool
    func authenticate(
        reason: String,
        completion: @escaping (BiometricAuthResult) -> Void
    )
}
