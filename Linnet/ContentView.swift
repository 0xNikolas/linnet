import SwiftUI
import LinnetLibrary

struct ContentView: View {
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.appDatabase) private var appDatabase
    @State private var selectedSidebarItem: SidebarItem? = .listenNow
    @State private var isDropTargeted = false
    @State private var navigationPath = NavigationPath()
    @State private var highlightedTrackID: Int64?
    @AppStorage("showQueueSidePane") private var showQueueSidePane = false
    @State private var breadcrumbs: [BreadcrumbItem] = []
    @State private var pendingNavigation: PendingNavigation?

    private enum PendingNavigation {
        case artist(ArtistRecord)
        case album(AlbumRecord)
        case playlist(Int64)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedItem: $selectedSidebarItem)
        } detail: {
            HStack(spacing: 0) {
                NavigationStack(path: $navigationPath) {
                    ContentArea(sidebarItem: selectedSidebarItem, highlightedTrackID: $highlightedTrackID)
                        .navigationTitle(selectedSidebarItem?.label ?? "Linnet")
                        .navigationDestination(for: AlbumRecord.self) { album in
                            let _ = Log.navigation.debug("Pushing AlbumDetailView: \(album.name)")
                            AlbumDetailView(album: album)
                                .navigationTitle(selectedSidebarItem?.label ?? "Albums")
                                .onAppear {
                                    NotificationCenter.default.post(
                                        name: .registerBreadcrumb,
                                        object: nil,
                                        userInfo: ["title": album.name]
                                    )
                                }
                        }
                        .navigationDestination(for: ArtistRecord.self) { artist in
                            let _ = Log.navigation.debug("Pushing ArtistDetailView: \(artist.name)")
                            ArtistDetailView(artist: artist, onNavigateToAlbum: { album in
                                    navigationPath.append(album)
                                })
                                .navigationTitle(selectedSidebarItem?.label ?? "Artists")
                                .onAppear {
                                    NotificationCenter.default.post(
                                        name: .registerBreadcrumb,
                                        object: nil,
                                        userInfo: ["title": artist.name]
                                    )
                                }
                        }
                        .navigationDestination(for: Int64.self) { id in
                            PlaylistDetailView(playlistID: id)
                                .navigationTitle("Playlists")
                        }
                }
                .id(selectedSidebarItem.map { "\($0)" } ?? "none")
                .environment(\.navigationPath, $navigationPath)
                .frame(maxWidth: .infinity)

                if showQueueSidePane {
                    Divider()
                    QueuePanel(isShowing: $showQueueSidePane)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showQueueSidePane)
        }
        .safeAreaInset(edge: .bottom) {
            NowPlayingBar()
        }
        .onChange(of: selectedSidebarItem) { _, newItem in
            navigationPath = NavigationPath()
            breadcrumbs = [BreadcrumbItem(title: newItem?.label ?? "Home", level: 0)]
            if let pending = pendingNavigation {
                pendingNavigation = nil
                Task { @MainActor in
                    await Task.yield()
                    switch pending {
                    case .artist(let artist): navigationPath.append(artist)
                    case .album(let album): navigationPath.append(album)
                    case .playlist(let id): navigationPath.append(id)
                    }
                }
            }
        }
        .onChange(of: navigationPath.count) { oldCount, newCount in
            if newCount < oldCount {
                breadcrumbs = Array(breadcrumbs.prefix(newCount + 1))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .registerBreadcrumb)) { notification in
            guard let title = notification.userInfo?["title"] as? String else { return }
            let level = navigationPath.count
            if breadcrumbs.count <= level {
                breadcrumbs.append(BreadcrumbItem(title: title, level: level))
            }
        }
        .onAppear {
            breadcrumbs = [BreadcrumbItem(title: selectedSidebarItem?.label ?? "Home", level: 0)]
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToCurrentTrack)) { _ in
            guard let track = player.currentQueueTrack else { return }
            if selectedSidebarItem == .artists && !navigationPath.isEmpty {
                NotificationCenter.default.post(
                    name: .highlightTrackInDetail,
                    object: nil,
                    userInfo: ["trackID": track.id]
                )
                return
            }
            selectedSidebarItem = .songs
            navigationPath = NavigationPath()
            highlightedTrackID = track.id
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToCurrentArtist)) { _ in
            guard let artistId = player.currentQueueTrack?.artistId,
                  let artistName = player.currentQueueTrack?.artistName else { return }
            if selectedSidebarItem == .artists && !navigationPath.isEmpty {
                return
            }
            selectedSidebarItem = .artists
            pendingNavigation = .artist(ArtistRecord(id: artistId, name: artistName))
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleQueueSidePane)) { _ in
            showQueueSidePane.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToArtist)) { notification in
            guard let artistId = notification.userInfo?["artistId"] as? Int64,
                  let artistName = notification.userInfo?["artistName"] as? String else { return }
            selectedSidebarItem = .artists
            pendingNavigation = .artist(ArtistRecord(id: artistId, name: artistName))
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToAlbum)) { notification in
            guard let albumId = notification.userInfo?["albumId"] as? Int64 else { return }
            guard let album = try? appDatabase?.albums.fetchOne(id: albumId) else { return }
            selectedSidebarItem = .albums
            pendingNavigation = .album(album)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToPlaylist)) { notification in
            guard let playlistID = notification.userInfo?["playlistID"] as? Int64 else { return }
            selectedSidebarItem = .playlists
            pendingNavigation = .playlist(playlistID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        .frame(minWidth: 900, minHeight: 600)
        .dropDestination(for: URL.self) { urls, _ in
            let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "flac", "alac", "wav", "aiff", "aif", "ogg", "wma", "caf", "opus"]
            let audioURLs = urls.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            guard !audioURLs.isEmpty else { return false }
            // TODO: Import dropped files via LibraryManager
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .dropOverlay(isTargeted: isDropTargeted)
    }

}
