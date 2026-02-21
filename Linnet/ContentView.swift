import SwiftUI

struct ContentView: View {
    @State private var selectedTab: NavigationTab = .listenNow
    @State private var selectedSidebarItem: SidebarItem? = .recentlyAdded
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedItem: $selectedSidebarItem)
        } detail: {
            NavigationStack {
                ContentArea(tab: selectedTab, sidebarItem: selectedSidebarItem)
            }
            .id(selectedTab)
            .id(selectedSidebarItem)
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
