import AVFoundation
import Accelerate

/// Spectral features extracted from an audio file using Accelerate/vDSP.
public struct AudioFeatures: Sendable {
    /// 128-dimensional feature vector for similarity search
    public let embedding: [Float]
    /// Estimated tempo in beats per minute
    public let estimatedBPM: Double
    /// Spectral centroid (brightness indicator, Hz)
    public let spectralCentroid: Float
    /// RMS energy normalized to 0-1
    public let energy: Float
    /// Zero-crossing rate (noisiness indicator, 0-1)
    public let zeroCrossingRate: Float
}

/// Extracts audio features from files using Accelerate framework (no ML model needed).
public enum AudioFeatureExtractor {

    // MARK: - Public API

    /// Extract features from an audio file (analyzes first 30 seconds).
    public static func extract(from url: URL) throws -> AudioFeatures {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let maxFrames = AVAudioFrameCount(min(file.length, Int64(sampleRate * 30)))

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maxFrames) else {
            throw AIError.invalidInput("Could not create audio buffer")
        }
        try file.read(into: buffer)

        guard let floatData = buffer.floatChannelData else {
            throw AIError.invalidInput("No float channel data")
        }

        let samples = floatData[0]
        let count = Int(buffer.frameLength)
        guard count > 0 else {
            throw AIError.invalidInput("Empty audio file")
        }

        let rms = computeRMS(samples, count)
        let zcr = computeZeroCrossingRate(samples, count)
        let spectralStats = computeSpectralFeatures(samples, count, sampleRate: Float(sampleRate))
        let energyContour = computeEnergyContour(samples, count)
        let bpm = estimateBPM(samples, count, sampleRate: Float(sampleRate))

        // Build 128-dim embedding from feature statistics
        var embedding: [Float] = []
        embedding.append(contentsOf: spectralStats.centroidStats)   // 32 dims
        embedding.append(contentsOf: spectralStats.rolloffStats)    // 32 dims
        embedding.append(contentsOf: energyContour)                 // 32 dims
        embedding.append(contentsOf: zcrContourStats(samples, count)) // 16 dims
        embedding.append(contentsOf: onsetStats(samples, count, sampleRate: Float(sampleRate))) // 16 dims

        // Pad or truncate to exactly 128
        if embedding.count < 128 {
            embedding.append(contentsOf: [Float](repeating: 0, count: 128 - embedding.count))
        } else if embedding.count > 128 {
            embedding = Array(embedding.prefix(128))
        }

        return AudioFeatures(
            embedding: embedding,
            estimatedBPM: Double(bpm),
            spectralCentroid: spectralStats.meanCentroid,
            energy: min(rms * 3.0, 1.0),
            zeroCrossingRate: zcr
        )
    }

    // MARK: - RMS Energy

    private static func computeRMS(_ samples: UnsafePointer<Float>, _ count: Int) -> Float {
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(count))
        return rms
    }

    // MARK: - Zero Crossing Rate

    private static func computeZeroCrossingRate(_ samples: UnsafePointer<Float>, _ count: Int) -> Float {
        guard count > 1 else { return 0 }
        var crossings: Float = 0
        for i in 1..<count {
            if (samples[i] >= 0) != (samples[i - 1] >= 0) { crossings += 1 }
        }
        return crossings / Float(count)
    }

    // MARK: - Spectral Features (FFT-based)

    struct SpectralStats {
        let centroidStats: [Float]  // 32 values
        let rolloffStats: [Float]   // 32 values
        let meanCentroid: Float
    }

    private static func computeSpectralFeatures(
        _ samples: UnsafePointer<Float>, _ count: Int, sampleRate: Float
    ) -> SpectralStats {
        let frameSize = 2048
        let hopSize = 512
        let numFrames = max(1, (count - frameSize) / hopSize)

        // Set up FFT
        let log2n = vDSP_Length(log2(Float(frameSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return SpectralStats(
                centroidStats: [Float](repeating: 0, count: 32),
                rolloffStats: [Float](repeating: 0, count: 32),
                meanCentroid: 0
            )
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        let halfN = frameSize / 2
        var centroids: [Float] = []
        var rolloffs: [Float] = []

        // Window function (Hann)
        var window = [Float](repeating: 0, count: frameSize)
        vDSP_hann_window(&window, vDSP_Length(frameSize), Int32(vDSP_HANN_NORM))

        var realBuffer = [Float](repeating: 0, count: halfN)
        var imagBuffer = [Float](repeating: 0, count: halfN)

        for frame in 0..<numFrames {
            let offset = frame * hopSize
            guard offset + frameSize <= count else { break }

            // Apply window
            var windowed = [Float](repeating: 0, count: frameSize)
            vDSP_vmul(samples + offset, 1, window, 1, &windowed, 1, vDSP_Length(frameSize))

            // FFT using split complex via safe pointer scoping
            realBuffer.withUnsafeMutableBufferPointer { realBuf in
                imagBuffer.withUnsafeMutableBufferPointer { imagBuf in
                    var splitComplex = DSPSplitComplex(
                        realp: realBuf.baseAddress!,
                        imagp: imagBuf.baseAddress!
                    )

                    windowed.withUnsafeMutableBufferPointer { ptr in
                        ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                            vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                        }
                    }

                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

                    // Compute magnitudes
                    var magnitudes = [Float](repeating: 0, count: halfN)
                    vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfN))

                    // Spectral centroid: sum(f[i] * mag[i]) / sum(mag[i])
                    var totalMag: Float = 0
                    var weightedSum: Float = 0
                    for i in 0..<halfN {
                        let freq = Float(i) * sampleRate / Float(frameSize)
                        totalMag += magnitudes[i]
                        weightedSum += freq * magnitudes[i]
                    }
                    let centroid = totalMag > 0 ? weightedSum / totalMag : 0
                    centroids.append(centroid)

                    // Spectral rolloff (85% energy threshold)
                    let threshold = totalMag * 0.85
                    var cumSum: Float = 0
                    var rolloffFreq: Float = 0
                    for i in 0..<halfN {
                        cumSum += magnitudes[i]
                        if cumSum >= threshold {
                            rolloffFreq = Float(i) * sampleRate / Float(frameSize)
                            break
                        }
                    }
                    rolloffs.append(rolloffFreq)
                }
            }
        }

        return SpectralStats(
            centroidStats: computeStatistics(centroids, targetCount: 32),
            rolloffStats: computeStatistics(rolloffs, targetCount: 32),
            meanCentroid: centroids.isEmpty ? 0 : centroids.reduce(0, +) / Float(centroids.count)
        )
    }

    // MARK: - Energy Contour

    private static func computeEnergyContour(_ samples: UnsafePointer<Float>, _ count: Int) -> [Float] {
        let hopSize = 512
        let frameSize = 1024
        let numFrames = max(1, (count - frameSize) / hopSize)
        var energies: [Float] = []

        for frame in 0..<numFrames {
            let offset = frame * hopSize
            guard offset + frameSize <= count else { break }
            var rms: Float = 0
            vDSP_rmsqv(samples + offset, 1, &rms, vDSP_Length(frameSize))
            energies.append(rms)
        }

        return computeStatistics(energies, targetCount: 32)
    }

    // MARK: - ZCR Contour

    private static func zcrContourStats(_ samples: UnsafePointer<Float>, _ count: Int) -> [Float] {
        let hopSize = 512
        let frameSize = 1024
        let numFrames = max(1, (count - frameSize) / hopSize)
        var zcrs: [Float] = []

        for frame in 0..<numFrames {
            let offset = frame * hopSize
            guard offset + frameSize <= count else { break }
            var crossings: Float = 0
            for i in 1..<frameSize {
                let idx = offset + i
                guard idx < count else { break }
                if (samples[idx] >= 0) != (samples[idx - 1] >= 0) { crossings += 1 }
            }
            zcrs.append(crossings / Float(frameSize))
        }

        return computeStatistics(zcrs, targetCount: 16)
    }

    // MARK: - Onset Detection Stats

    private static func onsetStats(_ samples: UnsafePointer<Float>, _ count: Int, sampleRate: Float) -> [Float] {
        let hopSize = 512
        let frameSize = 1024
        let numFrames = max(1, (count - frameSize) / hopSize)
        var energies: [Float] = []

        for frame in 0..<numFrames {
            let offset = frame * hopSize
            guard offset + frameSize <= count else { break }
            var rms: Float = 0
            vDSP_rmsqv(samples + offset, 1, &rms, vDSP_Length(frameSize))
            energies.append(rms)
        }

        // Onset detection: first-order difference of energy
        var onsets: [Float] = []
        for i in 1..<energies.count {
            let diff = max(0, energies[i] - energies[i - 1])
            onsets.append(diff)
        }

        return computeStatistics(onsets, targetCount: 16)
    }

    // MARK: - BPM Estimation

    private static func estimateBPM(_ samples: UnsafePointer<Float>, _ count: Int, sampleRate: Float) -> Float {
        // Onset detection function (energy envelope)
        let hopSize = 512
        let frameSize = 1024
        let numFrames = max(1, (count - frameSize) / hopSize)

        var envelope: [Float] = []
        for frame in 0..<numFrames {
            let offset = frame * hopSize
            guard offset + frameSize <= count else { break }
            var rms: Float = 0
            vDSP_rmsqv(samples + offset, 1, &rms, vDSP_Length(frameSize))
            envelope.append(rms)
        }

        guard envelope.count > 2 else { return 120 }

        // First-order difference (onset function)
        var onsetFunc = [Float](repeating: 0, count: envelope.count - 1)
        for i in 0..<onsetFunc.count {
            onsetFunc[i] = max(0, envelope[i + 1] - envelope[i])
        }

        // Autocorrelation of onset function
        let envelopeRate = sampleRate / Float(hopSize)
        let minBPM: Float = 60
        let maxBPM: Float = 200
        let minLag = Int(envelopeRate * 60.0 / maxBPM)
        let maxLag = min(onsetFunc.count / 2, Int(envelopeRate * 60.0 / minBPM))

        guard minLag < maxLag else { return 120 }

        var bestLag = minLag
        var bestCorr: Float = -Float.infinity

        onsetFunc.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            for lag in minLag..<maxLag {
                var corr: Float = 0
                let length = vDSP_Length(onsetFunc.count - lag)
                vDSP_dotpr(base, 1, base + lag, 1, &corr, length)
                if corr > bestCorr {
                    bestCorr = corr
                    bestLag = lag
                }
            }
        }

        let bpm = envelopeRate * 60.0 / Float(bestLag)
        return bpm
    }

    // MARK: - Statistics Helper

    /// Compute summary statistics (mean, std, min, max, percentiles) from a time series.
    private static func computeStatistics(_ values: [Float], targetCount: Int) -> [Float] {
        guard !values.isEmpty else {
            return [Float](repeating: 0, count: targetCount)
        }

        let sorted = values.sorted()
        let n = Float(values.count)

        // Mean
        var mean: Float = 0
        vDSP_meanv(values, 1, &mean, vDSP_Length(values.count))

        // Variance / Std
        var variance: Float = 0
        let centered = values.map { $0 - mean }
        vDSP_dotpr(centered, 1, centered, 1, &variance, vDSP_Length(centered.count))
        variance /= n
        let std = sqrtf(variance)

        let minVal = sorted.first!
        let maxVal = sorted.last!

        // Percentiles
        func percentile(_ p: Float) -> Float {
            let idx = p * Float(sorted.count - 1)
            let lower = Int(idx)
            let upper = min(lower + 1, sorted.count - 1)
            let frac = idx - Float(lower)
            return sorted[lower] * (1 - frac) + sorted[upper] * frac
        }

        var stats: [Float] = [
            mean, std, minVal, maxVal,
            percentile(0.1), percentile(0.25), percentile(0.5), percentile(0.75), percentile(0.9),
        ]

        // Add sub-sampled time series to fill target count
        let remaining = targetCount - stats.count
        if remaining > 0 {
            let step = max(1, values.count / remaining)
            for i in 0..<remaining {
                let idx = min(i * step, values.count - 1)
                stats.append(values[idx])
            }
        }

        return Array(stats.prefix(targetCount))
    }
}
