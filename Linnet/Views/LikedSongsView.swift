import SwiftUI
import LinnetLibrary
import GRDB

struct LikedSongsView: View {
    @Environment(\.appDatabase) private var appDatabase
    @Binding var highlightedTrackID: Int64?
    @AppStorage("likedSortOption") private var sortOption: TrackSortOption = .title
    @AppStorage("likedSortDirection") private var sortDirection: SortDirection = .ascending
    @State private var observer: DatabaseObserver<[TrackInfo]>?

    var body: some View {
        SongsListView(tracks: observer?.value ?? [], highlightedTrackID: $highlightedTrackID)
            .navigationTitle("Liked Songs")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    SortFilterMenuButton(sortOption: $sortOption, sortDirection: $sortDirection)
                }
            }
            .task {
                guard let db = appDatabase else { return }
                observer = DatabaseObserver(
                    initial: [],
                    in: db.pool,
                    observation: makeObservation()
                )
            }
            .onChange(of: sortOption) { _, _ in reobserve() }
            .onChange(of: sortDirection) { _, _ in reobserve() }
    }

    private func makeObservation() -> ValueObservation<ValueReducers.Fetch<[TrackInfo]>> {
        let ordering = sortOption.sqlColumn
        let dir = sortDirection.sql
        return ValueObservation.tracking { db in
            let sql = """
                SELECT
                    track.*,
                    artist.name AS artistName,
                    album.name AS albumName
                FROM track
                LEFT JOIN artist ON track.artistId = artist.id
                LEFT JOIN album ON track.albumId = album.id
                WHERE track.likedStatus = 1
                ORDER BY \(ordering) \(dir)
                """
            return try TrackInfo.fetchAll(db, sql: sql)
        }
    }

    private func reobserve() {
        guard let db = appDatabase else { return }
        observer?.reobserve(in: db.pool, observation: makeObservation())
    }
}
