import SwiftUI
import SwiftData
import LinnetLibrary

struct FolderBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var watchedFolders: [WatchedFolder]
    @State private var libraryVM = LibraryViewModel()

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

            if watchedFolders.isEmpty {
                ContentUnavailableView("No Folders", systemImage: "folder.badge.plus", description: Text("Add a folder to browse your music files."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(watchedFolders, id: \.path) { folder in
                        Label(folder.path, systemImage: "folder")
                    }
                }
            }
        }
    }
}
