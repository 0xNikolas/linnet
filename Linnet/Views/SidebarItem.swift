import SwiftUI

enum SidebarItem: Hashable, Codable {
    case listenNow
    case recentlyAdded
    case artists
    case albums
    case songs
    case likedSongs
    case folders
    case playlists
    case playlist(String)

    /// All library items in default order.
    static let allLibraryItems: [SidebarItem] = [
        .songs, .likedSongs, .recentlyAdded, .artists, .albums, .playlists, .folders
    ]

    var label: String {
        switch self {
        case .listenNow: return "Home"
        case .recentlyAdded: return "Recently Added"
        case .artists: return "Artists"
        case .albums: return "Albums"
        case .songs: return "Songs"
        case .likedSongs: return "Liked Songs"
        case .folders: return "Folders"
        case .playlists: return "Playlists"
        case .playlist(let name): return name
        }
    }

    var systemImage: String {
        switch self {
        case .listenNow: return "house"
        case .recentlyAdded: return "clock"
        case .artists: return "music.mic"
        case .albums: return "square.stack"
        case .songs: return "music.note"
        case .likedSongs: return "bolt.fill"
        case .folders: return "folder"
        case .playlists: return "music.note.list"
        case .playlist: return "music.note.list"
        }
    }
}
