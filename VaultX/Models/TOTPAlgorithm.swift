import Foundation

enum TOTPAlgorithm: String, Codable, CaseIterable {
    case sha1
    case sha256
    case sha512
}
