import SwiftUI
import LinnetLibrary

struct LikedSongsView: View {
    @Environment(\.appDatabase) private var appDatabase
    @Binding var highlightedTrackID: Int64?
    @AppStorage("likedSortOption") private var sortOption: TrackSortOption = .title
    @AppStorage("likedSortDirection") private var sortDirection: SortDirection = .ascending
    @State private var likedTracks: [TrackInfo] = []

    var body: some View {
        SongsListView(tracks: likedTracks, highlightedTrackID: $highlightedTrackID)
            .navigationTitle("Liked Songs")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    SortFilterMenuButton(sortOption: $sortOption, sortDirection: $sortDirection)
                }
            }
            .task { loadTracks() }
            .onChange(of: sortOption) { _, _ in loadTracks() }
            .onChange(of: sortDirection) { _, _ in loadTracks() }
    }

    private func loadTracks() {
        likedTracks = (try? appDatabase?.tracks.fetchLikedInfo(orderedBy: sortOption.sqlColumn, direction: sortDirection.sql)) ?? []
    }
}
