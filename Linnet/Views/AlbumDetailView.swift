import SwiftUI

struct AlbumDetailView: View {
    let albumName: String
    let artistName: String

    // Placeholder tracks
    private let tracks = [
        (number: 1, title: "First Track", duration: "3:42"),
        (number: 2, title: "Second Track", duration: "4:15"),
        (number: 3, title: "Third Track", duration: "2:58"),
        (number: 4, title: "Fourth Track", duration: "5:01"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(alignment: .bottom, spacing: 20) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .frame(width: 200, height: 200)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                        }
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(albumName)
                            .font(.system(size: 28, weight: .bold))
                        Text(artistName)
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                        Text("\(tracks.count) songs")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)

                        HStack(spacing: 12) {
                            Button("Play") {}
                                .buttonStyle(.borderedProminent)
                                .tint(.accentColor)
                            Button("Shuffle") {}
                                .buttonStyle(.bordered)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(20)

                Divider()

                // Track list
                ForEach(tracks, id: \.number) { track in
                    HStack {
                        Text("\(track.number)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)

                        Text(track.title)
                            .font(.system(size: 13))

                        Spacer()

                        Text(track.duration)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())

                    Divider()
                        .padding(.leading, 60)
                }
            }
        }
    }
}
