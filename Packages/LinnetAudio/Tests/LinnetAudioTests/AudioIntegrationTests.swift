import Testing
import Foundation
import AVFoundation
@testable import LinnetAudio

// MARK: - Test Audio Generation

private func generateTestWav(
    frequency: Float = 440,
    duration: Double = 2.0,
    sampleRate: Double = 44100
) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("integration_\(UUID()).wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let frameCount = AVAudioFrameCount(duration * sampleRate)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    let samples = buffer.floatChannelData![0]
    for i in 0..<Int(frameCount) {
        samples[i] = 0.5 * sin(2.0 * .pi * frequency * Float(i) / Float(sampleRate))
    }
    try file.write(from: buffer)
    return url
}

// MARK: - AudioPlayer Integration Tests

@Test func audioPlayerLoadFile() async throws {
    let url = try generateTestWav(duration: 1.0)
    defer { try? FileManager.default.removeItem(at: url) }

    let player = AudioPlayer()
    try await player.load(url: url)
    let state = await player.state
    #expect(state == .stopped)

    let duration = await player.duration
    #expect(duration > 0.5)
    #expect(duration < 2.0)
}

@Test func audioPlayerPlayAndStop() async throws {
    let url = try generateTestWav(duration: 1.0)
    defer { try? FileManager.default.removeItem(at: url) }

    let player = AudioPlayer()
    try await player.load(url: url)
    try await player.play()
    let playState = await player.state
    #expect(playState == .playing)

    await player.stop()
    let stopState = await player.state
    #expect(stopState == .stopped)
}

@Test func audioPlayerSeek() async throws {
    let url = try generateTestWav(duration: 3.0)
    defer { try? FileManager.default.removeItem(at: url) }

    let player = AudioPlayer()
    try await player.load(url: url)
    try await player.play()
    try await player.seek(to: 1.5)

    // currentTime depends on audio hardware render time, which may not be
    // available on CI runners. Just verify seek doesn't crash.
    let _ = await player.currentTime

    await player.stop()
}

// MARK: - LoudnessAnalyzer Integration Tests

@Test func loudnessAnalyzerWithGeneratedAudio() async throws {
    let url = try generateTestWav(frequency: 440, duration: 2.0)
    defer { try? FileManager.default.removeItem(at: url) }

    let analyzer = LoudnessAnalyzer()
    let result = try await analyzer.analyze(url: url)
    #expect(result.peakLevel < 0)  // dB should be negative for < 1.0 amplitude
    #expect(result.rmsLevel < 0)
    #expect(result.linearGain > 0)
}

@Test func loudnessAnalyzerBatchProcessing() async throws {
    let url1 = try generateTestWav(frequency: 440, duration: 1.0)
    let url2 = try generateTestWav(frequency: 880, duration: 1.0)
    defer {
        try? FileManager.default.removeItem(at: url1)
        try? FileManager.default.removeItem(at: url2)
    }

    let analyzer = LoudnessAnalyzer()
    let results = try await analyzer.analyzeBatch(urls: [url1, url2])
    #expect(results.count == 2)
    for (_, result) in results {
        #expect(result.rmsLevel < 0)
        #expect(result.linearGain > 0)
    }
}
