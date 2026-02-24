import SwiftUI
import SwiftData
import LinnetLibrary

struct ArtistListView: View {
    @Query(sort: \Artist.name) private var artists: [Artist]

    var body: some View {
        List {
            if artists.isEmpty {
                Text("No artists found")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(artists) { artist in
                    NavigationLink(value: artist) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(.quaternary)
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Image(systemName: "music.mic")
                                        .foregroundStyle(.secondary)
                                }

                            VStack(alignment: .leading) {
                                Text(artist.name)
                                    .font(.system(size: 14))
                                Text("\(artist.albums.count) albums")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}
