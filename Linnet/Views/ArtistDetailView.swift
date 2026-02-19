import SwiftUI

struct ArtistDetailView: View {
    let artistName: String

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
                        Text(artistName)
                            .font(.system(size: 28, weight: .bold))

                        HStack(spacing: 12) {
                            Button("Play") {}
                                .buttonStyle(.borderedProminent)
                            Button("Shuffle") {}
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(20)

                // Albums section
                Text("Albums")
                    .font(.headline)
                    .padding(.horizontal, 20)

                let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(1...3, id: \.self) { i in
                        AlbumCard(name: "Album \(i)", artist: artistName, artwork: nil)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}
