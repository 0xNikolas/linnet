import SwiftUI
import SwiftData
import LinnetLibrary

struct ContentView: View {
    @Environment(PlayerViewModel.self) private var player
    @State private var selectedTab: NavigationTab = .browse
    @State private var selectedSidebarItem: SidebarItem? = .songs
    @State private var isDropTargeted = false
    @State private var navigationPath = NavigationPath()
    @State private var highlightedTrackID: PersistentIdentifier?
    @AppStorage("showQueueSidePane") private var showQueueSidePane = false
    @State private var breadcrumbs: [BreadcrumbItem] = []

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedItem: $selectedSidebarItem)
        } detail: {
            HStack(spacing: 0) {
                NavigationStack(path: $navigationPath) {
                    VStack(spacing: 0) {
                        if breadcrumbs.count > 1 {
                            BreadcrumbBar(items: breadcrumbs) { level in
                                let popCount = navigationPath.count - level
                                for _ in 0..<popCount {
                                    navigationPath.removeLast()
                                }
                            }
                            Divider()
                        }
                        ContentArea(tab: selectedTab, sidebarItem: selectedSidebarItem, highlightedTrackID: $highlightedTrackID)
                    }
                        .navigationDestination(for: Album.self) { album in
                            let _ = Log.navigation.debug("Pushing AlbumDetailView: \(album.name)")
                            AlbumDetailView(album: album)
                                .onAppear {
                                    NotificationCenter.default.post(
                                        name: .registerBreadcrumb,
                                        object: nil,
                                        userInfo: ["title": album.name]
                                    )
                                }
                        }
                        .navigationDestination(for: Artist.self) { artist in
                            let _ = Log.navigation.debug("Pushing ArtistDetailView: \(artist.name)")
                            ArtistDetailView(artist: artist, navigationPath: $navigationPath)
                                .onAppear {
                                    NotificationCenter.default.post(
                                        name: .registerBreadcrumb,
                                        object: nil,
                                        userInfo: ["title": artist.name]
                                    )
                                }
                        }
                }
                .id("\(selectedTab)-\(selectedSidebarItem.map { "\($0)" } ?? "none")")
                .environment(\.navigationPath, $navigationPath)

                if showQueueSidePane {
                    Divider()
                    QueuePanel(isShowing: $showQueueSidePane)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            NowPlayingBar()
        }
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                Picker("", selection: $selectedTab) {
                    ForEach(NavigationTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 350)
            }
        }
        .onChange(of: selectedSidebarItem) { _, newItem in
            navigationPath = NavigationPath()
            breadcrumbs = [BreadcrumbItem(title: newItem?.label ?? "Browse", level: 0)]
            if newItem != nil && selectedTab != .browse {
                selectedTab = .browse
            }
        }
        .onChange(of: selectedTab) { _, _ in
            navigationPath = NavigationPath()
            breadcrumbs = [BreadcrumbItem(title: selectedSidebarItem?.label ?? "Browse", level: 0)]
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
            breadcrumbs = [BreadcrumbItem(title: selectedSidebarItem?.label ?? "Browse", level: 0)]
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToCurrentTrack)) { _ in
            guard let track = player.currentQueueTrack else { return }
            // If already viewing the track's artist page, scroll to the track there
            if selectedTab == .browse && selectedSidebarItem == .artists && !navigationPath.isEmpty {
                NotificationCenter.default.post(
                    name: .highlightTrackInDetail,
                    object: nil,
                    userInfo: ["trackID": track.persistentModelID]
                )
                return
            }
            selectedTab = .browse
            selectedSidebarItem = .songs
            navigationPath = NavigationPath()
            highlightedTrackID = track.persistentModelID
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToCurrentArtist)) { _ in
            guard let artist = player.currentQueueTrack?.artist else { return }
            // Already viewing this artist — do nothing
            if selectedTab == .browse && selectedSidebarItem == .artists && !navigationPath.isEmpty {
                return
            }
            selectedTab = .browse
            selectedSidebarItem = .artists
            navigationPath = NavigationPath()
            // Small delay to let the view switch happen before pushing
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                navigationPath.append(artist)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleQueueSidePane)) { _ in
            showQueueSidePane.toggle()
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
