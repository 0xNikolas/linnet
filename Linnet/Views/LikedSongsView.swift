import SwiftUI
import LinnetLibrary
import GRDB

// File-level cache -- survives SwiftUI view lifecycle
private nonisolated(unsafe) var _likedSongsCache: [TrackInfo]?

struct LikedSongsView: View {
    @Environment(\.appDatabase) private var appDatabase
    @Binding var highlightedTrackID: Int64?
    @AppStorage("likedSortOption") private var sortOption: TrackSortOption = .title
    @AppStorage("likedSortDirection") private var sortDirection: SortDirection = .ascending
    @State private var observer: DatabaseObserver<[TrackInfo]>?
    @State private var searchText = ""

    var body: some View {
        ListPage(
            searchPrompt: "Search liked songs...",
            sortOption: $sortOption,
            sortDirection: $sortDirection,
            searchText: $searchText
        ) {
            SongsListView(tracks: observer?.value ?? [], highlightedTrackID: $highlightedTrackID)
                .navigationTitle("Liked Songs")
        }
        .task {
                guard let db = appDatabase else { return }
                let initial = _likedSongsCache ?? (
                    (try? db.pool.read { db in
                        try TrackInfo.fetchAll(db, sql: """
                            SELECT
                                track.*,
                                artist.name AS artistName,
                                album.name AS albumName
                            FROM track
                            LEFT JOIN artist ON track.artistId = artist.id
                            LEFT JOIN album ON track.albumId = album.id
                            WHERE track.likedStatus = 1
                            ORDER BY track.title COLLATE NOCASE ASC
                            """)
                    }) ?? []
                )
                observer = DatabaseObserver(
                    initial: initial,
                    in: db.pool,
                    observation: makeObservation()
                )
            }
            .onChange(of: observer?.value) {
                if searchText.isEmpty {
                    _likedSongsCache = observer?.value
                }
            }
            .onChange(of: sortOption) { _, _ in reobserve() }
            .onChange(of: sortDirection) { _, _ in reobserve() }
            .onChange(of: searchText) { _, _ in reobserve() }
    }

    private func makeObservation() -> ValueObservation<ValueReducers.Fetch<[TrackInfo]>> {
        let ordering = sortOption.sqlColumn
        let dir = sortDirection.sql
        let query = searchText.isEmpty ? nil : searchText
        return ValueObservation.tracking { db in
            var sql = """
                SELECT
                    track.*,
                    artist.name AS artistName,
                    album.name AS albumName
                FROM track
                LEFT JOIN artist ON track.artistId = artist.id
                LEFT JOIN album ON track.albumId = album.id
                WHERE track.likedStatus = 1
                """
            var arguments: [any DatabaseValueConvertible] = []
            if let query {
                let likePattern = "%\(query)%"
                if let ftsQuery = sanitizedFTSQuery(query) {
                    sql += """

                        AND (track.id IN (SELECT rowid FROM trackFts WHERE trackFts MATCH ?) OR track.title LIKE ? OR artist.name LIKE ? OR album.name LIKE ?)
                        """
                    arguments = [ftsQuery, likePattern, likePattern, likePattern]
                } else {
                    sql += """

                        AND (track.title LIKE ? OR artist.name LIKE ? OR album.name LIKE ?)
                        """
                    arguments = [likePattern, likePattern, likePattern]
                }
            }
            sql += "\nORDER BY \(ordering) \(dir)"
            return try TrackInfo.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }
    }

    private func reobserve() {
        guard let db = appDatabase else { return }
        observer?.reobserve(in: db.pool, observation: makeObservation())
    }
}
