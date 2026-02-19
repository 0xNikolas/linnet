import SwiftUI

struct SidebarView: View {
    @Binding var selectedItem: SidebarItem?

    var body: some View {
        List(selection: $selectedItem) {
            Section("Library") {
                ForEach([SidebarItem.recentlyAdded, .artists, .albums, .songs, .folders], id: \.self) { item in
                    Label(item.label, systemImage: item.systemImage)
                        .tag(item)
                }
            }

            Section("Playlists") {
                // Placeholder — will be populated from SwiftData later
                Label("New Playlist...", systemImage: "plus")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
    }
}
