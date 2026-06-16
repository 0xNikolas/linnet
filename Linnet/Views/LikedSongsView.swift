import SwiftUI
import LinnetLibrary
import GRDB

struct LikedSongsView: View {
    @Environment(\.appDatabase) private var appDatabase
    @Binding var highlightedTrackID: Int64?
    @AppStorage("likedSortOption") private var sortOption: TrackSortOption = .title
    @AppStorage("likedSortDirection") private var sortDirection: SortDirection = .ascending
    @State private var query = CachedQuery<[TrackInfo]>(cacheKey: "likedSongs", default: [])
    @State private var searchText = ""

    var body: some View {
        ListPage(
            searchPrompt: "Search liked songs...",
            sortOption: $sortOption,
            sortDirection: $sortDirection,
            searchText: $searchText
        ) {
            SongsListView(tracks: query.value, highlightedTrackID: $highlightedTrackID)
                .navigationTitle("Liked Songs")
        }
        .task {
                guard let db = appDatabase else { return }
                query.activate(
                    in: db.pool,
                    seed: { db in
                        try TrackInfo.fetchAll(db, sql: TrackInfo.baseSQL + """
                             WHERE track.likedStatus = 1
                            ORDER BY track.title COLLATE NOCASE ASC
                            """)
                    },
                    observation: makeObservation()
                )
            }
            .onChange(of: query.value) {
                if searchText.isEmpty { query.persist() }
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
            var sql = TrackInfo.baseSQL + " WHERE track.likedStatus = 1"
            var arguments: [any DatabaseValueConvertible] = []
            if let match = TrackSearch.condition(for: query) {
                sql += " AND " + match.sql
                arguments = match.arguments
            }
            sql += " ORDER BY \(ordering) \(dir)"
            return try TrackInfo.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }
    }

    private func reobserve() {
        guard let db = appDatabase else { return }
        query.reobserve(in: db.pool, observation: makeObservation())
    }
}
