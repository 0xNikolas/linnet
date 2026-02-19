import SwiftUI

enum NavigationTab: String, CaseIterable, Identifiable {
    case listenNow = "Listen Now"
    case browse = "Browse"
    case playlists = "Playlists"
    case ai = "AI"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .listenNow: return "play.circle"
        case .browse: return "square.grid.2x2"
        case .playlists: return "music.note.list"
        case .ai: return "sparkles"
        }
    }
}
