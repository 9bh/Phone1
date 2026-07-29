import Foundation

protocol VaultFilesystemClient: Sendable {
    func fileExists(atPath path: String) async -> Bool
    func applicationSupportURL() async throws -> URL
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) async throws
    func readData(from url: URL) async throws -> Data
    func writeData(_ data: Data, to url: URL) async throws
    func moveItem(at sourceURL: URL, to destinationURL: URL) async throws
    func replaceItemAt(
        _ originalItemURL: URL,
        withItemAt newItemURL: URL,
        backupItemName: String?
    ) async throws -> URL?
    func removeItem(at url: URL) async throws
    func setResourceValues(_ values: URLResourceValues, for url: URL) async throws
    func resourceValues(
        forKeys keys: Set<URLResourceKey>,
        for url: URL
    ) async throws -> URLResourceValues
    func setAttributes(
        _ attributes: [FileAttributeKey: Any],
        ofItemAtPath path: String
    ) async throws
    func attributesOfItem(
        atPath path: String
    ) async throws -> [FileAttributeKey: Any]
}
