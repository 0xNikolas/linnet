import SwiftUI
import SwiftData
import LinnetLibrary

// MARK: - Grouping Option

enum SongsGrouping: String, CaseIterable, Identifiable {
    case allSongs = "All Songs"
    case byArtist = "By Artist"
    case byAlbum = "By Album"
    case byFolder = "By Folder"
    case byGenre = "By Genre"

    var id: String { rawValue }
}

// MARK: - Grouped Section Model

private struct TrackSection: Identifiable {
    let id: String
    let tracks: [Track]
}

// MARK: - Time Formatting

private func formatTime(_ seconds: Double) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", mins, secs)
}

// MARK: - Wrapper View

struct SongsGroupingView: View {
    @Binding var highlightedTrackID: PersistentIdentifier?
    @Query(sort: \Track.title) private var tracks: [Track]
    @AppStorage("songsGrouping") private var grouping: SongsGrouping = .allSongs
    @State private var sections: [TrackSection] = []
    @State private var searchText = ""
    @State private var isSearchPresented = false

    private var filteredTracks: [Track] {
        if searchText.isEmpty { return tracks }
        let query = searchText
        return tracks.filter { track in
            track.title.searchContains(query) ||
            (track.artist?.name ?? "").searchContains(query) ||
            (track.album?.name ?? "").searchContains(query) ||
            (track.genre ?? "").searchContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            groupingPicker
            Divider()

            if grouping == .allSongs {
                SongsListView(tracks: filteredTracks, highlightedTrackID: $highlightedTrackID)
            } else {
                GroupedSongsView(sections: sections)
            }
        }
        .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search songs...")
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            isSearchPresented = true
        }
        .onChange(of: tracks, initial: true) { _, _ in
            rebuildSections()
        }
        .onChange(of: grouping) { _, _ in
            rebuildSections()
        }
        .onChange(of: searchText) { _, _ in
            rebuildSections()
        }
    }

    // MARK: - Picker

    private var groupingPicker: some View {
        HStack {
            Picker("Group by", selection: $grouping) {
                ForEach(SongsGrouping.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 500)

            Spacer()

            Text("\(filteredTracks.count) songs")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Section Building

    private func rebuildSections() {
        guard grouping != .allSongs else {
            sections = []
            return
        }
        let source = filteredTracks
        let grouped: [String: [Track]]
        switch grouping {
        case .allSongs:
            sections = []
            return
        case .byArtist:
            grouped = Dictionary(grouping: source) { $0.artist?.name ?? "Unknown Artist" }
        case .byAlbum:
            grouped = Dictionary(grouping: source) { $0.album?.name ?? "Unknown Album" }
        case .byFolder:
            grouped = Dictionary(grouping: source) { track in
                let url = URL(filePath: track.filePath)
                return url.deletingLastPathComponent().lastPathComponent
            }
        case .byGenre:
            grouped = Dictionary(grouping: source) { $0.genre ?? "Unknown Genre" }
        }
        sections = grouped
            .map { TrackSection(id: $0.key, tracks: $0.value.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) }
            .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }
}

// MARK: - Grouped Songs View

private struct GroupedSongsView: View {
    let sections: [TrackSection]
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTrackIDs: Set<PersistentIdentifier> = []
    @AppStorage("nowPlayingBarHeight") private var barHeight: Double = 56

    /// Flattened list of all tracks across sections, used for building the playback queue.
    private var allTracks: [Track] {
        sections.flatMap(\.tracks)
    }

    var body: some View {
        if sections.isEmpty {
            ContentUnavailableView("No Songs", systemImage: "music.note",
                                   description: Text("Add a music folder in Settings to get started."))
        } else {
            List(selection: $selectedTrackIDs) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.tracks) { track in
                            GroupedTrackRow(track: track)
                                .tag(track.persistentModelID)
                        }
                    } header: {
                        Text(section.id)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .padding(.vertical, 2)
                    }
                }
            }
            .listStyle(.inset)
            .environment(\.defaultMinListRowHeight, 28)
            .contentMargins(.bottom, barHeight + 20, for: .scrollContent)
            .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
                contextMenuContent(for: ids)
            } primaryAction: { ids in
                if let id = ids.first {
                    let flat = allTracks
                    if let index = flat.firstIndex(where: { $0.persistentModelID == id }) {
                        player.playTrack(flat[index], queue: flat, startingAt: index)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenuContent(for ids: Set<PersistentIdentifier>) -> some View {
        if let id = ids.first {
            let flat = allTracks
            if let index = flat.firstIndex(where: { $0.persistentModelID == id }) {
                let track = flat[index]
                Button("Play") {
                    player.playTrack(track, queue: flat, startingAt: index)
                }
                Button("Play Next") {
                    player.addNext(track)
                }
                Button("Play Later") {
                    player.addLater(track)
                }
                AddToPlaylistMenu(tracks: [track])
                Divider()
                Button("Remove from Library", role: .destructive) {
                    for selectedID in ids {
                        if let t = flat.first(where: { $0.persistentModelID == selectedID }) {
                            removeTrack(t)
                        }
                    }
                }
            }
        }
    }

    private func removeTrack(_ track: Track) {
        let album = track.album
        let artist = track.artist
        modelContext.delete(track)
        if let album, album.tracks.isEmpty {
            modelContext.delete(album)
        }
        if let artist, artist.tracks.isEmpty {
            modelContext.delete(artist)
        }
        try? modelContext.save()
    }
}

// MARK: - Grouped Track Row

private struct GroupedTrackRow: View {
    let track: Track

    var body: some View {
        HStack(spacing: 0) {
            Text("\(track.trackNumber)")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(width: 30, alignment: .trailing)
                .padding(.trailing, 8)

            Text(track.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .frame(minWidth: 120, alignment: .leading)

            Spacer(minLength: 12)

            Text(track.artist?.name ?? "Unknown")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 100, alignment: .leading)

            Spacer(minLength: 12)

            Text(track.album?.name ?? "Unknown")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 100, alignment: .leading)

            Spacer(minLength: 12)

            Text(formatTime(track.duration))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }
}
