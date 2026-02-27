import SwiftUI
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
    let tracks: [TrackInfo]

    init(id: String, tracks: [TrackInfo], tooltip: String? = nil) {
        self.id = id
        self.tracks = tracks
        self.tooltip = tooltip
    }
}

// MARK: - Wrapper View

struct SongsGroupingView: View {
    @Binding var highlightedTrackID: Int64?
    @Environment(\.appDatabase) private var appDatabase
    @State private var tracks: [TrackInfo] = []
    @AppStorage("songsGrouping") private var grouping: SongsGrouping = .byFolder
    @AppStorage("songsSortOption") private var sortOption: TrackSortOption = .title
    @AppStorage("songsSortDirection") private var sortDirection: SortDirection = .ascending
    @State private var sections: [TrackSection] = []
    @State private var searchText = ""
    @State private var isSearchPresented = false

    var body: some View {
        SongsListView(
            tracks: tracks,
            sections: grouping == .allSongs ? [] : sections,
            highlightedTrackID: $highlightedTrackID
        )
        .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search songs...")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                SortFilterMenuButton(
                    sortOption: $sortOption,
                    sortDirection: $sortDirection
                ) { menu, coordinator in
                    menu.addItem(.separator())
                    let header = NSMenuItem(title: "Group By", action: nil, keyEquivalent: "")
                    header.isEnabled = false
                    menu.addItem(header)
                    for option in SongsGrouping.allCases {
                        let item = NSMenuItem(
                            title: option.rawValue,
                            action: #selector(type(of: coordinator).selectExtra(_:)),
                            keyEquivalent: ""
                        )
                        item.target = coordinator
                        item.state = grouping == option ? .on : .off
                        item.representedObject = { [self] in
                            grouping = option
                        } as () -> Void
                        menu.addItem(item)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            isSearchPresented = true
        }
        .task { loadData() }
        .onChange(of: grouping) { _, _ in loadData() }
        .onChange(of: sortOption) { _, _ in loadData() }
        .onChange(of: sortDirection) { _, _ in loadData() }
        .onChange(of: searchText) { _, _ in loadData() }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appDatabase else { return }
        let query = searchText.isEmpty ? nil : searchText
        let column = sortOption.sqlColumn
        let dir = sortDirection.sql

        switch grouping {
        case .allSongs:
            if let q = query {
                tracks = (try? db.tracks.searchAllInfo(query: q)) ?? []
            } else {
                tracks = (try? db.tracks.fetchAllInfo(orderedBy: column, direction: dir)) ?? []
            }
            sections = []

        case .byArtist:
            let grouped = (try? db.tracks.fetchInfoGroupedByArtist(searchQuery: query)) ?? []
            sections = grouped.map { TrackSection(id: $0.sectionName, tracks: $0.tracks) }
            tracks = grouped.flatMap { $0.tracks }

        case .byAlbum:
            let grouped = (try? db.tracks.fetchInfoGroupedByAlbum(searchQuery: query)) ?? []
            sections = grouped.map { TrackSection(id: $0.sectionName, tracks: $0.tracks) }
            tracks = grouped.flatMap { $0.tracks }

        case .byFolder:
            let grouped = (try? db.tracks.fetchInfoGroupedByFolder(searchQuery: query)) ?? []
            sections = grouped.map { group in
                let components = group.sectionName.split(separator: "/")
                let displayName = components.suffix(2).joined(separator: "/")
                return TrackSection(id: displayName, tracks: group.tracks, tooltip: group.sectionName)
            }
            tracks = grouped.flatMap { $0.tracks }
        }
    }
}
