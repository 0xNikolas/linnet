import AVFoundation
import Accelerate

public struct LoudnessResult: Sendable, Codable {
    public let peakLevel: Float      // dB
    public let rmsLevel: Float       // dB
    public let gainAdjustment: Float // dB to apply for normalization

    public init(peakLevel: Float, rmsLevel: Float, targetLoudness: Float = -14.0) {
        self.peakLevel = peakLevel
        self.rmsLevel = rmsLevel
        // Calculate gain needed to bring RMS to target
        self.gainAdjustment = targetLoudness - rmsLevel
    }

    /// Linear gain multiplier to apply to audio
    public var linearGain: Float {
        powf(10.0, gainAdjustment / 20.0)
    }
}

public actor LoudnessAnalyzer {
    public static let targetLoudness: Float = -14.0 // dB, similar to Spotify/YouTube

    public init() {}

    /// Analyze the loudness of an audio file
    public func analyze(url: URL) async throws -> LoudnessResult {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: min(frameCount, 44100 * 30)) else {
            // Fallback: no normalization needed
            return LoudnessResult(peakLevel: 0, rmsLevel: Self.targetLoudness)
        }

        try file.read(into: buffer)

        guard let floatData = buffer.floatChannelData else {
            return LoudnessResult(peakLevel: 0, rmsLevel: Self.targetLoudness)
        }

        let channelCount = Int(format.channelCount)
        let sampleCount = Int(buffer.frameLength)

        guard sampleCount > 0 else {
            return LoudnessResult(peakLevel: 0, rmsLevel: Self.targetLoudness)
        }

        var totalRMS: Float = 0
        var totalPeak: Float = 0

        for ch in 0..<channelCount {
            let samples = floatData[ch]

            // Peak
            var peak: Float = 0
            vDSP_maxmgv(samples, 1, &peak, vDSP_Length(sampleCount))
            totalPeak = max(totalPeak, peak)

            // RMS
            var rms: Float = 0
            vDSP_rmsqv(samples, 1, &rms, vDSP_Length(sampleCount))
            totalRMS += rms
        }

        totalRMS /= Float(channelCount)

        // Convert to dB
        let peakDB = totalPeak > 0 ? 20 * log10(totalPeak) : -96.0
        let rmsDB = totalRMS > 0 ? 20 * log10(totalRMS) : -96.0

        return LoudnessResult(
            peakLevel: peakDB,
            rmsLevel: rmsDB,
            targetLoudness: Self.targetLoudness
        )
    }

    /// Analyze a batch of files
    public func analyzeBatch(urls: [URL], progress: (@Sendable (Int, Int) -> Void)? = nil) async -> [URL: LoudnessResult] {
        var results: [URL: LoudnessResult] = [:]

        for (index, url) in urls.enumerated() {
            if let result = try? await analyze(url: url) {
                results[url] = result
            }
            progress?(index + 1, urls.count)
        }

        return results
    }
}
