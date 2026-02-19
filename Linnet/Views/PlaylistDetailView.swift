import SwiftUI

struct PlaylistDetailView: View {
    let name: String
    @State private var isDropTargeted = false

    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "alac", "wav", "aiff", "aif", "ogg", "wma", "caf", "opus"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 16) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 150, height: 150)
                    .overlay {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Text(name)
                        .font(.system(size: 24, weight: .bold))
                    Text("0 songs")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button("Play") {}
                            .buttonStyle(.borderedProminent)
                        Button("Shuffle") {}
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(20)

            Divider()

            Text("No tracks in this playlist")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let audioURLs = urls.filter { Self.audioExtensions.contains($0.pathExtension.lowercased()) }
            guard !audioURLs.isEmpty else { return false }
            // TODO: Add dropped files to playlist "\(name)" via LibraryManager
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .dropOverlay(isTargeted: isDropTargeted)
    }
}
