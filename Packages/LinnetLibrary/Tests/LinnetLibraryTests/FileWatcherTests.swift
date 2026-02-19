import Testing
import Foundation
@testable import LinnetLibrary

@Test func fileWatcherInitializes() {
    let watcher = FileWatcher()
    // Just verify it can be created without crashing
    watcher.stopAll()
}

@Test func fileWatcherCanWatchAndStop() async throws {
    let watcher = FileWatcher()
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    watcher.watch(folder: tempDir.path()) { _ in
        // Handler registered
    }

    // Give it a moment
    try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

    watcher.stopAll()

    // Cleanup
    try? FileManager.default.removeItem(at: tempDir)
}
