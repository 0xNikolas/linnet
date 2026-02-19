import Foundation

public actor FolderScanner {
    public static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "alac", "wav", "aiff", "aif",
        "ogg", "wma", "caf", "opus"
    ]

    public init() {}

    public func isAudioFile(_ url: URL) -> Bool {
        Self.audioExtensions.contains(url.pathExtension.lowercased())
    }

    public func scan(folder: URL) async throws -> [URL] {
        Self.collectAudioFiles(in: folder)
    }

    /// Synchronous file enumeration to avoid async-context restriction on DirectoryEnumerator
    public nonisolated static func collectAudioFiles(in folder: URL) -> [URL] {
        var audioFiles: [URL] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let fileURL as URL in enumerator {
            if audioExtensions.contains(fileURL.pathExtension.lowercased()) {
                audioFiles.append(fileURL)
            }
        }
        return audioFiles
    }
}
