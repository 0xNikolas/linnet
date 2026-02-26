import SwiftUI

enum SidebarItem: Hashable, Codable {
    case listenNow
    case ai
    case recentlyAdded
    case artists
    case albums
    case songs
    case likedSongs
    case folders
    case playlist(String)

    /// All library items in default order.
    static let allLibraryItems: [SidebarItem] = [
        .songs, .likedSongs, .recentlyAdded, .artists, .albums, .folders
    ]

    var label: String {
        switch self {
        case .listenNow: return "Listen Now"
        case .ai: return "AI"
        case .recentlyAdded: return "Recently Added"
        case .artists: return "Artists"
        case .albums: return "Albums"
        case .songs: return "Songs"
        case .likedSongs: return "Liked Songs"
        case .folders: return "Folders"
        case .playlist(let name): return name
        }
    }

    var systemImage: String {
        switch self {
        case .listenNow: return "play.circle"
        case .ai: return "sparkles"
        case .recentlyAdded: return "clock"
        case .artists: return "music.mic"
        case .albums: return "square.stack"
        case .songs: return "music.note"
        case .likedSongs: return "heart.fill"
        case .folders: return "folder"
        case .playlist: return "music.note.list"
        }
    }
}
