import Testing
@testable import LinnetAudio

@Test func eqPresetBandCount() {
    let flat = EQPreset.flat
    #expect(flat.bands.count == 10)
    #expect(flat.bands.allSatisfy { $0.gain == 0.0 })
}

@Test func eqPresetBassBoost() {
    let bass = EQPreset.bassBoost
    #expect(bass.bands[0].gain > 0)
    #expect(bass.bands[1].gain > 0)
    #expect(bass.bands[2].gain > 0)
}

@Test func allPresetsHave10Bands() {
    for preset in EQPreset.allPresets {
        #expect(preset.bands.count == 10)
    }
}
