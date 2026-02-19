import SwiftUI

struct ContentArea: View {
    let tab: NavigationTab
    let sidebarItem: SidebarItem?

    var body: some View {
        Group {
            switch tab {
            case .listenNow:
                ListenNowView()

            case .browse:
                if let item = sidebarItem {
                    switch item {
                    case .albums:
                        AlbumGridView()
                    case .artists:
                        ArtistListView()
                    case .songs:
                        SongsListView()
                    case .folders:
                        FolderBrowserView()
                    case .recentlyAdded:
                        AlbumGridView()
                    case .playlist(let name):
                        Text(name)
                            .font(.largeTitle.bold())
                    }
                } else {
                    Text("Select an item")
                        .foregroundStyle(.secondary)
                }

            case .playlists:
                PlaylistsView()

            case .ai:
                AIChatView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
