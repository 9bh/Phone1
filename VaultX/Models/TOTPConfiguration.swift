import Foundation

struct TOTPConfiguration: Equatable {
    let secret: Data
    let algorithm: TOTPAlgorithm
    let digits: Int
    let period: Int
}

struct TOTPCode: Equatable {
    let value: String
    let validFrom: Date
    let validUntil: Date
    let remainingSeconds: Int
}
