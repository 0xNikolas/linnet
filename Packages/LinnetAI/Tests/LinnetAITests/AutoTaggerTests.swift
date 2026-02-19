import Testing
import Foundation
@testable import LinnetAI

@Test func taggingResultCreation() {
    let result = TaggingResult(
        filePath: "/test.mp3",
        genre: "Rock",
        mood: "Energetic",
        bpm: 128.0,
        energy: 0.8
    )
    #expect(result.genre == "Rock")
    #expect(result.mood == "Energetic")
    #expect(result.bpm == 128.0)
    #expect(result.energy == 0.8)
}

@Test func supportedGenresNotEmpty() {
    #expect(!AutoTagger.supportedGenres.isEmpty)
    #expect(AutoTagger.supportedGenres.contains("Rock"))
}

@Test func supportedMoodsNotEmpty() {
    #expect(!AutoTagger.supportedMoods.isEmpty)
    #expect(AutoTagger.supportedMoods.contains("Calm"))
}
