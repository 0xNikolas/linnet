import Testing
import Foundation
@testable import LinnetAudio

@Test func loudnessResultLinearGain() {
    // If RMS is -20dB and target is -14dB, gain should be +6dB
    let result = LoudnessResult(peakLevel: -3, rmsLevel: -20, targetLoudness: -14)
    #expect(result.gainAdjustment == 6.0)
    // 10^(6/20) ~ 1.995
    #expect(abs(result.linearGain - 1.995) < 0.01)
}

@Test func loudnessResultNoAdjustment() {
    let result = LoudnessResult(peakLevel: -3, rmsLevel: -14, targetLoudness: -14)
    #expect(result.gainAdjustment == 0.0)
    #expect(abs(result.linearGain - 1.0) < 0.001)
}

@Test func volumeNormalizerDisabledReturnsUnity() {
    let normalizer = VolumeNormalizer()
    normalizer.isEnabled = false
    normalizer.store(result: LoudnessResult(peakLevel: -3, rmsLevel: -20), forPath: "/test.mp3")
    #expect(normalizer.gainFor(path: "/test.mp3") == 1.0)
}

@Test func volumeNormalizerEnabledReturnsAdjusted() {
    let normalizer = VolumeNormalizer()
    normalizer.isEnabled = true
    normalizer.store(result: LoudnessResult(peakLevel: -3, rmsLevel: -20), forPath: "/test.mp3")
    let gain = normalizer.gainFor(path: "/test.mp3")
    #expect(gain > 1.0) // should boost quiet track
    #expect(gain <= 4.0) // clamped
}

@Test func volumeNormalizerUnknownPathReturnsUnity() {
    let normalizer = VolumeNormalizer()
    normalizer.isEnabled = true
    #expect(normalizer.gainFor(path: "/unknown.mp3") == 1.0)
}

@Test func volumeNormalizerClampsExtremeGain() {
    let normalizer = VolumeNormalizer()
    normalizer.isEnabled = true
    // Very quiet track: -60dB RMS, target -14dB -> +46dB gain (way too much)
    normalizer.store(result: LoudnessResult(peakLevel: -10, rmsLevel: -60), forPath: "/quiet.mp3")
    #expect(normalizer.gainFor(path: "/quiet.mp3") <= 4.0) // clamped to max
}
