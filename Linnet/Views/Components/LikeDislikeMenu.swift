import SwiftUI
import LinnetLibrary

struct LikeDislikeMenu: View {
    let tracks: [Track]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let allLiked = tracks.allSatisfy { $0.likedStatus == 1 }
        let allDisliked = tracks.allSatisfy { $0.likedStatus == -1 }

        Button(allLiked ? "Remove Like" : "Like") {
            let newStatus = allLiked ? 0 : 1
            for track in tracks { track.likedStatus = newStatus }
            try? modelContext.save()
        }
        Button(allDisliked ? "Remove Dislike" : "Dislike") {
            let newStatus = allDisliked ? 0 : -1
            for track in tracks { track.likedStatus = newStatus }
            try? modelContext.save()
        }
    }
}
