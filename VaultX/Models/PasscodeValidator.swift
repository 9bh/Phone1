import Foundation

struct PasscodeValidator {
    static func isValidPasscode(_ value: String) -> Bool {
        guard value.count == 6 else { return false }
        
        // Ensure every character is an ASCII digit (0-9)
        for char in value {
            guard char.isASCII, char.isWholeNumber else {
                return false
            }
        }
        
        return true
    }
}
