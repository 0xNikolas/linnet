import SwiftUI
import SwiftData
import LinnetLibrary

struct LikedSongsView: View {
    @Query(filter: #Predicate<Track> { $0.likedStatus == 1 }, sort: \Track.title)
    private var likedTracks: [Track]
    @Binding var highlightedTrackID: PersistentIdentifier?

    var body: some View {
        SongsListView(tracks: likedTracks, highlightedTrackID: $highlightedTrackID)
            .navigationTitle("Liked Songs")
    }
}
