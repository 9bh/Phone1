import Foundation
import LocalAuthentication

class BiometricAuthenticationService: BiometricAuthenticating {
    
    func canEvaluateFaceID() -> Bool {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return context.biometryType == .faceID
        }
        return false
    }
    
    func authenticate(reason: String, completion: @escaping (BiometricAuthResult) -> Void) {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error), context.biometryType == .faceID {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authenticationError in
                DispatchQueue.main.async {
                    if success {
                        completion(.success)
                    } else if let laError = authenticationError as? LAError {
                        switch laError.code {
                        case .userCancel, .systemCancel, .appCancel:
                            completion(.cancelled)
                        case .biometryLockout:
                            completion(.lockedOut)
                        case .biometryNotEnrolled:
                            completion(.notEnrolled)
                        case .biometryNotAvailable:
                            completion(.notAvailable)
                        case .authenticationFailed:
                            completion(.authenticationFailed)
                        default:
                            completion(.notAvailable)
                        }
                    } else {
                        completion(.notAvailable)
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                if let laError = error as? LAError {
                    switch laError.code {
                    case .biometryNotEnrolled:
                        completion(.notEnrolled)
                    case .biometryLockout:
                        completion(.lockedOut)
                    default:
                        completion(.notAvailable)
                    }
                } else {
                    completion(.notAvailable)
                }
            }
        }
    }
}
