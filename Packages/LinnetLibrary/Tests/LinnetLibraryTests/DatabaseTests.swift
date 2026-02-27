import Testing
import Foundation
@testable import LinnetLibrary

@Suite("Database Layer Tests", .serialized)
@MainActor
struct DatabaseTests {

    // MARK: - Helpers

    private func makeDB() throws -> AppDatabase {
        try AppDatabase(inMemory: true)
    }

    // MARK: - Artist Repository

    @Test("Insert and fetch artist")
    func artistInsertFetch() throws {
        let db = try makeDB()
        var artist = ArtistRecord(name: "Radiohead")
        try db.artists.insert(&artist)

        #expect(artist.id != nil)
        let fetched = try db.artists.fetchOne(id: artist.id!)
        #expect(fetched?.name == "Radiohead")
    }

    @Test("Artist findOrCreate returns existing")
    func artistFindOrCreate() throws {
        let db = try makeDB()
        let first = try db.artists.findOrCreate(name: "Björk")
        let second = try db.artists.findOrCreate(name: "Björk")
        #expect(first.id == second.id)
        #expect(try db.artists.count() == 1)
    }

    @Test("Fetch artist by name")
    func artistFetchByName() throws {
        let db = try makeDB()
        var artist = ArtistRecord(name: "Portishead")
        try db.artists.insert(&artist)
        let found = try db.artists.fetchByName("Portishead")
        #expect(found?.id == artist.id)
        #expect(try db.artists.fetchByName("Nonexistent") == nil)
    }

    @Test("Delete artist")
    func artistDelete() throws {
        let db = try makeDB()
        var artist = ArtistRecord(name: "Massive Attack")
        try db.artists.insert(&artist)
        try db.artists.delete(id: artist.id!)
        #expect(try db.artists.fetchOne(id: artist.id!) == nil)
    }

    // MARK: - Album Repository

    @Test("Insert and fetch album")
    func albumInsertFetch() throws {
        let db = try makeDB()
        var artist = ArtistRecord(name: "Radiohead")
        try db.artists.insert(&artist)

        var album = AlbumRecord(name: "OK Computer", artistName: "Radiohead", year: 1997, artistId: artist.id)
        try db.albums.insert(&album)

        #expect(album.id != nil)
        let fetched = try db.albums.fetchOne(id: album.id!)
        #expect(fetched?.name == "OK Computer")
        #expect(fetched?.year == 1997)
    }

    @Test("Album findOrCreate")
    func albumFindOrCreate() throws {
        let db = try makeDB()
        let first = try db.albums.findOrCreate(name: "Kid A", artistName: "Radiohead", year: 2000, artistId: nil)
        let second = try db.albums.findOrCreate(name: "Kid A", artistName: "Radiohead", year: 2000, artistId: nil)
        #expect(first.id == second.id)
        #expect(try db.albums.count() == 1)
    }

    @Test("Fetch albums by artist")
    func albumsByArtist() throws {
        let db = try makeDB()
        var artist = ArtistRecord(name: "Radiohead")
        try db.artists.insert(&artist)

        var a1 = AlbumRecord(name: "The Bends", artistName: "Radiohead", year: 1995, artistId: artist.id)
        var a2 = AlbumRecord(name: "OK Computer", artistName: "Radiohead", year: 1997, artistId: artist.id)
        try db.albums.insert(&a1)
        try db.albums.insert(&a2)

        let albums = try db.albums.fetchByArtist(id: artist.id!)
        #expect(albums.count == 2)
        #expect(albums[0].name == "The Bends") // ordered by year
    }

    // MARK: - Track Repository

    @Test("Insert and fetch track")
    func trackInsertFetch() throws {
        let db = try makeDB()
        var track = TrackRecord(filePath: "/music/song.mp3", title: "Airbag", duration: 287.0, trackNumber: 1)
        try db.tracks.insert(&track)

        #expect(track.id != nil)
        let fetched = try db.tracks.fetchOne(id: track.id!)
        #expect(fetched?.title == "Airbag")
        #expect(fetched?.duration == 287.0)
    }

    @Test("Track fetchByFilePath")
    func trackByFilePath() throws {
        let db = try makeDB()
        var track = TrackRecord(filePath: "/music/paranoid.flac", title: "Paranoid Android", duration: 384.0, trackNumber: 2)
        try db.tracks.insert(&track)

        let found = try db.tracks.fetchByFilePath("/music/paranoid.flac")
        #expect(found?.id == track.id)
        #expect(try db.tracks.fetchByFilePath("/nonexistent") == nil)
    }

    @Test("Track liked status update")
    func trackLikedStatus() throws {
        let db = try makeDB()
        var track = TrackRecord(filePath: "/music/lucky.mp3", title: "Lucky", duration: 263.0, trackNumber: 7)
        try db.tracks.insert(&track)

        try db.tracks.updateLikedStatus(id: track.id!, status: 1)
        let fetched = try db.tracks.fetchOne(id: track.id!)
        #expect(fetched?.likedStatus == 1)
    }

    @Test("Track play count update")
    func trackPlayCount() throws {
        let db = try makeDB()
        var track = TrackRecord(filePath: "/music/karma.mp3", title: "Karma Police", duration: 264.0, trackNumber: 6)
        try db.tracks.insert(&track)

        try db.tracks.updatePlayCount(id: track.id!)
        try db.tracks.updatePlayCount(id: track.id!)
        let fetched = try db.tracks.fetchOne(id: track.id!)
        #expect(fetched?.playCount == 2)
        #expect(fetched?.lastPlayed != nil)
    }

    @Test("Fetch liked tracks")
    func fetchLikedTracks() throws {
        let db = try makeDB()
        var t1 = TrackRecord(filePath: "/a.mp3", title: "A", duration: 100, trackNumber: 1, likedStatus: 1)
        var t2 = TrackRecord(filePath: "/b.mp3", title: "B", duration: 100, trackNumber: 2, likedStatus: 0)
        var t3 = TrackRecord(filePath: "/c.mp3", title: "C", duration: 100, trackNumber: 3, likedStatus: 1)
        try db.tracks.insert(&t1)
        try db.tracks.insert(&t2)
        try db.tracks.insert(&t3)

        let liked = try db.tracks.fetchLiked()
        #expect(liked.count == 2)
    }

    @Test("Bulk insert tracks")
    func trackBulkInsert() throws {
        let db = try makeDB()
        var tracks = (1...100).map {
            TrackRecord(filePath: "/music/track\($0).mp3", title: "Track \($0)", duration: 200, trackNumber: $0)
        }
        try db.tracks.insertAll(&tracks)
        #expect(try db.tracks.count() == 100)
        #expect(tracks.allSatisfy { $0.id != nil })
    }

    @Test("All file paths")
    func allFilePaths() throws {
        let db = try makeDB()
        var t1 = TrackRecord(filePath: "/a.mp3", title: "A", duration: 100, trackNumber: 1)
        var t2 = TrackRecord(filePath: "/b.mp3", title: "B", duration: 100, trackNumber: 2)
        try db.tracks.insert(&t1)
        try db.tracks.insert(&t2)

        let paths = try db.tracks.allFilePaths()
        #expect(paths == ["/a.mp3", "/b.mp3"])
    }

    // MARK: - TrackInfo (joined queries)

    @Test("TrackInfo includes artist and album names")
    func trackInfoJoin() throws {
        let db = try makeDB()
        var artist = ArtistRecord(name: "Radiohead")
        try db.artists.insert(&artist)
        var album = AlbumRecord(name: "OK Computer", artistName: "Radiohead", year: 1997, artistId: artist.id)
        try db.albums.insert(&album)
        var track = TrackRecord(
            filePath: "/music/airbag.mp3", title: "Airbag", duration: 287, trackNumber: 1,
            albumId: album.id, artistId: artist.id
        )
        try db.tracks.insert(&track)

        let infos = try db.tracks.fetchAllInfo()
        #expect(infos.count == 1)
        #expect(infos[0].artistName == "Radiohead")
        #expect(infos[0].albumName == "OK Computer")
    }

    // MARK: - FTS5 Search

    @Test("FTS5 search by title")
    func ftsSearch() throws {
        let db = try makeDB()
        var t1 = TrackRecord(filePath: "/a.mp3", title: "Paranoid Android", duration: 384, trackNumber: 1)
        var t2 = TrackRecord(filePath: "/b.mp3", title: "Lucky", duration: 263, trackNumber: 2)
        try db.tracks.insert(&t1)
        try db.tracks.insert(&t2)

        let results = try db.tracks.search(query: "paranoid")
        #expect(results.count == 1)
        #expect(results[0].title == "Paranoid Android")
    }

    // MARK: - Playlist Repository

    @Test("Create playlist and add tracks")
    func playlistCRUD() throws {
        let db = try makeDB()
        var playlist = PlaylistRecord(name: "My Mix")
        try db.playlists.insert(&playlist)

        var t1 = TrackRecord(filePath: "/a.mp3", title: "Song A", duration: 200, trackNumber: 1)
        var t2 = TrackRecord(filePath: "/b.mp3", title: "Song B", duration: 200, trackNumber: 2)
        try db.tracks.insert(&t1)
        try db.tracks.insert(&t2)

        try db.playlists.addTrack(trackId: t1.id!, toPlaylist: playlist.id!)
        try db.playlists.addTrack(trackId: t2.id!, toPlaylist: playlist.id!)

        let entries = try db.playlists.fetchEntries(playlistId: playlist.id!)
        #expect(entries.count == 2)
        #expect(entries[0].order == 0)
        #expect(entries[1].order == 1)
    }

    @Test("Playlist track infos")
    func playlistTrackInfos() throws {
        let db = try makeDB()
        var artist = ArtistRecord(name: "Test Artist")
        try db.artists.insert(&artist)
        var playlist = PlaylistRecord(name: "Test Playlist")
        try db.playlists.insert(&playlist)
        var track = TrackRecord(filePath: "/a.mp3", title: "Song A", duration: 200, trackNumber: 1, artistId: artist.id)
        try db.tracks.insert(&track)
        try db.playlists.addTrack(trackId: track.id!, toPlaylist: playlist.id!)

        let infos = try db.playlists.fetchTrackInfos(playlistId: playlist.id!)
        #expect(infos.count == 1)
        #expect(infos[0].artistName == "Test Artist")
    }

    @Test("Delete playlist cascades entries")
    func playlistDeleteCascade() throws {
        let db = try makeDB()
        var playlist = PlaylistRecord(name: "Temp")
        try db.playlists.insert(&playlist)
        var track = TrackRecord(filePath: "/a.mp3", title: "A", duration: 100, trackNumber: 1)
        try db.tracks.insert(&track)
        try db.playlists.addTrack(trackId: track.id!, toPlaylist: playlist.id!)

        try db.playlists.delete(id: playlist.id!)
        let entries = try db.playlists.fetchEntries(playlistId: playlist.id!)
        #expect(entries.isEmpty)
    }

    // MARK: - Artwork Repository

    @Test("Upsert and fetch artwork")
    func artworkUpsertFetch() throws {
        let db = try makeDB()
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let thumbData = Data([0x89, 0x50, 0x4E])

        try db.artwork.upsert(ownerType: "album", ownerId: 1, imageData: imageData, thumbnailData: thumbData)

        let fetched = try db.artwork.fetch(ownerType: "album", ownerId: 1)
        #expect(fetched?.imageData == imageData)
        #expect(fetched?.thumbnailData == thumbData)

        // Upsert again (update)
        let newImage = Data([0x00, 0x01])
        try db.artwork.upsert(ownerType: "album", ownerId: 1, imageData: newImage, thumbnailData: nil)
        let updated = try db.artwork.fetch(ownerType: "album", ownerId: 1)
        #expect(updated?.imageData == newImage)
        #expect(updated?.thumbnailData == nil)
    }

    @Test("Fetch thumbnail only")
    func artworkThumbnail() throws {
        let db = try makeDB()
        let thumb = Data([0x01, 0x02, 0x03])
        try db.artwork.upsert(ownerType: "track", ownerId: 42, imageData: nil, thumbnailData: thumb)

        let fetched = try db.artwork.fetchThumbnail(ownerType: "track", ownerId: 42)
        #expect(fetched == thumb)
    }

    @Test("Has artwork check")
    func artworkExists() throws {
        let db = try makeDB()
        #expect(try !db.artwork.hasArtwork(ownerType: "artist", ownerId: 1))
        try db.artwork.upsert(ownerType: "artist", ownerId: 1, imageData: Data([0xFF]), thumbnailData: nil)
        #expect(try db.artwork.hasArtwork(ownerType: "artist", ownerId: 1))
    }

    // MARK: - WatchedFolder Repository

    @Test("Insert and fetch watched folder")
    func watchedFolderCRUD() throws {
        let db = try makeDB()
        var folder = WatchedFolderRecord(path: "/Users/test/Music")
        try db.watchedFolders.insert(&folder)

        #expect(folder.id != nil)
        let fetched = try db.watchedFolders.fetchOne(id: folder.id!)
        #expect(fetched?.path == "/Users/test/Music")
        #expect(fetched?.isEnabled == true)
    }

    @Test("Fetch enabled folders only")
    func watchedFolderEnabled() throws {
        let db = try makeDB()
        var f1 = WatchedFolderRecord(path: "/Music1", isEnabled: true)
        var f2 = WatchedFolderRecord(path: "/Music2", isEnabled: false)
        try db.watchedFolders.insert(&f1)
        try db.watchedFolders.insert(&f2)

        let enabled = try db.watchedFolders.fetchEnabled()
        #expect(enabled.count == 1)
        #expect(enabled[0].path == "/Music1")
    }

    @Test("Update last scanned")
    func watchedFolderLastScanned() throws {
        let db = try makeDB()
        var folder = WatchedFolderRecord(path: "/Music")
        try db.watchedFolders.insert(&folder)
        #expect(folder.lastScanned == nil)

        try db.watchedFolders.updateLastScanned(id: folder.id!)
        let updated = try db.watchedFolders.fetchOne(id: folder.id!)
        #expect(updated?.lastScanned != nil)
    }

    // MARK: - Foreign Key Constraints

    @Test("Deleting artist nullifies album.artistId")
    func artistDeleteNullifiesAlbum() throws {
        let db = try makeDB()
        var artist = ArtistRecord(name: "Test")
        try db.artists.insert(&artist)
        var album = AlbumRecord(name: "Album", artistName: "Test", artistId: artist.id)
        try db.albums.insert(&album)

        try db.artists.delete(id: artist.id!)
        let fetched = try db.albums.fetchOne(id: album.id!)
        #expect(fetched?.artistId == nil)
    }

    @Test("Deleting track cascades playlist entries")
    func trackDeleteCascadesEntries() throws {
        let db = try makeDB()
        var playlist = PlaylistRecord(name: "PL")
        try db.playlists.insert(&playlist)
        var track = TrackRecord(filePath: "/a.mp3", title: "A", duration: 100, trackNumber: 1)
        try db.tracks.insert(&track)
        try db.playlists.addTrack(trackId: track.id!, toPlaylist: playlist.id!)

        try db.tracks.delete(id: track.id!)
        let entries = try db.playlists.fetchEntries(playlistId: playlist.id!)
        #expect(entries.isEmpty)
    }
}
