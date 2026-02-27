import SwiftUI
import LinnetLibrary

struct FolderBrowserView: View {
    @Environment(\.appDatabase) private var appDatabase
    @State private var watchedFolders: [WatchedFolderRecord] = []
    @State private var libraryVM = LibraryViewModel()
    @State private var searchText = ""
    @State private var isSearchPresented = false

    private var filteredFolders: [WatchedFolderRecord] {
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
                        if let db = appDatabase {
                            libraryVM.addFolder(url: url, db: db)
                            loadFolders()
                        }
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
            }
        }
        .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search folders...")
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            isSearchPresented = true
        }
        .task { loadFolders() }
    }

    private func loadFolders() {
        watchedFolders = (try? appDatabase?.watchedFolders.fetchAll()) ?? []
    }

    private func removeFolder(_ folder: WatchedFolderRecord) {
        guard let db = appDatabase else { return }
        try? db.tracks.deleteByFolder(pathPrefix: folder.path)
        try? db.watchedFolders.deleteByPath(folder.path)
        try? db.albums.deleteOrphaned()
        try? db.artists.deleteOrphaned()
        loadFolders()
    }
}
