import SwiftUI

struct QueuePanel: View {
    @Binding var isShowing: Bool

    private let upNext = [
        (title: "Next Song", artist: "Artist B"),
        (title: "Another Track", artist: "Artist C"),
        (title: "More Music", artist: "Artist A"),
    ]

    private let history = [
        (title: "Previous Song", artist: "Artist A"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Queue")
                    .font(.headline)
                Spacer()
                Button("Clear") {}
                    .buttonStyle(.plain)
                    .foregroundStyle(.accent)
                Button(action: { isShowing = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Now Playing
                    Section {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.quaternary)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading) {
                                Text("Current Song")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Artist A")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal)
                    } header: {
                        Text("Now Playing")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal)
                    }

                    // Up Next
                    Section {
                        ForEach(upNext, id: \.title) { track in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.quaternary)
                                    .frame(width: 36, height: 36)
                                VStack(alignment: .leading) {
                                    Text(track.title)
                                        .font(.system(size: 13))
                                    Text(track.artist)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    } header: {
                        Text("Up Next")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal)
                    }

                    // History
                    Section {
                        ForEach(history, id: \.title) { track in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.quaternary)
                                    .frame(width: 36, height: 36)
                                VStack(alignment: .leading) {
                                    Text(track.title)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                    Text(track.artist)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    } header: {
                        Text("History")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        }
        .frame(width: 300)
        .background(.ultraThinMaterial)
    }
}
