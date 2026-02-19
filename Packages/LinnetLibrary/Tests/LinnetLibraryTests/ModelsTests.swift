import Testing
import SwiftData
@testable import LinnetLibrary

@Test func trackCreation() throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: Track.self, Album.self, Artist.self, configurations: config)
    let context = ModelContext(container)

    let track = Track(
        filePath: "/music/song.mp3",
        title: "Test Song",
        duration: 240.0,
        trackNumber: 1
    )
    context.insert(track)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<Track>())
    #expect(fetched.count == 1)
    #expect(fetched[0].title == "Test Song")
    #expect(fetched[0].duration == 240.0)
}

@Test func albumWithTracks() throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: Track.self, Album.self, Artist.self, configurations: config)
    let context = ModelContext(container)

    let album = Album(name: "Test Album", year: 2024)
    let track = Track(filePath: "/music/song.mp3", title: "Track 1", duration: 180.0, trackNumber: 1)
    track.album = album
    context.insert(album)
    context.insert(track)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<Album>())
    #expect(fetched.count == 1)
    #expect(fetched[0].tracks.count == 1)
}

@Test func playlistOrdering() throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: Track.self, Album.self, Artist.self, Playlist.self, PlaylistEntry.self,
        configurations: config
    )
    let context = ModelContext(container)

    let playlist = Playlist(name: "My Playlist")
    let t1 = Track(filePath: "/a.mp3", title: "A", duration: 100, trackNumber: 1)
    let t2 = Track(filePath: "/b.mp3", title: "B", duration: 200, trackNumber: 2)
    context.insert(t1)
    context.insert(t2)
    context.insert(playlist)

    let e1 = PlaylistEntry(track: t1, order: 0)
    let e2 = PlaylistEntry(track: t2, order: 1)
    playlist.entries = [e1, e2]
    context.insert(e1)
    context.insert(e2)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<Playlist>())
    #expect(fetched[0].entries.sorted(by: { $0.order < $1.order })[0].track.title == "A")
    #expect(fetched[0].entries.sorted(by: { $0.order < $1.order })[1].track.title == "B")
}
