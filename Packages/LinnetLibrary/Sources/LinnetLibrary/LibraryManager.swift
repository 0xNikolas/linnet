import Foundation

public struct ScanResult: Sendable {
    public let filePath: String
    public let metadata: TrackMetadata

    public init(filePath: String, metadata: TrackMetadata) {
        self.filePath = filePath
        self.metadata = metadata
    }
}

public actor LibraryManager {
    private let scanner: FolderScanner
    private let extractor: MetadataExtractor

    public init() {
        self.scanner = FolderScanner()
        self.extractor = MetadataExtractor()
    }

    /// Scan a folder and extract metadata for all audio files.
    /// Returns results for the caller to persist via SwiftData on @MainActor.
    public func scanFolder(url: URL) async throws -> [ScanResult] {
        let audioFiles = try await scanner.scan(folder: url)
        var results: [ScanResult] = []

        for fileURL in audioFiles {
            let metadata = try await extractor.extract(from: fileURL)
            results.append(ScanResult(filePath: fileURL.path, metadata: metadata))
        }

        return results
    }
}
