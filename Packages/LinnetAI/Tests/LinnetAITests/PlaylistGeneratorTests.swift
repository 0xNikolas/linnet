import Testing
@testable import LinnetAI

@Test func generatedPlaylistHasCorrectStructure() {
    let playlist = GeneratedPlaylist(
        name: "Chill Evening",
        description: "Relaxing tracks for the evening",
        trackFilePaths: ["/a.mp3", "/b.mp3", "/c.mp3"]
    )
    #expect(playlist.name == "Chill Evening")
    #expect(playlist.trackFilePaths.count == 3)
}

@Test func playlistRequestDefaults() {
    let request = PlaylistRequest(
        prompt: "chill vibes",
        library: [TrackEmbeddingRef(filePath: "/a.mp3", embedding: [1, 0, 0])]
    )
    #expect(request.maxTracks == 25)
    #expect(request.prompt == "chill vibes")
}
