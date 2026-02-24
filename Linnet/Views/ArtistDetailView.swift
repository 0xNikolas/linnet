import SwiftUI
import LinnetLibrary

struct ArtistDetailView: View {
    let artist: Artist
    @Environment(PlayerViewModel.self) private var player

    private var allTracks: [Track] {
        artist.tracks.sorted { lhs, rhs in
            let lhsYear = lhs.album?.year ?? 0
            let rhsYear = rhs.album?.year ?? 0
            if lhsYear != rhsYear { return lhsYear > rhsYear }
            let lhsAlbum = lhs.album?.name ?? ""
            let rhsAlbum = rhs.album?.name ?? ""
            if lhsAlbum != rhsAlbum { return lhsAlbum < rhsAlbum }
            if lhs.discNumber != rhs.discNumber { return lhs.discNumber < rhs.discNumber }
            return lhs.trackNumber < rhs.trackNumber
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hero
                HStack(spacing: 16) {
                    Circle()
                        .fill(.quaternary)
                        .frame(width: 120, height: 120)
                        .overlay {
                            Image(systemName: "music.mic")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                        }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(artist.name)
                            .font(.system(size: 28, weight: .bold))

                        Text("\(artist.albums.count) albums, \(artist.tracks.count) songs")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)

                        HStack(spacing: 12) {
                            Button("Play") {
                                if let first = allTracks.first {
                                    player.playTrack(first, queue: allTracks, startingAt: 0)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(allTracks.isEmpty)

                            Button("Shuffle") {
                                let shuffled = allTracks.shuffled()
                                if let first = shuffled.first {
                                    player.playTrack(first, queue: shuffled, startingAt: 0)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(allTracks.isEmpty)
                        }
                    }
                }
                .padding(20)

                // Albums section
                if !artist.albums.isEmpty {
                    Text("Albums")
                        .font(.headline)
                        .padding(.horizontal, 20)

                    let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(artist.albums.sorted(by: { ($0.year ?? Int.min) > ($1.year ?? Int.min) })) { album in
                            NavigationLink(value: album) {
                                AlbumCard(
                                    name: album.name,
                                    artist: artist.name,
                                    artwork: album.artworkData.flatMap { NSImage(data: $0) }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}
