import Testing
import Foundation
@testable import LinnetLibrary

@Test func trackMetadataCreation() {
    let metadata = TrackMetadata(
        title: "Song", artist: "Artist", album: "Album",
        trackNumber: 1, discNumber: 1, year: 2024,
        genre: "Rock", duration: 240.0, artwork: nil
    )
    #expect(metadata.title == "Song")
    #expect(metadata.artist == "Artist")
    #expect(metadata.album == "Album")
    #expect(metadata.trackNumber == 1)
    #expect(metadata.duration == 240.0)
}

@Test func trackMetadataWithNils() {
    let metadata = TrackMetadata(
        title: nil, artist: nil, album: nil,
        trackNumber: nil, discNumber: nil, year: nil,
        genre: nil, duration: 0.0, artwork: nil
    )
    #expect(metadata.title == nil)
    #expect(metadata.artist == nil)
    #expect(metadata.duration == 0.0)
}
