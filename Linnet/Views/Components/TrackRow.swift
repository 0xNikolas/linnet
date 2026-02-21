import SwiftUI

struct TrackRow: View {
    let number: Int
    let title: String
    let artist: String
    let duration: String
    let isPlaying: Bool

    init(number: Int, title: String, artist: String, duration: String, isPlaying: Bool = false) {
        self.number = number
        self.title = title
        self.artist = artist
        self.duration = duration
        self.isPlaying = isPlaying
    }

    var body: some View {
        HStack {
            if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tint)
                    .frame(width: 30, alignment: .trailing)
            } else {
                Text("\(number)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }

            Text(title)
                .font(.system(size: 13, weight: isPlaying ? .semibold : .regular))

            Spacer()

            Text(artist)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text(duration)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}
