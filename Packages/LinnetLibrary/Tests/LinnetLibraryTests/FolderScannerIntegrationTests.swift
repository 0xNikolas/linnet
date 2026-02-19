import Testing
import Foundation
import AVFoundation
@testable import LinnetLibrary

// MARK: - Test Helpers

private func createTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("scanner_test_\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func createTestWav(in directory: URL, name: String, duration: Double = 0.5) throws {
    let url = directory.appendingPathComponent(name)
    let sampleRate: Double = 44100
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let frameCount = AVAudioFrameCount(duration * sampleRate)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    let samples = buffer.floatChannelData![0]
    for i in 0..<Int(frameCount) {
        samples[i] = sin(2.0 * .pi * 440.0 * Float(i) / Float(sampleRate))
    }
    try file.write(from: buffer)
}

private func createDummyFile(in directory: URL, name: String) throws {
    let url = directory.appendingPathComponent(name)
    try "dummy content".write(to: url, atomically: true, encoding: .utf8)
}

// MARK: - Tests

@Test func scannerFindsOnlyAudioFiles() async throws {
    let dir = try createTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }

    try createTestWav(in: dir, name: "song.wav")
    try createDummyFile(in: dir, name: "readme.txt")
    try createDummyFile(in: dir, name: "cover.jpg")

    let scanner = FolderScanner()
    let results = try await scanner.scan(folder: dir)

    #expect(results.count == 1)
    #expect(results[0].lastPathComponent == "song.wav")
}

@Test func scannerFindsMultipleFormats() async throws {
    let dir = try createTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }

    try createTestWav(in: dir, name: "track.wav")
    // Create files with audio extensions (contents don't matter for scan)
    try createDummyFile(in: dir, name: "track.mp3")
    try createDummyFile(in: dir, name: "track.flac")
    try createDummyFile(in: dir, name: "track.m4a")
    try createDummyFile(in: dir, name: "notes.txt")

    let scanner = FolderScanner()
    let results = try await scanner.scan(folder: dir)

    #expect(results.count == 4)
}

@Test func scannerRecursesSubdirectories() async throws {
    let dir = try createTempDirectory()
    let subdir = dir.appendingPathComponent("subfolder")
    try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    try createTestWav(in: dir, name: "top.wav")
    try createTestWav(in: subdir, name: "nested.wav")

    let scanner = FolderScanner()
    let results = try await scanner.scan(folder: dir)

    #expect(results.count == 2)
}

@Test func scannerSkipsHiddenFiles() async throws {
    let dir = try createTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }

    try createTestWav(in: dir, name: "visible.wav")
    try createDummyFile(in: dir, name: ".hidden.wav")

    let scanner = FolderScanner()
    let results = try await scanner.scan(folder: dir)

    #expect(results.count == 1)
    #expect(results[0].lastPathComponent == "visible.wav")
}

@Test func scannerHandlesEmptyDirectory() async throws {
    let dir = try createTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }

    let scanner = FolderScanner()
    let results = try await scanner.scan(folder: dir)

    #expect(results.isEmpty)
}
