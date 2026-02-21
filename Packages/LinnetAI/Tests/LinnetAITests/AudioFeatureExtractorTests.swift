import Testing
import Foundation
import AVFoundation
@testable import LinnetAI

// MARK: - Test Audio Generation

private func generateTestAudio(
    frequency: Float = 440,
    duration: Double = 2.0,
    sampleRate: Double = 44100
) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("test_\(UUID()).wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let frameCount = AVAudioFrameCount(duration * sampleRate)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    let samples = buffer.floatChannelData![0]
    for i in 0..<Int(frameCount) {
        samples[i] = sin(2.0 * .pi * frequency * Float(i) / Float(sampleRate))
    }
    try file.write(from: buffer)
    return url
}

private func generateWhiteNoise(duration: Double = 2.0, sampleRate: Double = 44100) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("noise_\(UUID()).wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let frameCount = AVAudioFrameCount(duration * sampleRate)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    let samples = buffer.floatChannelData![0]
    for i in 0..<Int(frameCount) {
        samples[i] = Float.random(in: -1...1)
    }
    try file.write(from: buffer)
    return url
}

private func generateBeatPattern(
    bpm: Double = 120,
    duration: Double = 5.0,
    sampleRate: Double = 44100
) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("beat_\(UUID()).wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let frameCount = AVAudioFrameCount(duration * sampleRate)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    let samples = buffer.floatChannelData![0]

    let beatInterval = 60.0 / bpm
    let clickDuration = 0.01 // 10ms click
    let clickSamples = Int(clickDuration * sampleRate)

    for i in 0..<Int(frameCount) {
        let time = Double(i) / sampleRate
        let timeSinceBeat = time.truncatingRemainder(dividingBy: beatInterval)
        if timeSinceBeat < clickDuration {
            // Short click: 1kHz sine burst
            samples[i] = 0.8 * sin(2.0 * .pi * 1000 * Float(i) / Float(sampleRate))
        } else {
            samples[i] = 0
        }
    }
    try file.write(from: buffer)
    return url
}

// MARK: - Tests

@Test func extractionProduces128DimEmbedding() throws {
    let url = try generateTestAudio(frequency: 440, duration: 2.0)
    defer { try? FileManager.default.removeItem(at: url) }

    let features = try AudioFeatureExtractor.extract(from: url)
    #expect(features.embedding.count == 128)
}

@Test func sineWaveHasReasonableSpectralCentroid() throws {
    let url = try generateTestAudio(frequency: 440, duration: 3.0)
    defer { try? FileManager.default.removeItem(at: url) }

    let features = try AudioFeatureExtractor.extract(from: url)
    // Spectral centroid of a pure 440Hz tone should be near 440Hz
    // Allow wide tolerance due to windowing and FFT bin resolution
    #expect(features.spectralCentroid > 200)
    #expect(features.spectralCentroid < 800)
}

@Test func whiteNoiseHasHighZeroCrossingRate() throws {
    let url = try generateWhiteNoise(duration: 2.0)
    defer { try? FileManager.default.removeItem(at: url) }

    let features = try AudioFeatureExtractor.extract(from: url)
    // White noise should have high ZCR (typically > 0.3)
    #expect(features.zeroCrossingRate > 0.2)
}

@Test func sineWaveHasLowZeroCrossingRate() throws {
    // Low-frequency sine has fewer zero crossings
    let url = try generateTestAudio(frequency: 100, duration: 2.0)
    defer { try? FileManager.default.removeItem(at: url) }

    let features = try AudioFeatureExtractor.extract(from: url)
    // 100Hz sine at 44100Hz: ~200 crossings per 44100 samples = ~0.0045
    #expect(features.zeroCrossingRate < 0.05)
}

@Test func sineWaveHasNonZeroEnergy() throws {
    let url = try generateTestAudio(frequency: 440, duration: 2.0)
    defer { try? FileManager.default.removeItem(at: url) }

    let features = try AudioFeatureExtractor.extract(from: url)
    #expect(features.energy > 0)
    #expect(features.energy <= 1.0)
}

@Test func beatPatternHasReasonableBPM() throws {
    let targetBPM: Double = 120
    let url = try generateBeatPattern(bpm: targetBPM, duration: 8.0)
    defer { try? FileManager.default.removeItem(at: url) }

    let features = try AudioFeatureExtractor.extract(from: url)
    // BPM estimation is approximate; allow wide tolerance
    #expect(features.estimatedBPM > 60)
    #expect(features.estimatedBPM < 200)
}

@Test func differentFrequenciesProduceDifferentEmbeddings() throws {
    let url1 = try generateTestAudio(frequency: 220, duration: 2.0)
    let url2 = try generateTestAudio(frequency: 4000, duration: 2.0)
    defer {
        try? FileManager.default.removeItem(at: url1)
        try? FileManager.default.removeItem(at: url2)
    }

    let features1 = try AudioFeatureExtractor.extract(from: url1)
    let features2 = try AudioFeatureExtractor.extract(from: url2)

    // Embeddings should differ for very different frequencies
    let similarity = VectorUtils.cosineSimilarity(features1.embedding, features2.embedding)
    #expect(similarity < 1.0, "Different frequencies should produce distinct embeddings")
}
