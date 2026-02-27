import Foundation
import GRDB
import Observation

/// Central database facade. Holds all repositories and the database pool.
/// Injected into the SwiftUI environment.
@Observable
@MainActor
public final class AppDatabase {
    public let manager: DatabaseManager

    public let tracks: TrackRepository
    public let albums: AlbumRepository
    public let artists: ArtistRepository
    public let playlists: PlaylistRepository
    public let artwork: ArtworkRepository
    public let watchedFolders: WatchedFolderRepository

    public init(location: DatabaseLocation = .appSupport) throws {
        let mgr = try DatabaseManager(location: location)
        self.manager = mgr
        self.tracks = TrackRepository(pool: mgr.pool)
        self.albums = AlbumRepository(pool: mgr.pool)
        self.artists = ArtistRepository(pool: mgr.pool)
        self.playlists = PlaylistRepository(pool: mgr.pool)
        self.artwork = ArtworkRepository(pool: mgr.pool)
        self.watchedFolders = WatchedFolderRepository(pool: mgr.pool)
    }

    /// Creates an in-memory AppDatabase for testing.
    public init(inMemory: Bool) throws {
        precondition(inMemory)
        let mgr = try DatabaseManager(inMemory: true)
        self.manager = mgr
        self.tracks = TrackRepository(pool: mgr.pool)
        self.albums = AlbumRepository(pool: mgr.pool)
        self.artists = ArtistRepository(pool: mgr.pool)
        self.playlists = PlaylistRepository(pool: mgr.pool)
        self.artwork = ArtworkRepository(pool: mgr.pool)
        self.watchedFolders = WatchedFolderRepository(pool: mgr.pool)
    }

    /// The underlying database pool, for advanced queries and observations.
    public var pool: DatabasePool { manager.pool }
}
