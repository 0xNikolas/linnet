import SwiftUI
import SwiftData
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
    let tracks: [Track]
    var sections: [TrackSection] = []
    @Binding var highlightedTrackID: PersistentIdentifier?
    @Environment(PlayerViewModel.self) private var player
    @Environment(\.modelContext) private var modelContext

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

    private func removeTracks(ids: Set<PersistentIdentifier>) {
        for id in ids {
            if let track = tracks.first(where: { $0.id == id }) {
                let album = track.album
                let artist = track.artist
                modelContext.delete(track)
                if let album, album.tracks.isEmpty {
                    modelContext.delete(album)
                }
                if let artist, artist.tracks.isEmpty {
                    modelContext.delete(artist)
                }
            }
        }
        try? modelContext.save()
    }
}

// MARK: - SongsTableView (no player environment -- immune to timer-driven redraws)

private struct SongsTableView: View {
    let tracks: [Track]
    let sections: [TrackSection]
    @Binding var highlightedTrackID: PersistentIdentifier?
    let onPlay: (Track, [Track], Int) -> Void
    let onPlayNext: (Track) -> Void
    let onPlayLater: (Track) -> Void
    let onRemove: (Set<PersistentIdentifier>) -> Void

    @State private var selectedTrackIDs: Set<PersistentIdentifier> = []
    @State private var sortOrder = [KeyPathComparator(\Track.title)]
    @State private var sortedTracks: [Track] = []
    @State private var sortedSections: [TrackSection] = []
    @SceneStorage("SongsTableConfig") private var columnCustomization: TableColumnCustomization<Track>

    /// Lightweight cache of relationship data to avoid repeated SwiftData faulting during scroll.
    @State private var artistNames: [PersistentIdentifier: String] = [:]
    @State private var albumNames: [PersistentIdentifier: String] = [:]

    @State private var scrollTarget: PersistentIdentifier?
    @State private var expandedSections: Set<String> = []

    private var isGrouped: Bool { !sections.isEmpty }

    /// Flat playback queue respecting current display order.
    private var playbackQueue: [Track] {
        isGrouped ? sortedSections.flatMap(\.tracks) : sortedTracks
    }

    var body: some View {
        ScrollViewReader { proxy in
            songsTable
                .tableStyle(.inset)
                .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
                    contextMenuContent(for: ids)
                } primaryAction: { ids in
                    let queue = playbackQueue
                    if let id = ids.first, let index = queue.firstIndex(where: { $0.id == id }) {
                        onPlay(queue[index], queue, index)
                    }
                }
                .onChange(of: tracks, initial: true) { _, newTracks in
                    sortedTracks = newTracks.sorted(using: sortOrder)
                    rebuildRelationshipCaches(from: newTracks)
                    rebuildSortedSections()
                    expandedSections.formUnion(sections.map(\.id))
                }
                .onChange(of: sections.map(\.id)) { _, newIDs in
                    rebuildSortedSections()
                    // Expand new sections by default
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

    // Extracted to help the Swift type checker with complex Table expressions
    @ViewBuilder
    private var songsTable: some View {
        if isGrouped {
            Table(of: Track.self, selection: $selectedTrackIDs, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
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
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .padding(.bottom, 4)
                            .toolTip(section.tooltip)
                    }
                }
            }
        } else {
            Table(of: Track.self, selection: $selectedTrackIDs, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
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

    @TableColumnBuilder<Track, KeyPathComparator<Track>>
    private var coreColumns: some TableColumnContent<Track, KeyPathComparator<Track>> {
        TableColumn("#", value: \.trackNumber) { track in
            Text("\(track.trackNumber)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 30, ideal: 40, max: 60)
        .customizationID("trackNumber")

        TableColumn("Title", value: \.title) { track in
            Text(track.title)
                .font(.system(size: 13))
                .id(track.persistentModelID)
        }
        .customizationID("title")

        TableColumn("Artist") { track in
            Text(artistNames[track.id] ?? "Unknown")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 80, ideal: 150)
        .customizationID("artist")

        TableColumn("Album") { track in
            Text(albumNames[track.id] ?? "Unknown")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 80, ideal: 150)
        .customizationID("album")

        TableColumn("Time", value: \.duration) { track in
            Text(formatTime(track.duration))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .width(min: 40, ideal: 55, max: 80)
        .customizationID("time")
    }

    @TableColumnBuilder<Track, KeyPathComparator<Track>>
    private var metadataColumns: some TableColumnContent<Track, KeyPathComparator<Track>> {
        TableColumn("Genre") { track in
            Text(track.genre ?? "")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 60, ideal: 100)
        .customizationID("genre")
        .defaultVisibility(.hidden)

        TableColumn("Year") { track in
            Text(track.year.map { "\($0)" } ?? "")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 40, ideal: 60, max: 80)
        .customizationID("year")
        .defaultVisibility(.hidden)

        TableColumn("Plays") { track in
            Text("\(track.playCount)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 40, ideal: 50, max: 70)
        .customizationID("plays")
        .defaultVisibility(.hidden)
    }

    @TableColumnBuilder<Track, KeyPathComparator<Track>>
    private var audioColumns: some TableColumnContent<Track, KeyPathComparator<Track>> {
        TableColumn("Format") { track in
            Text(track.codec ?? "")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 40, ideal: 60, max: 80)
        .customizationID("format")
        .defaultVisibility(.hidden)

        TableColumn("Bitrate") { track in
            Text(track.bitrate.map { "\($0) kbps" } ?? "")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 50, ideal: 80, max: 100)
        .customizationID("bitrate")
        .defaultVisibility(.hidden)

        TableColumn("Sample Rate") { track in
            Text(track.sampleRate.map { formatSampleRate($0) } ?? "")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 50, ideal: 80, max: 100)
        .customizationID("sampleRate")
        .defaultVisibility(.hidden)

        TableColumn("Channels") { track in
            Text(track.channels.map { channelLabel($0) } ?? "")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .width(min: 40, ideal: 60, max: 80)
        .customizationID("channels")
        .defaultVisibility(.hidden)

        TableColumn("Size") { track in
            Text(track.fileSize.map { formatFileSize($0) } ?? "")
                .font(.system(size: 13))
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

    private func rebuildRelationshipCaches(from trackList: [Track]) {
        var artists: [PersistentIdentifier: String] = [:]
        var albums: [PersistentIdentifier: String] = [:]
        artists.reserveCapacity(trackList.count)
        albums.reserveCapacity(trackList.count)
        for track in trackList {
            artists[track.id] = track.artist?.name ?? "Unknown"
            albums[track.id] = track.album?.name ?? "Unknown"
        }
        artistNames = artists
        albumNames = albums
    }

    @ViewBuilder
    private func contextMenuContent(for ids: Set<PersistentIdentifier>) -> some View {
        let queue = playbackQueue
        if let id = ids.first, let index = queue.firstIndex(where: { $0.id == id }) {
            let track = queue[index]
            Button("Play") {
                onPlay(track, queue, index)
            }
            Button("Play Next") {
                onPlayNext(track)
            }
            Button("Play Later") {
                onPlayLater(track)
            }
            AddToPlaylistMenu(tracks: [track])
            Divider()
            Button("Remove from Library", role: .destructive) {
                onRemove(ids)
            }
        }
    }
}
