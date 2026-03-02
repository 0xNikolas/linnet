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

// MARK: - FTS5 helper (mirrors TrackRepository)

private func sanitizedFTSQuery(_ query: String) -> String? {
    let tokens = query
        .components(separatedBy: .whitespaces)
        .map { $0.filter { $0.isLetter || $0.isNumber } }
        .filter { !$0.isEmpty }
    guard !tokens.isEmpty else { return nil }
    return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
}

// MARK: - Wrapper View

struct SongsGroupingView: View {
    @Binding var highlightedTrackID: Int64?
    @Environment(\.appDatabase) private var appDatabase
    @State private var observer: DatabaseObserver<SongsData>?
    @AppStorage("songsGrouping") private var grouping: SongsGrouping = .byFolder
    @AppStorage("songsSortOption") private var sortOption: TrackSortOption = .title
    @AppStorage("songsSortDirection") private var sortDirection: SortDirection = .ascending
    @State private var searchText = ""
    @State private var isSearchPresented = false

    private var tracks: [TrackInfo] { observer?.value.tracks ?? [] }
    private var sections: [TrackSection] { observer?.value.sections ?? [] }

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
        .task {
            guard let db = appDatabase else { return }
            observer = DatabaseObserver(
                initial: SongsData(tracks: [], sections: []),
                in: db.pool,
                observation: makeObservation()
            )
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
                let tracks: [TrackInfo]
                if let q = query {
                    tracks = try fetchSearchTracks(db: db, query: q)
                } else {
                    let sql = """
                        SELECT
                            track.*,
                            artist.name AS artistName,
                            album.name AS albumName
                        FROM track
                        LEFT JOIN artist ON track.artistId = artist.id
                        LEFT JOIN album ON track.albumId = album.id
                        ORDER BY \(column) \(dir)
                        """
                    tracks = try TrackInfo.fetchAll(db, sql: sql)
                }
                return SongsData(tracks: tracks, sections: [])

            case .byArtist:
                let (tracks, sections) = try fetchGroupedByArtist(db: db, searchQuery: query)
                return SongsData(tracks: tracks, sections: sections)

            case .byAlbum:
                let (tracks, sections) = try fetchGroupedByAlbum(db: db, searchQuery: query)
                return SongsData(tracks: tracks, sections: sections)

            case .byFolder:
                let (tracks, sections) = try fetchGroupedByFolder(db: db, searchQuery: query)
                return SongsData(tracks: tracks, sections: sections)
            }
        }
    }

    private func reobserve() {
        guard let db = appDatabase else { return }
        observer?.reobserve(in: db.pool, observation: makeObservation())
    }

}

// MARK: - SQL helpers (free functions to avoid MainActor isolation in ValueObservation closures)

private func fetchSearchTracks(db: Database, query: String) throws -> [TrackInfo] {
    let likePattern = "%\(query)%"
    if let ftsQuery = sanitizedFTSQuery(query) {
        let sql = """
            SELECT DISTINCT
                track.*,
                artist.name AS artistName,
                album.name AS albumName
            FROM track
            LEFT JOIN artist ON track.artistId = artist.id
            LEFT JOIN album ON track.albumId = album.id
            LEFT JOIN trackFts ON trackFts.rowid = track.id
            WHERE trackFts MATCH ?
               OR track.title LIKE ?
               OR artist.name LIKE ?
               OR album.name LIKE ?
            ORDER BY track.title COLLATE NOCASE
            LIMIT 200
            """
        return try TrackInfo.fetchAll(db, sql: sql, arguments: [ftsQuery, likePattern, likePattern, likePattern])
    } else {
        let sql = """
            SELECT DISTINCT
                track.*,
                artist.name AS artistName,
                album.name AS albumName
            FROM track
            LEFT JOIN artist ON track.artistId = artist.id
            LEFT JOIN album ON track.albumId = album.id
            WHERE track.title LIKE ?
               OR artist.name LIKE ?
               OR album.name LIKE ?
            ORDER BY track.title COLLATE NOCASE
            LIMIT 200
            """
        return try TrackInfo.fetchAll(db, sql: sql, arguments: [likePattern, likePattern, likePattern])
    }
}

private func appendSearchWhereClause(sql: inout String, arguments: inout [any DatabaseValueConvertible], searchQuery: String?) {
    guard let query = searchQuery, !query.isEmpty else { return }
    let likePattern = "%\(query)%"
    if let ftsQuery = sanitizedFTSQuery(query) {
        sql += """

            LEFT JOIN trackFts ON trackFts.rowid = track.id
            WHERE trackFts MATCH ? OR track.title LIKE ? OR artist.name LIKE ? OR album.name LIKE ?
            """
        arguments = [ftsQuery, likePattern, likePattern, likePattern]
    } else {
        sql += """

            WHERE track.title LIKE ? OR artist.name LIKE ? OR album.name LIKE ?
            """
        arguments = [likePattern, likePattern, likePattern]
    }
}

private func fetchGroupedByArtist(db: Database, searchQuery: String?) throws -> ([TrackInfo], [TrackSection]) {
    var sql = """
        SELECT
            track.*,
            artist.name AS artistName,
            album.name AS albumName
        FROM track
        LEFT JOIN artist ON track.artistId = artist.id
        LEFT JOIN album ON track.albumId = album.id
        """
    var arguments: [any DatabaseValueConvertible] = []
    appendSearchWhereClause(sql: &sql, arguments: &arguments, searchQuery: searchQuery)
    sql += " ORDER BY COALESCE(artist.name, 'Unknown Artist') COLLATE NOCASE, track.title COLLATE NOCASE"

    let tracks = try TrackInfo.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
    let sections = groupTracksByKey(tracks) { $0.artistName ?? "Unknown Artist" }
    return (tracks, sections)
}

private func fetchGroupedByAlbum(db: Database, searchQuery: String?) throws -> ([TrackInfo], [TrackSection]) {
    var sql = """
        SELECT
            track.*,
            artist.name AS artistName,
            album.name AS albumName
        FROM track
        LEFT JOIN artist ON track.artistId = artist.id
        LEFT JOIN album ON track.albumId = album.id
        """
    var arguments: [any DatabaseValueConvertible] = []
    appendSearchWhereClause(sql: &sql, arguments: &arguments, searchQuery: searchQuery)
    sql += " ORDER BY COALESCE(album.name, 'Unknown Album') COLLATE NOCASE, track.title COLLATE NOCASE"

    let tracks = try TrackInfo.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
    let sections = groupTracksByKey(tracks) { $0.albumName ?? "Unknown Album" }
    return (tracks, sections)
}

private func fetchGroupedByFolder(db: Database, searchQuery: String?) throws -> ([TrackInfo], [TrackSection]) {
    var sql = """
        SELECT
            track.*,
            artist.name AS artistName,
            album.name AS albumName
        FROM track
        LEFT JOIN artist ON track.artistId = artist.id
        LEFT JOIN album ON track.albumId = album.id
        """
    var arguments: [any DatabaseValueConvertible] = []
    appendSearchWhereClause(sql: &sql, arguments: &arguments, searchQuery: searchQuery)
    sql += " ORDER BY track.filePath COLLATE NOCASE"

    let tracks = try TrackInfo.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))

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
