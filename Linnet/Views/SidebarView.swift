import SwiftUI
import LinnetLibrary

struct SidebarView: View {
    @Binding var selectedItem: SidebarItem?
    @AppStorage("sidebarConfiguration") private var configuration: SidebarConfiguration = .default
    @State private var showEditSheet = false
    @State private var showNewPlaylistSheet = false
    @State private var renamingPlaylist: PlaylistRecord?
    @State private var renameText = ""
    @State private var playlists: [PlaylistRecord] = []
    @Environment(\.appDatabase) private var appDatabase
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        List(selection: $selectedItem) {
            Section {
                sidebarLabel(SidebarItem.listenNow)
                sidebarLabel(SidebarItem.ai)
            } header: {
                Text("Home")
                    .font(.app(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(configuration.visibleItems, id: \.self) { item in
                    sidebarLabel(item)
                        .contextMenu {
                            Button { setVisibility(of: item, visible: false) } label: { Label("Hide \"\(item.label)\"", systemImage: "eye.slash") }
                            Divider()
                            Button { showEditSheet = true } label: { Label("Edit Sidebar...", systemImage: "sidebar.left") }
                        }
                }
                .onMove { source, destination in
                    moveVisibleItems(from: source, to: destination)
                }
            } header: {
                Text("Library")
                    .font(.app(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(playlists) { playlist in
                    HStack(spacing: 8) {
                        Image(systemName: playlist.isAIGenerated ? "sparkles" : "music.note.list")
                            .font(.system(size: 18))
                            .frame(width: 24, alignment: .center)
                            .foregroundStyle(.secondary)
                        Text(playlist.name)
                            .font(.app(size: 13))
                    }
                        .tag(SidebarItem.playlist(String(playlist.id!)))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedItem = nil
                            NotificationCenter.default.post(
                                name: .navigateToPlaylist,
                                object: nil,
                                userInfo: ["playlistID": playlist.id!]
                            )
                        }
                        .contextMenu {
                            Button {
                                let tracks = (try? appDatabase?.playlists.fetchTrackInfos(playlistId: playlist.id!)) ?? []
                                guard let first = tracks.first else { return }
                                player.playTrack(first, queue: tracks)
                            } label: { Label("Play", systemImage: "play") }
                            .disabled((try? appDatabase?.playlists.entryCount(playlistId: playlist.id!)) ?? 0 == 0)

                            Button {
                                let tracks = (try? appDatabase?.playlists.fetchTrackInfos(playlistId: playlist.id!)) ?? []
                                for track in tracks.reversed() {
                                    player.addNext(track)
                                }
                            } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                            .disabled((try? appDatabase?.playlists.entryCount(playlistId: playlist.id!)) ?? 0 == 0)

                            Button {
                                let tracks = (try? appDatabase?.playlists.fetchTrackInfos(playlistId: playlist.id!)) ?? []
                                for track in tracks {
                                    player.addLater(track)
                                }
                            } label: { Label("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward") }
                            .disabled((try? appDatabase?.playlists.entryCount(playlistId: playlist.id!)) ?? 0 == 0)

                            Divider()

                            Button {
                                renameText = playlist.name
                                renamingPlaylist = playlist
                            } label: { Label("Rename...", systemImage: "pencil") }

                            Button { duplicatePlaylist(playlist) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }

                            Divider()

                            Button(role: .destructive) { deletePlaylist(playlist) } label: { Label("Delete Playlist", systemImage: "trash") }
                        }
                }

                Button {
                    showNewPlaylistSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 18))
                            .frame(width: 24, alignment: .center)
                        Text("New Playlist...")
                            .font(.app(size: 13))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } header: {
                Text("Playlists")
                    .font(.app(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showNewPlaylistSheet) {
            NewPlaylistSheet(tracks: [])
        }
        .listStyle(.sidebar)
        .task {
            configuration.mergeDefaults()
            loadPlaylists()
        }
        .sheet(isPresented: $showEditSheet) {
            EditSidebarSheet(configuration: $configuration)
        }
        .alert("Rename Playlist", isPresented: Binding(
            get: { renamingPlaylist != nil },
            set: { if !$0 { renamingPlaylist = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingPlaylist = nil }
            Button("Rename") {
                if var playlist = renamingPlaylist, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    playlist.name = renameText.trimmingCharacters(in: .whitespaces)
                    try? appDatabase?.playlists.update(playlist)
                    loadPlaylists()
                }
                renamingPlaylist = nil
            }
        }
    }

    // MARK: - Sidebar Label

    private func sidebarLabel(_ item: SidebarItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.systemImage)
                .font(.system(size: 18))
                .frame(width: 24, alignment: .center)
                .foregroundStyle(.secondary)
            Text(item.label)
                .font(.app(size: 13))
        }
        .tag(item)
    }

    // MARK: - Helpers

    private func loadPlaylists() {
        playlists = (try? appDatabase?.playlists.fetchAllByCreatedAt()) ?? []
    }

    private func deletePlaylist(_ playlist: PlaylistRecord) {
        guard let id = playlist.id else { return }
        try? appDatabase?.playlists.delete(id: id)
        loadPlaylists()
    }

    private func duplicatePlaylist(_ playlist: PlaylistRecord) {
        guard let id = playlist.id else { return }
        try? appDatabase?.playlists.duplicate(playlistId: id, newName: "\(playlist.name) Copy")
        loadPlaylists()
    }

    private func setVisibility(of item: SidebarItem, visible: Bool) {
        guard let index = configuration.entries.firstIndex(where: { $0.item == item }) else { return }
        configuration.entries[index].isVisible = visible
        if !visible && selectedItem == item {
            selectedItem = configuration.visibleItems.first
        }
    }

    /// Map a move in the visible-only list back to the full entries array.
    private func moveVisibleItems(from source: IndexSet, to destination: Int) {
        var visible = configuration.visibleItems
        visible.move(fromOffsets: source, toOffset: destination)

        var newEntries: [SidebarConfiguration.Entry] = []
        let hiddenEntries = configuration.entries.filter { !$0.isVisible }

        var hiddenAfter: [SidebarItem: [SidebarConfiguration.Entry]] = [:]
        var hiddenBefore: [SidebarConfiguration.Entry] = []
        var lastVisible: SidebarItem?
        for entry in configuration.entries {
            if entry.isVisible {
                lastVisible = entry.item
            } else {
                if let lv = lastVisible {
                    hiddenAfter[lv, default: []].append(entry)
                } else {
                    hiddenBefore.append(entry)
                }
            }
        }

        newEntries.append(contentsOf: hiddenBefore)
        for item in visible {
            newEntries.append(SidebarConfiguration.Entry(item: item, isVisible: true))
            if let trailing = hiddenAfter[item] {
                newEntries.append(contentsOf: trailing)
            }
        }

        configuration.entries = newEntries
    }
}

// MARK: - Edit Sidebar Sheet

struct EditSidebarSheet: View {
    @Binding var configuration: SidebarConfiguration
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Sidebar")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            // Item list
            List {
                ForEach($configuration.entries) { $entry in
                    HStack {
                        Toggle(isOn: $entry.isVisible) {
                            Label(entry.item.label, systemImage: entry.item.systemImage)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .onMove { source, destination in
                    configuration.entries.move(fromOffsets: source, toOffset: destination)
                }
            }

            Divider()

            // Footer
            HStack {
                Button("Reset to Default") {
                    configuration = .default
                }
                Spacer()
            }
            .padding()
        }
        .frame(width: 320, height: 380)
    }
}
