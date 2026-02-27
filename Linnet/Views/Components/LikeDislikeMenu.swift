import SwiftUI
import LinnetLibrary

struct LikeDislikeMenu: View {
    let tracks: [TrackInfo]
    @Environment(\.appDatabase) private var appDatabase

    var body: some View {
        let allLiked = tracks.allSatisfy { $0.likedStatus == 1 }
        let allDisliked = tracks.allSatisfy { $0.likedStatus == -1 }

        Button {
            let newStatus = allLiked ? 0 : 1
            for track in tracks {
                try? appDatabase?.tracks.updateLikedStatus(filePath: track.filePath, status: newStatus)
            }
        } label: { Label(allLiked ? "Remove Like" : "Like", systemImage: allLiked ? "heart.slash" : "heart") }
        Button {
            let newStatus = allDisliked ? 0 : -1
            for track in tracks {
                try? appDatabase?.tracks.updateLikedStatus(filePath: track.filePath, status: newStatus)
            }
        } label: { Label(allDisliked ? "Remove Dislike" : "Dislike", systemImage: allDisliked ? "hand.thumbsdown.fill" : "hand.thumbsdown") }
    }
}
