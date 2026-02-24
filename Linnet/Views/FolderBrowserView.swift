import SwiftUI
import SwiftData
import LinnetLibrary

struct FolderBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var watchedFolders: [WatchedFolder]
    @State private var libraryVM = LibraryViewModel()
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @AppStorage("nowPlayingBarHeight") private var barHeight: Double = 56

    private var filteredFolders: [WatchedFolder] {
        if searchText.isEmpty { return watchedFolders }
        let query = searchText
        return watchedFolders.filter { $0.path.searchContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Folders")
                    .font(.largeTitle.bold())
                Spacer()
                Button("Add Folder...") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        libraryVM.addFolder(url: url, context: modelContext)
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            if libraryVM.isScanning {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(libraryVM.scanProgress)
                        .font(.caption)
                }
                .padding(.horizontal, 20)
            }

            if filteredFolders.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Folders" : "No Results",
                    systemImage: searchText.isEmpty ? "folder.badge.plus" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? "Add a folder to browse your music files."
                        : "No folders matching \"\(searchText)\"")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredFolders, id: \.path) { folder in
                        Label(folder.path, systemImage: "folder")
                            .contextMenu {
                                Button("Remove Folder", role: .destructive) {
                                    removeFolder(folder)
                                }
                            }
                    }
                }
                .contentMargins(.bottom, barHeight + 20, for: .scrollContent)
            }
        }
        .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search folders...")
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            isSearchPresented = true
        }
    }

    private func removeFolder(_ folder: WatchedFolder) {
        let folderPath = folder.path
        let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.filePath.starts(with: folderPath) })
        if let tracks = try? modelContext.fetch(descriptor) {
            for track in tracks {
                modelContext.delete(track)
            }
        }
        modelContext.delete(folder)
        // Clean up orphaned albums and artists
        if let albums = try? modelContext.fetch(FetchDescriptor<Album>()) {
            for album in albums where album.tracks.isEmpty {
                modelContext.delete(album)
            }
        }
        if let artists = try? modelContext.fetch(FetchDescriptor<Artist>()) {
            for artist in artists where artist.tracks.isEmpty {
                modelContext.delete(artist)
            }
        }
        try? modelContext.save()
    }
}
