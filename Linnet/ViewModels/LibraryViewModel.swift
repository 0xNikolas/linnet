import SwiftUI
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

    func addFolder(url: URL, db: AppDatabase) {
        let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        var folder = WatchedFolderRecord(path: url.path, bookmarkData: bookmark)
        try? db.watchedFolders.insert(&folder)

        scanFolder(url: url, db: db)

        fileWatcher.watch(folder: url.path) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scanFolder(url: url, db: db)
            }
        }
    }

    func scanFolder(url: URL, db: AppDatabase) {
        isScanning = true
        scanProgress = "Scanning \(url.lastPathComponent)..."

        Task {
            do {
                let results = try await libraryManager.scanFolder(url: url)
                let count = try await libraryManager.importResults(results, into: db.pool)
                lastScanCount = count
                scanProgress = "Imported \(count) tracks"
            } catch {
                scanProgress = "Error: \(error.localizedDescription)"
            }
            isScanning = false
        }
    }

    func rescanAll(db: AppDatabase) {
        guard let folders = try? db.watchedFolders.fetchEnabled() else { return }

        isScanning = true
        var totalImported = 0

        Task {
            for folder in folders {
                let folderURL = resolveFolder(folder, db: db)
                scanProgress = "Scanning \(folderURL.lastPathComponent)..."
                do {
                    let results = try await libraryManager.scanFolder(url: folderURL)
                    let count = try await libraryManager.importResults(results, into: db.pool)
                    totalImported += count
                    try? db.watchedFolders.updateLastScanned(id: folder.id!)
                } catch {
                    scanProgress = "Error scanning \(folder.path): \(error.localizedDescription)"
                }
                folderURL.stopAccessingSecurityScopedResource()
            }
            lastScanCount = totalImported
            scanProgress = "Imported \(totalImported) tracks total"
            isScanning = false
        }
    }

    private func resolveFolder(_ folder: WatchedFolderRecord, db: AppDatabase) -> URL {
        if let bookmarkData = folder.bookmarkData {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                _ = url.startAccessingSecurityScopedResource()
                if isStale {
                    if let newBookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                        var updated = folder
                        updated.bookmarkData = newBookmark
                        try? db.watchedFolders.update(updated)
                    }
                }
                return url
            }
        }
        return URL(filePath: folder.path)
    }

    func startWatching(db: AppDatabase) {
        stopWatching()
        guard let folders = try? db.watchedFolders.fetchEnabled() else { return }
        for folder in folders {
            let url = URL(filePath: folder.path)
            fileWatcher.watch(folder: folder.path) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scanFolder(url: url, db: db)
                }
            }
        }
    }

    func stopWatching() {
        fileWatcher.stopAll()
    }
}
