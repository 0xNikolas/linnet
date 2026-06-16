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
                do { try appDatabase?.tracks.updateLikedStatus(filePath: track.filePath, status: newStatus) } catch { Log.database.error("Failed to update liked status for \(track.filePath): \(error)") }
            }
        } label: { Label(allLiked ? "Remove Like" : "Like", systemImage: allLiked ? "bolt.fill" : "bolt") }
        Button {
            let newStatus = allDisliked ? 0 : -1
            for track in tracks {
                do { try appDatabase?.tracks.updateLikedStatus(filePath: track.filePath, status: newStatus) } catch { Log.database.error("Failed to update liked status for \(track.filePath): \(error)") }
            }
        } label: { Label(allDisliked ? "Remove Dislike" : "Dislike", systemImage: allDisliked ? "bolt.slash.fill" : "bolt.slash") }
    }
}
