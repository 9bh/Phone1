import Foundation

enum PasscodeVerificationResult: Equatable {
    case success
    case incorrect
    case invalidInput
    case storageUnavailable
}
