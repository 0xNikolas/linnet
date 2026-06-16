import SwiftUI
import LinnetLibrary
import GRDB

// MARK: - Grouping Option

enum SongsGrouping: String, CaseIterable, Identifiable {
    case allSongs = "All Songs"
    case byFolder = "By Folder"
    case byArtist = "By Artist"
    case byAlbum = "By Album"

    var id: String { rawValue }
}

// MARK: - Grouped Section Model

struct TrackSection: Identifiable, Sendable {
    let id: String
    let tooltip: String?
    let tracks: [TrackInfo]

    init(id: String, tracks: [TrackInfo], tooltip: String? = nil) {
        self.id = id
        self.tracks = tracks
        self.tooltip = tooltip
    }
}

// MARK: - Combined data for observation

private struct SongsData: Sendable {
    let tracks: [TrackInfo]
    let sections: [TrackSection]
}

// MARK: - Wrapper View

struct SongsGroupingView: View {
    @Binding var highlightedTrackID: Int64?
    @Environment(\.appDatabase) private var appDatabase
    @State private var songsQuery = CachedQuery<SongsData>(cacheKey: "songs", default: SongsData(tracks: [], sections: []))
    @AppStorage("songsGrouping") private var grouping: SongsGrouping = .byFolder
    @AppStorage("songsSortOption") private var sortOption: TrackSortOption = .title
    @AppStorage("songsSortDirection") private var sortDirection: SortDirection = .ascending
    @State private var searchText = ""

    private var tracks: [TrackInfo] { songsQuery.value.tracks }
    private var sections: [TrackSection] { songsQuery.value.sections }

    var body: some View {
        ListPage(
            searchPrompt: "Search songs...",
            sortOption: $sortOption,
            sortDirection: $sortDirection,
            searchText: $searchText,
            extraMenuBuilder: { menu, coordinator in
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
        ) {
            SongsListView(
                tracks: tracks,
                sections: grouping == .allSongs ? [] : sections,
                highlightedTrackID: $highlightedTrackID
            )
        }
        .task {
            guard let db = appDatabase else { return }
            songsQuery.activate(
                in: db.pool,
                seed: { db in
                    let tracks = try TrackInfo.fetchAll(db, sql: TrackInfo.baseSQL + " ORDER BY track.title COLLATE NOCASE ASC")
                    return SongsData(tracks: tracks, sections: [])
                },
                observation: makeObservation()
            )
        }
        .onChange(of: tracks) {
            if searchText.isEmpty { songsQuery.persist() }
        }
        .onChange(of: grouping) { _, _ in reobserve() }
        .onChange(of: sortOption) { _, _ in reobserve() }
        .onChange(of: sortDirection) { _, _ in reobserve() }
        .onChange(of: searchText) { _, _ in reobserve() }
    }

    // MARK: - Observation

    private func makeObservation() -> ValueObservation<ValueReducers.Fetch<SongsData>> {
        let currentGrouping = grouping
        let column = sortOption.sqlColumn
        let dir = sortDirection.sql
        let search = searchText
        let query = search.isEmpty ? nil : search

        return ValueObservation.tracking { db in
            switch currentGrouping {
            case .allSongs:
                return SongsData(tracks: try fetchAllSongs(db: db, query: query, column: column, dir: dir), sections: [])

            case .byArtist:
                let (tracks, sections) = try fetchGroupedByArtist(db: db, query: query)
                return SongsData(tracks: tracks, sections: sections)

            case .byAlbum:
                let (tracks, sections) = try fetchGroupedByAlbum(db: db, query: query)
                return SongsData(tracks: tracks, sections: sections)

            case .byFolder:
                let (tracks, sections) = try fetchGroupedByFolder(db: db, query: query)
                return SongsData(tracks: tracks, sections: sections)
            }
        }
    }

    private func reobserve() {
        guard let db = appDatabase else { return }
        songsQuery.reobserve(in: db.pool, observation: makeObservation())
    }

}

// MARK: - SQL helpers (free functions to avoid MainActor isolation in ValueObservation closures)

/// `TrackInfo.baseSQL` plus an optional search `WHERE` clause (via `TrackSearch`), a caller-supplied
/// ORDER BY, and an optional LIMIT.
private func fetchOrderedTracks(db: Database, query: String?, orderBy: String, limit: Int? = nil) throws -> [TrackInfo] {
    var sql = TrackInfo.baseSQL
    var arguments: [any DatabaseValueConvertible] = []
    if let match = TrackSearch.condition(for: query) {
        sql += " WHERE " + match.sql
        arguments = match.arguments
    }
    sql += " ORDER BY " + orderBy
    if let limit {
        sql += " LIMIT ?"
        arguments.append(limit)
    }
    return try TrackInfo.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
}

private func fetchAllSongs(db: Database, query: String?, column: SortSQL, dir: String) throws -> [TrackInfo] {
    // Searches are capped and ordered by title; the unfiltered list honours the user's sort.
    query == nil
        ? try fetchOrderedTracks(db: db, query: nil, orderBy: "\(column) \(dir)")
        : try fetchOrderedTracks(db: db, query: query, orderBy: "track.title COLLATE NOCASE", limit: 200)
}

private func fetchGroupedByArtist(db: Database, query: String?) throws -> ([TrackInfo], [TrackSection]) {
    let tracks = try fetchOrderedTracks(
        db: db, query: query,
        orderBy: "COALESCE(artist.name, 'Unknown Artist') COLLATE NOCASE, track.title COLLATE NOCASE"
    )
    return (tracks, groupTracksByKey(tracks) { $0.artistName ?? "Unknown Artist" })
}

private func fetchGroupedByAlbum(db: Database, query: String?) throws -> ([TrackInfo], [TrackSection]) {
    let tracks = try fetchOrderedTracks(
        db: db, query: query,
        orderBy: "COALESCE(album.name, 'Unknown Album') COLLATE NOCASE, track.title COLLATE NOCASE"
    )
    return (tracks, groupTracksByKey(tracks) { $0.albumName ?? "Unknown Album" })
}

private func fetchGroupedByFolder(db: Database, query: String?) throws -> ([TrackInfo], [TrackSection]) {
    let tracks = try fetchOrderedTracks(db: db, query: query, orderBy: "track.filePath COLLATE NOCASE")

    var sectionsList: [TrackSection] = []
    var currentKey = ""
    var currentTracks: [TrackInfo] = []

    for track in tracks {
        let url = URL(fileURLWithPath: track.filePath)
        let key = url.deletingLastPathComponent().path
        if key != currentKey {
            if !currentTracks.isEmpty {
                let components = currentKey.split(separator: "/")
                let displayName = components.suffix(2).joined(separator: "/")
                sectionsList.append(TrackSection(id: displayName, tracks: currentTracks, tooltip: currentKey))
            }
            currentKey = key
            currentTracks = [track]
        } else {
            currentTracks.append(track)
        }
    }
    if !currentTracks.isEmpty {
        let components = currentKey.split(separator: "/")
        let displayName = components.suffix(2).joined(separator: "/")
        sectionsList.append(TrackSection(id: displayName, tracks: currentTracks, tooltip: currentKey))
    }

    return (tracks, sectionsList)
}

/// Group an already-ordered array of tracks by a key function into sections.
private func groupTracksByKey(_ tracks: [TrackInfo], key: (TrackInfo) -> String) -> [TrackSection] {
    var sections: [TrackSection] = []
    var currentKey = ""
    var currentTracks: [TrackInfo] = []

    for track in tracks {
        let k = key(track)
        if k != currentKey {
            if !currentTracks.isEmpty {
                sections.append(TrackSection(id: currentKey, tracks: currentTracks))
            }
            currentKey = k
            currentTracks = [track]
        } else {
            currentTracks.append(track)
        }
    }
    if !currentTracks.isEmpty {
        sections.append(TrackSection(id: currentKey, tracks: currentTracks))
    }

    return sections
}
