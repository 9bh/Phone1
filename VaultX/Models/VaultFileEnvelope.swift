import Foundation

struct VaultFileEnvelope: Codable, Sendable, Equatable {
    let formatVersion: UInt16
    let sealedPayload: Data
}
