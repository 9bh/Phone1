import Foundation

actor ProductionVaultFilesystemClient: VaultFilesystemClient {
    private let fm = FileManager.default
    
    func fileExists(atPath path: String) async -> Bool {
        fm.fileExists(atPath: path)
    }
    
    func applicationSupportURL() async throws -> URL {
        guard let url = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw VaultPersistenceError.applicationSupportUnavailable
        }
        return url
    }
    
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) async throws {
        try fm.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
    }
    
    func readData(from url: URL) async throws -> Data {
        try Data(contentsOf: url)
    }
    
    func writeData(_ data: Data, to url: URL) async throws {
        try data.write(to: url, options: .atomic)
    }
    
    func moveItem(at sourceURL: URL, to destinationURL: URL) async throws {
        try fm.moveItem(at: sourceURL, to: destinationURL)
    }
    
    func replaceItemAt(_ originalItemURL: URL, withItemAt newItemURL: URL, backupItemName: String?) async throws -> URL? {
        try fm.replaceItemAt(originalItemURL, withItemAt: newItemURL, backupItemName: backupItemName, options: [])
    }
    
    func removeItem(at url: URL) async throws {
        try fm.removeItem(at: url)
    }
    
    func setResourceValues(_ values: URLResourceValues, for url: URL) async throws {
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
    
    func resourceValues(forKeys keys: Set<URLResourceKey>, for url: URL) async throws -> URLResourceValues {
        try url.resourceValues(forKeys: keys)
    }
    
    func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) async throws {
        try fm.setAttributes(attributes, ofItemAtPath: path)
    }
    
    func attributesOfItem(atPath path: String) async throws -> [FileAttributeKey: Any] {
        try fm.attributesOfItem(atPath: path)
    }
}
