import SwiftUI
import SwiftData
import LinnetLibrary

// MARK: - Grouping Option

enum SongsGrouping: String, CaseIterable, Identifiable {
    case allSongs = "All Songs"
    case byFolder = "By Folder"
    case byArtist = "By Artist"
    case byAlbum = "By Album"

    var id: String { rawValue }
}

// MARK: - Grouped Section Model

struct TrackSection: Identifiable {
    let id: String
    let tooltip: String?
    let tracks: [Track]

    init(id: String, tracks: [Track], tooltip: String? = nil) {
        self.id = id
        self.tracks = tracks
        self.tooltip = tooltip
    }
}

// MARK: - Wrapper View

struct SongsGroupingView: View {
    @Binding var highlightedTrackID: PersistentIdentifier?
    @Query(sort: \Track.title) private var tracks: [Track]
    @AppStorage("songsGrouping") private var grouping: SongsGrouping = .byFolder
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

            SongsListView(
                tracks: filteredTracks,
                sections: grouping == .allSongs ? [] : sections,
                highlightedTrackID: $highlightedTrackID
            )
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
            .frame(maxWidth: 400)

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

        switch grouping {
        case .allSongs:
            sections = []
            return
        case .byArtist:
            let grouped = Dictionary(grouping: source) { $0.artist?.name ?? "Unknown Artist" }
            sections = grouped
                .map { TrackSection(id: $0.key, tracks: sortTracks($0.value)) }
                .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
        case .byAlbum:
            let grouped = Dictionary(grouping: source) { $0.album?.name ?? "Unknown Album" }
            sections = grouped
                .map { TrackSection(id: $0.key, tracks: sortTracks($0.value)) }
                .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
        case .byFolder:
            let grouped = Dictionary(grouping: source) { track -> String in
                URL(filePath: track.filePath).deletingLastPathComponent().path
            }
            sections = grouped
                .map { fullPath, tracks in
                    // Show last 2 path components as display name (e.g. "Artist/Album")
                    let components = fullPath.split(separator: "/")
                    let displayName = components.suffix(2).joined(separator: "/")
                    return TrackSection(id: displayName, tracks: sortTracks(tracks), tooltip: fullPath)
                }
                .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
        }
    }

    private func sortTracks(_ tracks: [Track]) -> [Track] {
        tracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
