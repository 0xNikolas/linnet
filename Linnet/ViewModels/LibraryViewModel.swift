import SwiftUI
@preconcurrency import SwiftData
import Observation
import LinnetLibrary

@MainActor
@Observable
public final class LibraryViewModel {
    var searchText: String = ""
    var isScanning: Bool = false
    var scanProgress: String = ""
    var lastScanCount: Int = 0

    private let libraryManager = LibraryManager()
    private var fileWatcher = FileWatcher()

    func addFolder(url: URL, context: ModelContext) {
        let folder = WatchedFolder(path: url.path())
        context.insert(folder)
        try? context.save()

        scanFolder(url: url, context: context)

        fileWatcher.watch(folder: url.path()) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scanFolder(url: url, context: context)
            }
        }
    }

    func scanFolder(url: URL, context: ModelContext) {
        isScanning = true
        scanProgress = "Scanning \(url.lastPathComponent)..."

        Task {
            do {
                let results = try await libraryManager.scanFolder(url: url)
                let count = importResults(results, context: context)
                lastScanCount = count
                scanProgress = "Imported \(count) tracks"
            } catch {
                scanProgress = "Error: \(error.localizedDescription)"
            }
            isScanning = false
        }
    }

    func rescanAll(context: ModelContext) {
        let descriptor = FetchDescriptor<WatchedFolder>(predicate: #Predicate { $0.isEnabled })
        guard let folders = try? context.fetch(descriptor) else { return }

        isScanning = true
        var totalImported = 0

        Task {
            for folder in folders {
                scanProgress = "Scanning \(URL(filePath: folder.path).lastPathComponent)..."
                do {
                    let results = try await libraryManager.scanFolder(url: URL(filePath: folder.path))
                    let count = importResults(results, context: context)
                    totalImported += count
                    folder.lastScanned = Date()
                } catch {
                    scanProgress = "Error scanning \(folder.path): \(error.localizedDescription)"
                }
            }
            try? context.save()
            lastScanCount = totalImported
            scanProgress = "Imported \(totalImported) tracks total"
            isScanning = false
        }
    }

    func startWatching(folders: [WatchedFolder], context: ModelContext) {
        stopWatching()
        for folder in folders where folder.isEnabled {
            let url = URL(filePath: folder.path)
            fileWatcher.watch(folder: folder.path) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scanFolder(url: url, context: context)
                }
            }
        }
    }

    func stopWatching() {
        fileWatcher.stopAll()
    }

    /// Import scan results into SwiftData. Must be called on @MainActor.
    private func importResults(_ results: [ScanResult], context: ModelContext) -> Int {
        var importedCount = 0

        for result in results {
            // Skip if already imported
            let path = result.filePath
            var descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.filePath == path })
            descriptor.fetchLimit = 1
            let existing = (try? context.fetch(descriptor)) ?? []
            if !existing.isEmpty { continue }

            let metadata = result.metadata

            // Find or create artist
            var artist: Artist?
            if let artistName = metadata.artist {
                var artistDescriptor = FetchDescriptor<Artist>(predicate: #Predicate { $0.name == artistName })
                artistDescriptor.fetchLimit = 1
                if let found = try? context.fetch(artistDescriptor).first {
                    artist = found
                } else {
                    artist = Artist(name: artistName)
                    context.insert(artist!)
                }
            }

            // Find or create album
            var album: Album?
            if let albumName = metadata.album {
                let artistName = metadata.artist
                var albumDescriptor = FetchDescriptor<Album>(predicate: #Predicate {
                    $0.name == albumName && $0.artistName == artistName
                })
                albumDescriptor.fetchLimit = 1
                if let found = try? context.fetch(albumDescriptor).first {
                    album = found
                } else {
                    album = Album(name: albumName, year: metadata.year, artistName: metadata.artist)
                    album!.artist = artist
                    if let artData = metadata.artwork {
                        album!.artworkData = artData
                    }
                    context.insert(album!)
                }
            }

            // Create track
            let track = Track(
                filePath: path,
                title: metadata.title ?? URL(filePath: path).deletingPathExtension().lastPathComponent,
                duration: metadata.duration,
                trackNumber: metadata.trackNumber ?? 0,
                discNumber: metadata.discNumber ?? 1,
                genre: metadata.genre,
                year: metadata.year
            )
            track.artist = artist
            track.album = album
            track.artworkData = metadata.artwork
            context.insert(track)
            importedCount += 1
        }

        try? context.save()
        return importedCount
    }
}
