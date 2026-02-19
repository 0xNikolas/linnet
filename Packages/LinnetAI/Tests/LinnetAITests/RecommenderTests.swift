import Testing
@testable import LinnetAI

@Test func moreLikeThisExcludesSourceTrack() {
    let source = TrackEmbeddingRef(filePath: "/a.mp3", embedding: [1, 0, 0], title: "A")
    let library = [
        source,
        TrackEmbeddingRef(filePath: "/b.mp3", embedding: [0.9, 0.1, 0], title: "B"),
        TrackEmbeddingRef(filePath: "/c.mp3", embedding: [0, 1, 0], title: "C"),
    ]

    let results = Recommender.moreLikeThis(track: source, library: library, count: 5)

    #expect(results.count == 2)
    #expect(results[0].id == "/b.mp3") // most similar
    #expect(!results.contains { $0.id == "/a.mp3" }) // source excluded
}

@Test func moreLikeTheseAveragesEmbeddings() {
    let tracks = [
        TrackEmbeddingRef(filePath: "/a.mp3", embedding: [1, 0, 0]),
        TrackEmbeddingRef(filePath: "/b.mp3", embedding: [0, 1, 0]),
    ]
    let library = [
        tracks[0], tracks[1],
        TrackEmbeddingRef(filePath: "/c.mp3", embedding: [0.5, 0.5, 0]),  // closest to average
        TrackEmbeddingRef(filePath: "/d.mp3", embedding: [0, 0, 1]),      // far from average
    ]

    let results = Recommender.moreLikeThese(tracks: tracks, library: library, count: 5)

    #expect(results[0].id == "/c.mp3") // closest to [0.5, 0.5, 0]
    #expect(!results.contains { $0.id == "/a.mp3" || $0.id == "/b.mp3" }) // sources excluded
}

@Test func emptySourceReturnsEmpty() {
    let results = Recommender.moreLikeThese(tracks: [], library: [], count: 5)
    #expect(results.isEmpty)
}
