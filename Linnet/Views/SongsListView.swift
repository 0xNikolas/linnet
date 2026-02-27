import SwiftUI
import AppKit
import LinnetLibrary

// MARK: - Native AppKit Tooltip

private struct TooltipView: NSViewRepresentable {
    let tooltip: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.toolTip = tooltip
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.toolTip = tooltip
    }
}

private extension View {
    func toolTip(_ tip: String?) -> some View {
        if let tip, !tip.isEmpty {
            return AnyView(self.overlay(TooltipView(tooltip: tip)))
        }
        return AnyView(self)
    }
}

private func formatTime(_ seconds: Double) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", mins, secs)
}

private func formatSampleRate(_ hz: Int) -> String {
    if hz % 1000 == 0 {
        return "\(hz / 1000) kHz"
    }
    return String(format: "%.1f kHz", Double(hz) / 1000.0)
}

private func channelLabel(_ count: Int) -> String {
    switch count {
    case 1: return "Mono"
    case 2: return "Stereo"
    default: return "\(count)ch"
    }
}

private func formatFileSize(_ bytes: Int64) -> String {
    if bytes < 1_048_576 {
        return "\(bytes / 1024) KB"
    }
    return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
}

// MARK: - SongsListView (owns player environment + library mutations)

struct SongsListView: View {
    let tracks: [TrackInfo]
    var sections: [TrackSection] = []
    @Binding var highlightedTrackID: Int64?
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.appDatabase) private var appDatabase

    var body: some View {
        if tracks.isEmpty {
            ContentUnavailableView("No Songs", systemImage: "music.note", description: Text("Add a music folder in Settings to get started."))
        } else {
            SongsTableView(
                tracks: tracks,
                sections: sections,
                highlightedTrackID: $highlightedTrackID,
                onPlay: { track, queue, index in
                    player.playTrack(track, queue: queue, startingAt: index)
                },
                onPlayNext: { track in
                    player.addNext(track)
                },
                onPlayLater: { track in
                    player.addLater(track)
                },
                onRemove: { trackIDs in
                    removeTracks(ids: trackIDs)
                }
            )
        }
    }

    private func removeTracks(ids: Set<Int64>) {
        guard let db = appDatabase else { return }
        for id in ids {
            try? db.tracks.delete(id: id)
        }
        try? db.albums.deleteOrphaned()
        try? db.artists.deleteOrphaned()
    }
}

// MARK: - SongsTableView (no player environment -- immune to timer-driven redraws)

private struct SongsTableView: View {
    let tracks: [TrackInfo]
    let sections: [TrackSection]
    @Binding var highlightedTrackID: Int64?
    let onPlay: (TrackInfo, [TrackInfo], Int) -> Void
    let onPlayNext: (TrackInfo) -> Void
    let onPlayLater: (TrackInfo) -> Void
    let onRemove: (Set<Int64>) -> Void

    @State private var selectedTrackIDs: Set<Int64> = []
    @State private var sortOrder = [KeyPathComparator(\TrackInfo.title)]
    @State private var sortedTracks: [TrackInfo] = []
    @State private var sortedSections: [TrackSection] = []
    @SceneStorage("SongsTableConfig") private var columnCustomization: TableColumnCustomization<TrackInfo>

    @State private var scrollTarget: Int64?
    @State private var expandedSections: Set<String> = []

    private var isGrouped: Bool { !sections.isEmpty }

    private var playbackQueue: [TrackInfo] {
        isGrouped ? sortedSections.flatMap(\.tracks) : sortedTracks
    }

    var body: some View {
        ScrollViewReader { proxy in
            songsTable
                .tableStyle(.inset)
                .contextMenu(forSelectionType: Int64.self) { ids in
                    contextMenuContent(for: ids)
                } primaryAction: { ids in
                    let queue = playbackQueue
                    if let id = ids.first, let index = queue.firstIndex(where: { $0.id == id }) {
                        onPlay(queue[index], queue, index)
                    }
                }
                .onChange(of: tracks, initial: true) { _, newTracks in
                    sortedTracks = newTracks.sorted(using: sortOrder)
                    rebuildSortedSections()
                    expandedSections.formUnion(sections.map(\.id))
                }
                .onChange(of: sections.map(\.id)) { _, newIDs in
                    rebuildSortedSections()
                    expandedSections.formUnion(newIDs)
                }
                .onChange(of: sortOrder) { _, newOrder in
                    sortedTracks = tracks.sorted(using: newOrder)
                    rebuildSortedSections()
                }
                .onChange(of: highlightedTrackID, initial: true) { _, newID in
                    if let id = newID {
                        selectedTrackIDs = [id]
                        scrollTarget = id
                        highlightedTrackID = nil
                    }
                }
                .onChange(of: scrollTarget) { _, target in
                    if let target {
                        withAnimation {
                            proxy.scrollTo(target, anchor: .center)
                        }
                        scrollTarget = nil
                    }
                }
        }
    }

    @ViewBuilder
    private var songsTable: some View {
        if isGrouped {
            Table(of: TrackInfo.self, selection: $selectedTrackIDs, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
                coreColumns
                metadataColumns
                audioColumns
            } rows: {
                ForEach(sortedSections) { section in
                    Section(isExpanded: Binding(
                        get: { expandedSections.contains(section.id) },
                        set: { expanded in
                            if expanded {
                                expandedSections.insert(section.id)
                            } else {
                                expandedSections.remove(section.id)
                            }
                        }
                    )) {
                        ForEach(section.tracks) { track in
                            TableRow(track)
                        }
                    } header: {
                        Text(section.id)
                            .font(.app(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .padding(.bottom, 4)
                            .toolTip(section.tooltip)
                    }
                }
            }
        } else {
            Table(of: TrackInfo.self, selection: $selectedTrackIDs, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
                coreColumns
                metadataColumns
                audioColumns
            } rows: {
                ForEach(sortedTracks) { track in
                    TableRow(track)
                }
            }
        }
    }

    @TableColumnBuilder<TrackInfo, KeyPathComparator<TrackInfo>>
    private var coreColumns: some TableColumnContent<TrackInfo, KeyPathComparator<TrackInfo>> {
        TableColumn("#", value: \.trackNumber) { track in
            Text("\(track.trackNumber)")
                .font(.app(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 30, ideal: 40, max: 60)
        .customizationID("trackNumber")

        TableColumn("Title", value: \.title) { track in
            HStack(spacing: 4) {
                Text(track.title)
                    .font(.app(size: 13))
                if track.likedStatus == 1 {
                    Image(systemName: "heart.fill")
                        .font(.app(size: 9))
                        .foregroundStyle(.red)
                }
            }
            .opacity(track.likedStatus == -1 ? 0.5 : 1.0)
            .id(track.id)
        }
        .customizationID("title")

        TableColumn("Artist") { track in
            Text(track.artistName ?? "Unknown")
                .font(.app(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 80, ideal: 150)
        .customizationID("artist")

        TableColumn("Album") { track in
            Text(track.albumName ?? "Unknown")
                .font(.app(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 80, ideal: 150)
        .customizationID("album")

        TableColumn("Time", value: \.duration) { track in
            Text(formatTime(track.duration))
                .font(.app(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .width(min: 40, ideal: 55, max: 80)
        .customizationID("time")
    }

    @TableColumnBuilder<TrackInfo, KeyPathComparator<TrackInfo>>
    private var metadataColumns: some TableColumnContent<TrackInfo, KeyPathComparator<TrackInfo>> {
        TableColumn("Genre") { track in
            Text(track.genre ?? "")
                .font(.app(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 60, ideal: 100)
        .customizationID("genre")
        .defaultVisibility(.hidden)

        TableColumn("Year") { track in
            Text(track.year.map { "\($0)" } ?? "")
                .font(.app(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 40, ideal: 60, max: 80)
        .customizationID("year")
        .defaultVisibility(.hidden)

        TableColumn("Plays") { track in
            Text("\(track.playCount)")
                .font(.app(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 40, ideal: 50, max: 70)
        .customizationID("plays")
        .defaultVisibility(.hidden)
    }

    @TableColumnBuilder<TrackInfo, KeyPathComparator<TrackInfo>>
    private var audioColumns: some TableColumnContent<TrackInfo, KeyPathComparator<TrackInfo>> {
        TableColumn("Format") { track in
            Text(track.codec ?? "")
                .font(.app(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 40, ideal: 60, max: 80)
        .customizationID("format")
        .defaultVisibility(.hidden)

        TableColumn("Bitrate") { track in
            Text(track.bitrate.map { "\($0) kbps" } ?? "")
                .font(.app(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 50, ideal: 80, max: 100)
        .customizationID("bitrate")
        .defaultVisibility(.hidden)

        TableColumn("Sample Rate") { track in
            Text(track.sampleRate.map { formatSampleRate($0) } ?? "")
                .font(.app(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 50, ideal: 80, max: 100)
        .customizationID("sampleRate")
        .defaultVisibility(.hidden)

        TableColumn("Channels") { track in
            Text(track.channels.map { channelLabel($0) } ?? "")
                .font(.app(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 40, ideal: 60, max: 80)
        .customizationID("channels")
        .defaultVisibility(.hidden)

        TableColumn("Size") { track in
            Text(track.fileSize.map { formatFileSize($0) } ?? "")
                .font(.app(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 40, ideal: 70, max: 90)
        .customizationID("fileSize")
        .defaultVisibility(.hidden)
    }

    private func rebuildSortedSections() {
        sortedSections = sections.map { section in
            TrackSection(id: section.id, tracks: section.tracks.sorted(using: sortOrder), tooltip: section.tooltip)
        }
    }

    @ViewBuilder
    private func contextMenuContent(for ids: Set<Int64>) -> some View {
        let queue = playbackQueue
        if let id = ids.first, let index = queue.firstIndex(where: { $0.id == id }) {
            let track = queue[index]
            Button { onPlay(track, queue, index) } label: { Label("Play", systemImage: "play") }
            Button { onPlayNext(track) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { onPlayLater(track) } label: { Label("Play Later", systemImage: "text.line.last.and.arrowtriangle.forward") }
            AddToPlaylistMenu(tracks: [track])
            LikeDislikeMenu(tracks: [track])
            Divider()
            if let artistId = track.artistId {
                Button {
                    NotificationCenter.default.post(name: .navigateToArtist, object: nil, userInfo: ["artistId": artistId, "artistName": track.artistName ?? ""])
                } label: { Label("Go to Artist", systemImage: "music.mic") }
            }
            if let albumId = track.albumId {
                Button {
                    NotificationCenter.default.post(name: .navigateToAlbum, object: nil, userInfo: ["albumId": albumId])
                } label: { Label("Go to Album", systemImage: "square.stack") }
            }
            Divider()
            Button(role: .destructive) { onRemove(ids) } label: { Label("Remove from Library", systemImage: "trash") }
        }
    }
}
