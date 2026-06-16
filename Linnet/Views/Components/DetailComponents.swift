import SwiftUI
import AppKit
import GRDB
import LinnetLibrary

// MARK: - Artwork thumbnail cache

/// Main-actor cache of decoded artwork thumbnails, keyed by "ownerType-ownerId".
/// Shared by the per-row thumbnails so scrolling never re-reads or re-decodes the
/// same cover. Misses are remembered so owners without art don't hit the database
/// on every appearance.
@MainActor
final class ArtworkThumbnailCache {
    static let shared = ArtworkThumbnailCache()
    private var images: [String: NSImage] = [:]
    private var misses: Set<String> = []

    func image(forKey key: String) -> NSImage? { images[key] }
    func isMiss(_ key: String) -> Bool { misses.contains(key) }
    func store(_ image: NSImage?, forKey key: String) {
        if let image { images[key] = image } else { misses.insert(key) }
    }
}

/// A small rounded artwork thumbnail for a row. Loads the owner's art (thumbnail,
/// falling back to the full image) off the main thread, caches it, and shows a
/// system-image placeholder when there is none.
struct ArtworkThumbnail: View {
    let ownerType: String
    let ownerId: Int64?
    var size: CGFloat = 28
    var fallbackSystemImage: String = "music.note"

    @Environment(\.appDatabase) private var appDatabase
    @State private var image: NSImage?

    private var cacheKey: String? { ownerId.map { "\(ownerType)-\($0)" } }

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.quaternary)
            .frame(width: size, height: size)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: fallbackSystemImage)
                        .font(.system(size: size * 0.42))
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .task(id: ownerId) { await load() }
    }

    private func load() async {
        guard let ownerId, let cacheKey else { return }
        if let cached = ArtworkThumbnailCache.shared.image(forKey: cacheKey) {
            image = cached
            return
        }
        if ArtworkThumbnailCache.shared.isMiss(cacheKey) { return }
        guard let pool = appDatabase?.pool else { return }
        let type = ownerType
        let data: Data? = await Task.detached {
            try? pool.read { db in
                try Data.fetchOne(
                    db,
                    sql: "SELECT COALESCE(thumbnailData, imageData) FROM artwork WHERE ownerType = ? AND ownerId = ?",
                    arguments: [type, ownerId]
                )
            }
        }.value ?? nil
        let decoded = data.flatMap(NSImage.init(data:))
        ArtworkThumbnailCache.shared.store(decoded, forKey: cacheKey)
        image = decoded
    }
}

// MARK: - Detail header

/// The shared Apple Music-style detail header: a large square artwork on the left,
/// then title, subtitle, an optional metadata line, and Play / Shuffle buttons.
/// The artwork is supplied by the caller (each detail view owns its own art loading
/// and context menu); this view handles the consistent sizing and layout.
struct DetailHeader<Artwork: View, Subtitle: View>: View {
    @ViewBuilder var artwork: () -> Artwork
    let title: String
    @ViewBuilder var subtitle: () -> Subtitle
    var metadata: String?
    var playDisabled: Bool = false
    let onPlay: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            artwork()
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.app(size: 28, weight: .bold))
                    .lineLimit(2)

                subtitle()

                if let metadata {
                    Text(metadata)
                        .font(.app(size: 13))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 12) {
                    Button(action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .disabled(playDisabled)

                    Button(action: onShuffle) {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(playDisabled)
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
    }
}

// MARK: - Footer

/// "N songs, M minutes" summary shown under a track list.
func trackListSummary(_ tracks: [TrackInfo]) -> String {
    let totalMinutes = Int(tracks.reduce(0.0) { $0 + $1.duration } / 60)
    let songWord = tracks.count == 1 ? "song" : "songs"
    let minuteWord = totalMinutes == 1 ? "minute" : "minutes"
    return "\(tracks.count) \(songWord), \(totalMinutes) \(minuteWord)"
}

struct TrackListFooter: View {
    let tracks: [TrackInfo]

    var body: some View {
        Text(trackListSummary(tracks))
            .font(.app(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
    }
}
