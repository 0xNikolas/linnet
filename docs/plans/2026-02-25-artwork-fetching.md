# Artwork Fetching Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fetch missing album and artist artwork on-demand from MusicBrainz, Cover Art Archive, Wikipedia, and optionally Fanart.tv/AcoustID.

**Architecture:** A new `ArtworkService` in `LinnetLibrary` orchestrates rate-limited HTTP lookups across MusicBrainz (text search), Cover Art Archive (album covers), Wikipedia (artist photos), and optional AcoustID/Fanart.tv. Views auto-fetch on appear when artwork is nil, and expose a manual "Find Artwork" context menu.

**Tech Stack:** Swift concurrency (async/await), URLSession, MusicBrainz JSON API, Cover Art Archive, Wikipedia REST API, SwiftData.

---

### Task 1: Add `artworkData` to Artist model

**Files:**
- Modify: `Packages/LinnetLibrary/Sources/LinnetLibrary/Models/Artist.swift`

**Step 1: Add the property**

In `Artist.swift`, add `artworkData` property after `name`:

```swift
public var name: String
public var artworkData: Data?   // <-- ADD THIS
```

No init change needed — it defaults to nil.

**Step 2: Build to verify**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add Packages/LinnetLibrary/Sources/LinnetLibrary/Models/Artist.swift
git commit -m "feat: add artworkData property to Artist model"
```

---

### Task 2: MusicBrainzClient — album and artist search

**Files:**
- Create: `Packages/LinnetLibrary/Sources/LinnetLibrary/Services/MusicBrainzClient.swift`

**Step 1: Create the client**

This client handles:
- Album search: query by album name + artist name → returns release-group MBID
- Artist search: query by name → returns artist MBID + URL relations (for Wikipedia)
- Rate limiting: 1 request per second via an actor-based throttle
- User-Agent header: required by MusicBrainz

```swift
import Foundation

public actor MusicBrainzClient {
    private static let baseURL = "https://musicbrainz.org/ws/2"
    private static let userAgent = "Linnet/1.0 (https://github.com/nicklama/linnet)"
    private var lastRequestTime: Date = .distantPast

    public init() {}

    // MARK: - Album Search

    public struct ReleaseGroupResult: Sendable {
        public let mbid: String
        public let title: String
        public let score: Int
    }

    public func searchReleaseGroup(album: String, artist: String) async throws -> ReleaseGroupResult? {
        let query = "releasegroup:\(album) AND artist:\(artist)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "\(Self.baseURL)/release-group/?query=\(query)&fmt=json&limit=5")!
        let data = try await rateLimitedRequest(url: url)

        struct Response: Decodable {
            struct ReleaseGroup: Decodable {
                let id: String
                let title: String
                let score: Int
            }
            let releaseGroups: [ReleaseGroup]?
            enum CodingKeys: String, CodingKey {
                case releaseGroups = "release-groups"
            }
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let best = response.releaseGroups?.first, best.score >= 80 else { return nil }
        return ReleaseGroupResult(mbid: best.id, title: best.title, score: best.score)
    }

    // MARK: - Artist Search

    public struct ArtistResult: Sendable {
        public let mbid: String
        public let name: String
        public let score: Int
    }

    public func searchArtist(name: String) async throws -> ArtistResult? {
        let query = "artist:\(name)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "\(Self.baseURL)/artist/?query=\(query)&fmt=json&limit=5")!
        let data = try await rateLimitedRequest(url: url)

        struct Response: Decodable {
            struct Artist: Decodable {
                let id: String
                let name: String
                let score: Int
            }
            let artists: [Artist]?
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let best = response.artists?.first, best.score >= 80 else { return nil }
        return ArtistResult(mbid: best.id, name: best.name, score: best.score)
    }

    // MARK: - Artist Wikipedia URL

    public func fetchArtistWikipediaURL(mbid: String) async throws -> URL? {
        let url = URL(string: "\(Self.baseURL)/artist/\(mbid)?inc=url-rels&fmt=json")!
        let data = try await rateLimitedRequest(url: url)

        struct Response: Decodable {
            struct Relation: Decodable {
                let type: String
                let url: RelURL?
                struct RelURL: Decodable {
                    let resource: String
                }
            }
            let relations: [Relation]?
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        // Prefer Wikipedia, fall back to Wikidata
        let wikiRelation = response.relations?.first(where: { $0.type == "wikipedia" })
            ?? response.relations?.first(where: { $0.type == "wikidata" })
        guard let resource = wikiRelation?.url?.resource else { return nil }
        return URL(string: resource)
    }

    // MARK: - Rate Limiting

    private func rateLimitedRequest(url: URL) async throws -> Data {
        let elapsed = Date().timeIntervalSince(lastRequestTime)
        if elapsed < 1.0 {
            try await Task.sleep(for: .milliseconds(Int((1.0 - elapsed) * 1000)))
        }
        lastRequestTime = Date()

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
```

**Step 2: Build to verify**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add Packages/LinnetLibrary/Sources/LinnetLibrary/Services/MusicBrainzClient.swift
git commit -m "feat: add MusicBrainzClient for album/artist search"
```

---

### Task 3: Cover Art Archive + Wikipedia image fetching

**Files:**
- Create: `Packages/LinnetLibrary/Sources/LinnetLibrary/Services/ImageFetcher.swift`

**Step 1: Create the image fetcher**

This handles downloading images from Cover Art Archive and Wikipedia:

```swift
import Foundation

public struct ImageFetcher: Sendable {

    public init() {}

    /// Fetch album cover from Cover Art Archive by release-group MBID.
    /// Returns JPEG/PNG image data or nil if not found.
    public func fetchAlbumCover(releaseGroupMBID: String) async throws -> Data? {
        // Cover Art Archive redirects to the actual image
        let url = URL(string: "https://coverartarchive.org/release-group/\(releaseGroupMBID)/front-500")!
        var request = URLRequest(url: url)
        request.setValue("Linnet/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            if http.statusCode == 404 { return nil }
            guard (200...299).contains(http.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }

    /// Fetch artist image from Wikipedia given a Wikipedia or Wikidata URL.
    public func fetchWikipediaImage(from wikiURL: URL) async throws -> Data? {
        let title: String
        if wikiURL.host?.contains("wikidata") == true {
            // Wikidata URL like https://www.wikidata.org/wiki/Q2831
            // Need to resolve to Wikipedia title first
            guard let resolved = try await resolveWikidataToWikipedia(wikiURL) else { return nil }
            title = resolved
        } else {
            // Wikipedia URL like https://en.wikipedia.org/wiki/Enya
            title = wikiURL.lastPathComponent
        }

        // Use Wikipedia REST API to get page summary with thumbnail
        let summaryURL = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(title)")!
        var request = URLRequest(url: summaryURL)
        request.setValue("Linnet/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }

        struct Summary: Decodable {
            struct Thumbnail: Decodable {
                let source: String
            }
            let thumbnail: Thumbnail?
            let originalimage: Thumbnail?
        }

        let summary = try JSONDecoder().decode(Summary.self, from: data)
        // Prefer original image, fall back to thumbnail
        guard let imageURLString = summary.originalimage?.source ?? summary.thumbnail?.source,
              let imageURL = URL(string: imageURLString) else { return nil }

        var imgRequest = URLRequest(url: imageURL)
        imgRequest.setValue("Linnet/1.0", forHTTPHeaderField: "User-Agent")
        let (imgData, imgResponse) = try await URLSession.shared.data(for: imgRequest)
        guard let imgHttp = imgResponse as? HTTPURLResponse, (200...299).contains(imgHttp.statusCode) else {
            return nil
        }
        return imgData
    }

    /// Resolve a Wikidata entity URL to an English Wikipedia page title.
    private func resolveWikidataToWikipedia(_ wikidataURL: URL) async throws -> String? {
        let entityID = wikidataURL.lastPathComponent // e.g. "Q2831"
        let apiURL = URL(string: "https://www.wikidata.org/w/api.php?action=wbgetentities&ids=\(entityID)&props=sitelinks&sitefilter=enwiki&format=json")!
        var request = URLRequest(url: apiURL)
        request.setValue("Linnet/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)

        struct Response: Decodable {
            struct Entity: Decodable {
                struct SiteLinks: Decodable {
                    struct SiteLink: Decodable {
                        let title: String
                    }
                    let enwiki: SiteLink?
                }
                let sitelinks: SiteLinks?
            }
            let entities: [String: Entity]?
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.entities?.values.first?.sitelinks?.enwiki?.title
    }
}
```

**Step 2: Build to verify**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add Packages/LinnetLibrary/Sources/LinnetLibrary/Services/ImageFetcher.swift
git commit -m "feat: add ImageFetcher for Cover Art Archive and Wikipedia"
```

---

### Task 4: ArtworkService — orchestrator

**Files:**
- Create: `Packages/LinnetLibrary/Sources/LinnetLibrary/Services/ArtworkService.swift`

**Step 1: Create the service**

This is the main entry point for views to request artwork. It orchestrates the lookup pipeline and manages in-flight requests to avoid duplicate fetches.

```swift
import Foundation
import SwiftData

@MainActor
@Observable
public final class ArtworkService {
    private let musicBrainz = MusicBrainzClient()
    private let imageFetcher = ImageFetcher()

    /// Track in-flight requests to avoid duplicate fetches
    private var albumFetchesInProgress: Set<String> = []   // album name + artist
    private var artistFetchesInProgress: Set<String> = []  // artist name

    public var fanartTVAPIKey: String = ""
    public var acoustIDAPIKey: String = ""

    public init() {}

    // MARK: - Album Artwork

    /// Fetch album artwork and save to the Album model.
    /// Returns true if artwork was found and saved.
    @discardableResult
    public func fetchAlbumArtwork(for album: Album, context: ModelContext) async -> Bool {
        let key = "\(album.name)|\(album.artistName ?? "")"
        guard !albumFetchesInProgress.contains(key) else { return false }
        albumFetchesInProgress.insert(key)
        defer { albumFetchesInProgress.remove(key) }

        do {
            // Step 1: Search MusicBrainz for release group
            guard let result = try await musicBrainz.searchReleaseGroup(
                album: album.name,
                artist: album.artistName ?? ""
            ) else { return false }

            // Step 2: Fetch cover from Cover Art Archive
            guard let imageData = try await imageFetcher.fetchAlbumCover(
                releaseGroupMBID: result.mbid
            ) else { return false }

            // Step 3: Save to model
            album.artworkData = imageData
            // Also update tracks that belong to this album and have no artwork
            for track in album.tracks where track.artworkData == nil {
                track.artworkData = imageData
            }
            try? context.save()
            return true
        } catch {
            print("[ArtworkService] Album fetch error for \(album.name): \(error)")
            return false
        }
    }

    // MARK: - Artist Artwork

    /// Fetch artist artwork and save to the Artist model.
    /// Returns true if artwork was found and saved.
    @discardableResult
    public func fetchArtistArtwork(for artist: Artist, context: ModelContext) async -> Bool {
        let key = artist.name
        guard !artistFetchesInProgress.contains(key) else { return false }
        artistFetchesInProgress.insert(key)
        defer { artistFetchesInProgress.remove(key) }

        do {
            // Try Fanart.tv first if API key is available
            if !fanartTVAPIKey.isEmpty {
                if let data = try await fetchFanartTVArtistImage(artistName: artist.name) {
                    artist.artworkData = data
                    try? context.save()
                    return true
                }
            }

            // Fall back to MusicBrainz → Wikipedia
            guard let mbResult = try await musicBrainz.searchArtist(name: artist.name) else {
                return false
            }
            guard let wikiURL = try await musicBrainz.fetchArtistWikipediaURL(mbid: mbResult.mbid) else {
                return false
            }
            guard let imageData = try await imageFetcher.fetchWikipediaImage(from: wikiURL) else {
                return false
            }

            artist.artworkData = imageData
            try? context.save()
            return true
        } catch {
            print("[ArtworkService] Artist fetch error for \(artist.name): \(error)")
            return false
        }
    }

    // MARK: - Fanart.tv (optional)

    private func fetchFanartTVArtistImage(artistName: String) async throws -> Data? {
        // First need the MBID from MusicBrainz
        guard let mbResult = try await musicBrainz.searchArtist(name: artistName) else {
            return nil
        }

        let url = URL(string: "https://webservice.fanart.tv/v3/music/\(mbResult.mbid)?api_key=\(fanartTVAPIKey)")!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }

        struct FanartResponse: Decodable {
            struct Image: Decodable { let url: String }
            let artistthumb: [Image]?
        }

        let fanart = try JSONDecoder().decode(FanartResponse.self, from: data)
        guard let imageURLString = fanart.artistthumb?.first?.url,
              let imageURL = URL(string: imageURLString) else { return nil }

        let (imgData, _) = try await URLSession.shared.data(from: imageURL)
        return imgData
    }
}
```

**Step 2: Build to verify**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add Packages/LinnetLibrary/Sources/LinnetLibrary/Services/ArtworkService.swift
git commit -m "feat: add ArtworkService orchestrating album/artist artwork lookup"
```

---

### Task 5: Wire ArtworkService into the app

**Files:**
- Modify: `Linnet/LinnetApp.swift` (or wherever the app entry point injects environment objects)

**Step 1: Find the app entry point**

Check how `PlayerViewModel` is injected. The same pattern applies for `ArtworkService`.

The app likely has something like `.environment(playerViewModel)`. Add `.environment(artworkService)` alongside it.

```swift
@State private var artworkService = ArtworkService()

// In body, alongside existing .environment(playerViewModel):
.environment(artworkService)
```

**Step 2: Build to verify**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add Linnet/LinnetApp.swift
git commit -m "feat: inject ArtworkService into SwiftUI environment"
```

---

### Task 6: Add API key settings UI

**Files:**
- Modify: `Linnet/Views/SettingsView.swift`

**Step 1: Add artwork settings section**

Add a new "Artwork" section to SettingsView, reading/writing `@AppStorage` keys that the `ArtworkService` will use:

```swift
struct ArtworkSettingsView: View {
    @AppStorage("acoustIDAPIKey") private var acoustIDKey = ""
    @AppStorage("fanartTVAPIKey") private var fanartTVKey = ""

    var body: some View {
        Form {
            Section("Album Artwork") {
                Text("Album covers are fetched automatically from MusicBrainz and Cover Art Archive (no API key needed).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("AcoustID API Key") {
                    SecureField("Optional — enables fingerprint fallback", text: $acoustIDKey)
                        .textFieldStyle(.roundedBorder)
                }
                Text("Get a free key at acoustid.org")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Section("Artist Images") {
                Text("Artist photos are fetched from Wikipedia (no API key needed).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Fanart.tv API Key") {
                    SecureField("Optional — enables higher-quality images", text: $fanartTVKey)
                        .textFieldStyle(.roundedBorder)
                }
                Text("Get a free key at fanart.tv")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }
}
```

Add the tab to `SettingsView`:

```swift
ArtworkSettingsView()
    .tabItem { Label("Artwork", systemImage: "photo") }
```

Increase settings frame height from 300 to 350 to accommodate the new tab.

**Step 2: Build to verify**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add Linnet/Views/SettingsView.swift
git commit -m "feat: add artwork API key settings UI"
```

---

### Task 7: Auto-fetch artwork in AlbumDetailView and AlbumGridView

**Files:**
- Modify: `Linnet/Views/AlbumDetailView.swift`
- Modify: `Linnet/Views/AlbumGridView.swift`

**Step 1: AlbumDetailView — auto-fetch on appear + loading state**

Add to `AlbumDetailView`:
- `@Environment(ArtworkService.self) private var artworkService`
- `@State private var isFetchingArtwork = false`
- `.task` modifier on the header artwork area to auto-fetch if nil
- Loading indicator overlay on the artwork placeholder
- Context menu item "Find Artwork" for manual refetch

In the artwork overlay, when `artworkData` is nil, show a `ProgressView` while fetching:

```swift
if let artData = album.artworkData, let img = NSImage(data: artData) {
    Image(nsImage: img).resizable().scaledToFill()
} else if isFetchingArtwork {
    ProgressView()
} else {
    Image(systemName: "music.note")
        .font(.system(size: 40))
        .foregroundStyle(.secondary)
}
```

Add `.task` modifier:
```swift
.task {
    guard album.artworkData == nil else { return }
    isFetchingArtwork = true
    await artworkService.fetchAlbumArtwork(for: album, context: modelContext)
    isFetchingArtwork = false
}
```

Add context menu item to the album header (right-click on artwork):
```swift
.contextMenu {
    Button("Find Artwork") {
        Task {
            isFetchingArtwork = true
            await artworkService.fetchAlbumArtwork(for: album, context: modelContext)
            isFetchingArtwork = false
        }
    }
}
```

**Step 2: AlbumGridView — auto-fetch for visible albums + context menu**

Add `@Environment(ArtworkService.self) private var artworkService` to `AlbumGridView`.

On each `AlbumCard`, add a `.task` modifier that fetches artwork if nil:

```swift
.task {
    guard album.artworkData == nil else { return }
    await artworkService.fetchAlbumArtwork(for: album, context: modelContext)
}
```

Add "Find Artwork" to the existing context menu.

**Step 3: Build to verify**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```bash
git add Linnet/Views/AlbumDetailView.swift Linnet/Views/AlbumGridView.swift
git commit -m "feat: auto-fetch album artwork on view appear"
```

---

### Task 8: Auto-fetch artwork in ArtistDetailView and ArtistListView

**Files:**
- Modify: `Linnet/Views/ArtistDetailView.swift`
- Modify: `Linnet/Views/ArtistListView.swift`

**Step 1: ArtistDetailView — show artwork + auto-fetch**

Replace the hardcoded `music.mic` circle placeholder with actual artwork display:

```swift
Circle()
    .fill(.quaternary)
    .frame(width: 120, height: 120)
    .overlay {
        if let artData = artist.artworkData, let img = NSImage(data: artData) {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
        } else if isFetchingArtwork {
            ProgressView()
        } else {
            Image(systemName: "music.mic")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
        }
    }
    .clipShape(Circle())
    .task {
        guard artist.artworkData == nil else { return }
        isFetchingArtwork = true
        await artworkService.fetchArtistArtwork(for: artist, context: modelContext)
        isFetchingArtwork = false
    }
    .contextMenu {
        Button("Find Artwork") {
            Task {
                isFetchingArtwork = true
                await artworkService.fetchArtistArtwork(for: artist, context: modelContext)
                isFetchingArtwork = false
            }
        }
    }
```

**Step 2: ArtistListView — show artwork in list rows**

Replace the placeholder circle in artist rows with actual artwork:

```swift
Circle()
    .fill(.quaternary)
    .frame(width: 40, height: 40)
    .overlay {
        if let artData = artist.artworkData, let img = NSImage(data: artData) {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "music.mic")
                .foregroundStyle(.secondary)
        }
    }
    .clipShape(Circle())
    .task {
        guard artist.artworkData == nil else { return }
        await artworkService.fetchArtistArtwork(for: artist, context: modelContext)
    }
```

Add "Find Artwork" to artist context menu.

**Step 3: Build to verify**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```bash
git add Linnet/Views/ArtistDetailView.swift Linnet/Views/ArtistListView.swift
git commit -m "feat: auto-fetch artist artwork on view appear"
```

---

### Task 9: Auto-fetch artwork in ListenNowView

**Files:**
- Modify: `Linnet/Views/ListenNowView.swift`

**Step 1: Add artwork auto-fetch for Recently Added tracks and Albums**

Add `@Environment(ArtworkService.self) private var artworkService`.

For album cards in the "Albums" horizontal scroll, add `.task` to fetch missing artwork:

```swift
.task {
    guard album.artworkData == nil else { return }
    await artworkService.fetchAlbumArtwork(for: album, context: modelContext)
}
```

For recently added track cards, fetch via the track's album if artwork is missing:

```swift
.task {
    guard track.artworkData == nil, let album = track.album, album.artworkData == nil else { return }
    await artworkService.fetchAlbumArtwork(for: album, context: modelContext)
}
```

**Step 2: Build to verify**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add Linnet/Views/ListenNowView.swift
git commit -m "feat: auto-fetch artwork in Listen Now view"
```

---

### Task 10: Wire API keys from AppStorage to ArtworkService

**Files:**
- Modify: `Linnet/LinnetApp.swift` (or wherever the ArtworkService is created)

**Step 1: Sync AppStorage keys to ArtworkService**

The `ArtworkService` has `fanartTVAPIKey` and `acoustIDAPIKey` properties. These need to be synced from `@AppStorage`. Add this in the app entry point or a parent view:

```swift
@AppStorage("acoustIDAPIKey") private var acoustIDKey = ""
@AppStorage("fanartTVAPIKey") private var fanartTVKey = ""

// In body or .onChange:
.onChange(of: fanartTVKey, initial: true) { _, newValue in
    artworkService.fanartTVAPIKey = newValue
}
.onChange(of: acoustIDKey, initial: true) { _, newValue in
    artworkService.acoustIDAPIKey = newValue
}
```

**Step 2: Build to verify**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add Linnet/LinnetApp.swift
git commit -m "feat: sync API keys from settings to ArtworkService"
```

---

### Task 11: Export public API from LinnetLibrary

**Files:**
- Modify: `Packages/LinnetLibrary/Sources/LinnetLibrary/LinnetLibrary.swift`

**Step 1: Ensure new types are exported**

Check that `LinnetLibrary.swift` re-exports or that all new service files use `public` access. Since the files are in the `LinnetLibrary` target and use `public` on their APIs, they should be accessible. Verify by checking the import works from the app target.

If `LinnetLibrary.swift` has explicit exports, add:
```swift
@_exported import struct LinnetLibrary.ArtworkService
```

More likely, since everything is in the same module, just verify the build works from the app target.

**Step 2: Build to verify**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: `BUILD SUCCEEDED`

**Step 3: Commit (if changes needed)**

```bash
git add Packages/LinnetLibrary/Sources/LinnetLibrary/LinnetLibrary.swift
git commit -m "feat: export artwork service from LinnetLibrary"
```

---

### Task 12: Final integration test

**Step 1: Full build**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: `BUILD SUCCEEDED`

**Step 2: Manual verification checklist**

- [ ] Launch app, navigate to Albums — albums with missing art should show loading → artwork appears
- [ ] Navigate to an artist — artist photo fetches from Wikipedia
- [ ] Right-click an album → "Find Artwork" triggers refetch
- [ ] Right-click an artist → "Find Artwork" triggers refetch
- [ ] Settings → Artwork tab shows API key fields
- [ ] Delete an album → no orphaned artwork (it's inline in SwiftData)
- [ ] Rate limiting works (no 503 errors from MusicBrainz)

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: complete artwork fetching from MusicBrainz, Cover Art Archive, Wikipedia"
```
