import Foundation
import Security

protocol VaultKeychainClient: Sendable {
    func readData(service: String, account: String) async throws -> Data?
    func addData(_ data: Data, service: String, account: String, accessibility: CFString) async throws -> VaultKeychainAddResult
    func deleteData(service: String, account: String) async throws
}

enum VaultKeychainAddResult: Sendable, Equatable {
    case success
    case duplicate
    case failure(OSStatus)
}
