import SwiftUI
import SwiftData

struct ContentArea: View {
    let sidebarItem: SidebarItem?
    @Binding var highlightedTrackID: PersistentIdentifier?
    @AppStorage("nowPlayingBarHeight") private var barHeight: Double = 56

    var body: some View {
        Group {
            if let item = sidebarItem {
                switch item {
                case .listenNow:
                    ListenNowView()
                case .ai:
                    AIChatView()
                case .albums:
                    AlbumGridView()
                case .artists:
                    ArtistListView()
                case .songs:
                    SongsGroupingView(highlightedTrackID: $highlightedTrackID)
                case .likedSongs:
                    LikedSongsView(highlightedTrackID: $highlightedTrackID)
                case .folders:
                    FolderBrowserView()
                case .recentlyAdded:
                    AlbumGridView()
                case .playlist:
                    PlaylistsView()
                }
            } else {
                Text("Select an item")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: barHeight + 4)
        }
    }
}
