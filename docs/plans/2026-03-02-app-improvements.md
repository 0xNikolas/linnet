# App-Wide Improvements Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix 11 issues across the app — reactive data, gapless playback, timer polling, SQL duplication, type-safe sorting, error handling, navigation hacks, bookmark resolution, README accuracy, AI labeling, and async imports.

**Architecture:** Each task is self-contained and targets a specific layer (data, audio, views, docs). Tasks are ordered so earlier changes don't break later ones. The existing `DatabaseObserver<Value>` wrapper is already built and unused — Task 1 wires it in. The `GaplessScheduler` and `CrossfadeManager` are already built and tested — Task 2 wires them into `AudioPlayer`.

**Tech Stack:** Swift 6, SwiftUI, GRDB 7.4.1, AVAudioEngine, `@Observable`

---

### Task 1: Wire up GRDB ValueObservation for reactive views

Every list view currently loads data via `.task { loadItems() }` and manual `.onChange` triggers. If the database changes externally (e.g., a scan completes), views don't update. `DatabaseObserver<Value>` already exists at `Packages/LinnetLibrary/Sources/LinnetLibrary/Database/DatabaseObserver.swift` — it wraps `ValueObservation` and is `@Observable`. It just needs to be used.

**Files:**
- Modify: `Packages/LinnetLibrary/Sources/LinnetLibrary/Database/DatabaseObserver.swift` — add a convenience re-observe method so views can change sort/filter params
- Modify: `Packages/LinnetLibrary/Sources/LinnetLibrary/Database/AppDatabase.swift` — expose `pool` publicly (already done)
- Modify: All list views that use the `@State private var items: [T] = []` + `.task { loadData() }` pattern:
  - `Linnet/Views/SongsGroupingView.swift`
  - `Linnet/Views/AlbumGridView.swift`
  - `Linnet/Views/ArtistListView.swift`
  - `Linnet/Views/LikedSongsView.swift`
  - `Linnet/Views/PlaylistsView.swift`
  - `Linnet/Views/ListenNowView.swift`
  - `Linnet/Views/FolderBrowserView.swift`
  - `Linnet/Views/SidebarView.swift`
  - `Linnet/Views/AlbumDetailView.swift`
  - `Linnet/Views/ArtistDetailView.swift`
  - `Linnet/Views/PlaylistDetailView.swift`

**Approach:**

Step 1: Add a `reobserve` method to `DatabaseObserver` so views can restart observation with new parameters (e.g., when sort option changes):

```swift
// In DatabaseObserver.swift, add:
public func reobserve(
    in pool: DatabasePool,
    observation: ValueObservation<ValueReducers.Fetch<Value>>
) {
    cancellable?.cancel()
    self.cancellable = observation.start(
        in: pool,
        scheduling: .immediate,
        onError: { error in
            print("DatabaseObserver error: \(error)")
        },
        onChange: { [weak self] newValue in
            Task { @MainActor in
                self?.value = newValue
            }
        }
    )
}
```

Step 2: Convert each view one at a time. The pattern for each view is:

**Before (current pattern):**
```swift
@State private var tracks: [TrackInfo] = []

.task { loadData() }
.onChange(of: sortOption) { _, _ in loadData() }

private func loadData() {
    tracks = (try? appDatabase?.tracks.fetchAllInfo(orderedBy: sortOption.sqlColumn, direction: sortDirection.sql)) ?? []
}
```

**After (reactive pattern):**
```swift
@State private var observer: DatabaseObserver<[TrackInfo]>?

.task {
    guard let db = appDatabase else { return }
    observer = DatabaseObserver(
        initial: [],
        in: db.pool,
        observation: ValueObservation.tracking { db in
            try TrackInfo.fetchAll(db, sql: """
                SELECT track.*, artist.name AS artistName, album.name AS albumName
                FROM track
                LEFT JOIN artist ON track.artistId = artist.id
                LEFT JOIN album ON track.albumId = album.id
                ORDER BY \(sortOption.sqlColumn) \(sortDirection.sql)
                """)
        }
    )
}
.onChange(of: sortOption) { _, _ in reobserve() }
.onChange(of: sortDirection) { _, _ in reobserve() }
```

Then reference `observer?.value ?? []` instead of `tracks`.

Do one view at a time, build and verify the app compiles after each. Start with `SongsGroupingView` as it's the simplest list. Then `AlbumGridView`, `ArtistListView`, `LikedSongsView`, `PlaylistsView`, `ListenNowView`, `FolderBrowserView`, `SidebarView`, `AlbumDetailView`, `ArtistDetailView`, `PlaylistDetailView`.

**Step 3: Build**
```bash
xcodebuild -scheme Linnet -configuration Debug build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

**Step 4: Commit**
```bash
git add -A && git commit -m "feat: wire up GRDB ValueObservation for reactive views"
```

---

### Task 2: Wire up gapless playback and crossfade

`GaplessScheduler` and `CrossfadeManager` are fully implemented and tested but disconnected from `AudioPlayer`. `AudioPlayer` uses a single `AVAudioPlayerNode` with `completionHandler: nil`. The crossfade UI in `SettingsView` uses `@State` with no connection to the audio layer.

**Files:**
- Modify: `Packages/LinnetAudio/Sources/LinnetAudio/AudioPlayer.swift` — integrate `GaplessScheduler`, add track-end callback, pre-schedule next track
- Modify: `Linnet/ViewModels/PlayerViewModel.swift` — use the track-end callback instead of timer-based detection, pre-schedule next track
- Modify: `Linnet/Views/SettingsView.swift` (AudioSettingsView section, ~lines 273-293) — wire crossfade toggle/slider to `PlayerViewModel`

**Approach:**

Step 1: Refactor `AudioPlayer` to use `GaplessScheduler`:

```swift
// AudioPlayer.swift changes:
public final class AudioPlayer: @unchecked Sendable {
    private let engine: AVAudioEngine
    private let scheduler: GaplessScheduler
    private let eqNode: AVAudioUnitEQ
    public let equalizer: Equalizer

    // Track-end callback
    public var onTrackFinished: (@Sendable () -> Void)?

    private var currentFile: AVAudioFile?
    private var _duration: Double = 0
    private var _volume: Float = 0.7
    private var sampleRate: Double = 44100
    private var scheduledStartFrame: AVAudioFramePosition = 0

    public init() {
        engine = AVAudioEngine()
        scheduler = GaplessScheduler()
        eqNode = AVAudioUnitEQ(numberOfBands: Equalizer.bandCount)
        equalizer = Equalizer()

        // Attach both nodes from scheduler
        for node in scheduler.allNodes() {
            engine.attach(node)
        }
        engine.attach(eqNode)

        let mainMixer = engine.mainMixerNode
        let format = mainMixer.outputFormat(forBus: 0)
        // Connect active node through EQ
        engine.connect(scheduler.activeNode, to: eqNode, format: format)
        engine.connect(eqNode, to: mainMixer, format: format)

        mainMixer.outputVolume = _volume
        equalizer.bind(to: eqNode)
    }

    // Expose crossfade controls
    public var crossfadeEnabled: Bool {
        get { scheduler.crossfadeManager.isEnabled }
        set { scheduler.crossfadeManager.isEnabled = newValue }
    }

    public var crossfadeDuration: Double {
        get { scheduler.crossfadeManager.duration }
        set { scheduler.crossfadeManager.duration = newValue }
    }
```

In `load(url:)`, schedule the file on the active node and set a completion handler that calls `onTrackFinished`. Use `completionCallbackType: .dataPlayedBack` for accurate end-of-track detection.

Add a `preloadNext(url:)` method that opens the file and schedules it on the next node via `scheduler.scheduleNext(file:at:)`.

Step 2: In `PlayerViewModel`, set `audioPlayer.onTrackFinished` to call `next()`. Remove the timer-based track-end detection (`if self.currentTime >= self.duration`). Keep the timer only for UI time updates (or replace with a display link — but timer is fine for now).

Step 3: Wire `AudioSettingsView`:
- Change `@State` to `@AppStorage` for persistence
- Add `@Environment(PlayerViewModel.self)` to get the player
- Add `.onChange` to sync `crossfadeEnabled` → `player.setCrossfadeEnabled(_:)` and `crossfadeDuration` → `player.setCrossfadeDuration(_:)`
- Add methods on `PlayerViewModel` that forward to `audioPlayer.crossfadeEnabled` / `audioPlayer.crossfadeDuration`

Step 4: Run LinnetAudio tests:
```bash
swift test --package-path Packages/LinnetAudio 2>&1 | tail -10
```

Step 5: Build the app:
```bash
xcodebuild -scheme Linnet -configuration Debug build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Step 6: Commit
```bash
git add -A && git commit -m "feat: wire up gapless playback and crossfade to AudioPlayer"
```

---

### Task 3: Replace polling timer with completion callback for track-end detection

This is partially done in Task 2 (the `onTrackFinished` callback). This task cleans up the remaining timer to only update UI time, and removes the fragile `currentTime >= duration` check.

**Files:**
- Modify: `Linnet/ViewModels/PlayerViewModel.swift` — lines 326-337

**Approach:**

Step 1: In `startTimeUpdates()`, remove the track-end detection:

```swift
private func startTimeUpdates() {
    stopTimeUpdates()
    timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
        Task { @MainActor [weak self] in
            guard let self, self.isPlaying else { return }
            self.currentTime = self.audioPlayer.currentTime
            // Track-end is now handled by audioPlayer.onTrackFinished
        }
    }
}
```

Step 2: Make sure `audioPlayer.onTrackFinished` is set in `init()` or `loadAndPlay`:

```swift
// In init() or a setup method:
audioPlayer.onTrackFinished = { [weak self] in
    Task { @MainActor in
        self?.next()
    }
}
```

Step 3: Build and verify.

Step 4: Commit
```bash
git add -A && git commit -m "fix: replace polling-based track-end detection with completion callback"
```

---

### Task 4: DRY up TrackRepository SQL using TrackInfo.request()

The 3-table JOIN is copy-pasted ~9 times. `TrackInfo.request()` already exists but is unused.

**Files:**
- Modify: `Packages/LinnetLibrary/Sources/LinnetLibrary/Database/Records/TrackInfo.swift` — add parameterized request builders
- Modify: `Packages/LinnetLibrary/Sources/LinnetLibrary/Database/Repositories/TrackRepository.swift` — use the shared SQL

**Approach:**

Step 1: Add helper SQL methods to `TrackInfo`:

```swift
// TrackInfo.swift additions:
extension TrackInfo {
    /// Base SQL for the track+artist+album join. Append WHERE/ORDER BY/LIMIT as needed.
    static let baseSQL = """
        SELECT
            track.*,
            artist.name AS artistName,
            album.name AS albumName
        FROM track
        LEFT JOIN artist ON track.artistId = artist.id
        LEFT JOIN album ON track.albumId = album.id
        """

    /// Base SQL with FTS join for search.
    static let baseFTSSQL = """
        SELECT DISTINCT
            track.*,
            artist.name AS artistName,
            album.name AS albumName
        FROM track
        LEFT JOIN artist ON track.artistId = artist.id
        LEFT JOIN album ON track.albumId = album.id
        LEFT JOIN trackFts ON trackFts.rowid = track.id
        """
}
```

Step 2: Rewrite each `TrackRepository` method to use `TrackInfo.baseSQL`:

```swift
public func fetchAllInfo(orderedBy ordering: String = "track.title COLLATE NOCASE", direction: String = "ASC") throws -> [TrackInfo] {
    try pool.read { db in
        try TrackInfo.fetchAll(db, sql: "\(TrackInfo.baseSQL) ORDER BY \(ordering) \(direction)")
    }
}

public func fetchInfoByAlbum(id albumId: Int64) throws -> [TrackInfo] {
    try pool.read { db in
        try TrackInfo.fetchAll(db, sql: "\(TrackInfo.baseSQL) WHERE track.albumId = ? ORDER BY track.discNumber, track.trackNumber", arguments: [albumId])
    }
}
// ... etc for all methods
```

Step 3: Run LinnetLibrary tests:
```bash
swift test --package-path Packages/LinnetLibrary 2>&1 | tail -10
```

Step 4: Build the app.

Step 5: Commit
```bash
git add -A && git commit -m "refactor: DRY up TrackRepository SQL using shared TrackInfo.baseSQL"
```

---

### Task 5: Type-safe sort ordering

Sort parameters are raw `String` values interpolated into SQL. Replace with an allow-list validation approach.

**Files:**
- Modify: `Packages/LinnetLibrary/Sources/LinnetLibrary/Database/Repositories/TrackRepository.swift`
- Modify: `Packages/LinnetLibrary/Sources/LinnetLibrary/Database/Repositories/AlbumRepository.swift`
- Modify: `Packages/LinnetLibrary/Sources/LinnetLibrary/Database/Repositories/ArtistRepository.swift`
- Modify: `Packages/LinnetLibrary/Sources/LinnetLibrary/Database/Repositories/PlaylistRepository.swift`

**Approach:**

Step 1: Add a `TrackSortColumn` enum in `TrackRepository.swift` (and similar for other repos) that maps to safe SQL strings:

```swift
public enum TrackSortColumn: String, Sendable {
    case title, artist, album, dateAdded, duration

    var sql: String {
        switch self {
        case .title: "track.title COLLATE NOCASE"
        case .artist: "COALESCE(artist.name, 'zzz') COLLATE NOCASE"
        case .album: "COALESCE(album.name, 'zzz') COLLATE NOCASE"
        case .dateAdded: "track.dateAdded"
        case .duration: "track.duration"
        }
    }
}

public enum SortOrder: String, Sendable {
    case ascending, descending
    var sql: String { self == .ascending ? "ASC" : "DESC" }
}
```

Step 2: Change method signatures from `orderedBy: String` to `orderedBy: TrackSortColumn`:

```swift
public func fetchAllInfo(orderedBy column: TrackSortColumn = .title, direction: SortOrder = .ascending) throws -> [TrackInfo] {
    try pool.read { db in
        try TrackInfo.fetchAll(db, sql: "\(TrackInfo.baseSQL) ORDER BY \(column.sql) \(direction.sql)")
    }
}
```

Step 3: Update `SortFilterMenu.swift` — the `SortOptionProtocol.sqlColumn` property is no longer needed for direct SQL interpolation. Instead, map from the UI enum to the repository enum at the call site. Or make the UI enum's rawValue match the repository enum and convert.

Step 4: Update all view call sites that pass `sortOption.sqlColumn` and `sortDirection.sql` to use the new typed enums.

Step 5: Run tests, build, commit.
```bash
git add -A && git commit -m "refactor: replace raw SQL string sort params with type-safe enums"
```

---

### Task 6: Surface errors instead of silently swallowing with try?

Replace `try?` with proper error logging in views. The pattern is consistent: `(try? appDatabase?.repo.fetch()) ?? []`.

**Files:**
- Modify: All view files listed in Task 1 that use `try?` for database reads

**Approach:**

Step 1: Add a logging helper in `Linnet/Utilities/Log.swift`:

```swift
// If not already present, add a database log category:
static let database = Logger(subsystem: subsystem, category: "database")
```

Step 2: For **read operations** in views, replace `try?` with a do/catch that logs:

```swift
// Before:
tracks = (try? appDatabase?.tracks.fetchAllInfo()) ?? []

// After:
do {
    tracks = try appDatabase?.tracks.fetchAllInfo() ?? []
} catch {
    Log.database.error("Failed to fetch tracks: \(error)")
    tracks = []
}
```

Since Task 1 converts views to use `DatabaseObserver` (which already has error logging in its `onError` handler), most read-path `try?` calls will be eliminated. Focus the remaining `try?` fixes on:
- **Write operations** (like/dislike, playlist add/remove, folder operations) — these should log errors
- **One-off reads** (fetching a single album/artist for navigation) — these should log errors

Step 3: For write operations in `PlayerViewModel` (toggleLike, toggleDislike, updatePlayCount), log errors:

```swift
// Before:
try? appDatabase?.tracks.updateLikedStatus(filePath: track.filePath, status: newStatus)

// After:
do {
    try appDatabase?.tracks.updateLikedStatus(filePath: track.filePath, status: newStatus)
} catch {
    Log.database.error("Failed to update liked status: \(error)")
}
```

Step 4: Build and commit.
```bash
git add -A && git commit -m "fix: replace silent try? with error logging for database operations"
```

---

### Task 7: Fix navigation Task.sleep hacks in ContentView

Replace the 4 `Task.sleep(for: .milliseconds(100))` hacks with a state-driven approach.

**Files:**
- Modify: `Linnet/ContentView.swift` — lines 96-136

**Approach:**

The root cause: setting `selectedSidebarItem` triggers a re-render that resets `NavigationStack`, and appending to `navigationPath` in the same run loop tick is dropped because the stack hasn't rebuilt yet.

The fix: use a `@State` pending navigation target that gets consumed after the sidebar change takes effect.

Step 1: Add pending navigation state:

```swift
@State private var pendingNavigation: AnyHashable?
```

Step 2: Add an `.onChange(of: selectedSidebarItem)` handler that consumes pending navigation:

The existing `onChange(of: selectedSidebarItem)` resets `navigationPath`. Append to it by checking `pendingNavigation` after the reset, in the **next** run loop tick using `Task { @MainActor in }` (but without a sleep — SwiftUI processes the sidebar change synchronously in the same update cycle, so just yielding once is enough):

```swift
.onChange(of: selectedSidebarItem) { _, newItem in
    navigationPath = NavigationPath()
    breadcrumbs = [BreadcrumbItem(title: newItem?.label ?? "Home", level: 0)]
    if let pending = pendingNavigation {
        pendingNavigation = nil
        // Use DispatchQueue.main.async to ensure NavigationStack has rebuilt
        DispatchQueue.main.async {
            if let artist = pending as? ArtistRecord {
                navigationPath.append(artist)
            } else if let album = pending as? AlbumRecord {
                navigationPath.append(album)
            } else if let playlistID = pending as? Int64 {
                navigationPath.append(playlistID)
            }
        }
    }
}
```

Step 3: Update the notification handlers to set pending state instead of sleeping:

```swift
.onReceive(NotificationCenter.default.publisher(for: .navigateToCurrentArtist)) { _ in
    guard let artistId = player.currentQueueTrack?.artistId,
          let artistName = player.currentQueueTrack?.artistName else { return }
    if selectedSidebarItem == .artists && !navigationPath.isEmpty { return }
    pendingNavigation = ArtistRecord(id: artistId, name: artistName)
    selectedSidebarItem = .artists
}
```

Step 4: Build and verify navigation still works.

Step 5: Commit
```bash
git add -A && git commit -m "fix: replace Task.sleep navigation hacks with state-driven pending navigation"
```

---

### Task 8: Fix security-scoped bookmark resolution in startWatching

`LibraryViewModel.startWatching` uses `URL(filePath: folder.path)` instead of resolving the stored security-scoped bookmark, which will fail in sandbox.

**Files:**
- Modify: `Linnet/ViewModels/LibraryViewModel.swift` — `startWatching(db:)` method (lines 91-102)

**Approach:**

Step 1: Use the existing `resolveFolder` method (which correctly resolves bookmarks) instead of `URL(filePath:)`:

```swift
func startWatching(db: AppDatabase) {
    stopWatching()
    guard let folders = try? db.watchedFolders.fetchEnabled() else { return }
    for folder in folders {
        let url = resolveFolder(folder, db: db)
        fileWatcher.watch(folder: url.path) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scanFolder(url: url, db: db)
            }
        }
    }
}
```

Step 2: Also call `startWatching` on app launch. Check `LinnetApp.swift` — if it's not called there, add it:
```swift
// In the app's .task or .onAppear:
libraryViewModel.startWatching(db: appDatabase)
```

Step 3: Build and commit.
```bash
git add -A && git commit -m "fix: resolve security-scoped bookmarks in startWatching"
```

---

### Task 9: Update README to reflect actual tech stack

**Files:**
- Modify: `README.md`

**Approach:**

Step 1: Replace "SwiftData" with "GRDB" in the Tech Stack and Project Structure sections:

```markdown
## Tech Stack

- Swift 6, SwiftUI, AVAudioEngine, GRDB
- MLX Swift for on-device ML inference
- XcodeGen for project generation
- GitHub Actions CI with parallel package testing
```

```markdown
## Project Structure

Linnet/                  Main app target (SwiftUI)
Packages/
  LinnetAudio/           Audio engine — AVAudioEngine, gapless playback, EQ, queue
  LinnetLibrary/         Library management — GRDB database, metadata, folder scanning
  LinnetAI/              AI features — MLX Swift, embeddings, recommendations, playlists
```

Step 2: Commit
```bash
git add README.md && git commit -m "docs: update README tech stack from SwiftData to GRDB"
```

---

### Task 10: Label AI features as experimental

**Files:**
- Modify: `Linnet/Views/AIChatView.swift` — add "Experimental" badge/note
- Modify: `Linnet/Views/SettingsView.swift` — AI settings tab, add note

**Approach:**

Step 1: In `AIChatView`, add a subtle "Experimental" label near the top or as a placeholder message:

```swift
// Add to the empty state / welcome message:
Text("AI features are experimental and require downloading models.")
    .font(.app(size: 12))
    .foregroundStyle(.secondary)
```

Step 2: In the AI settings section (if it exists in SettingsView), add a similar note.

Step 3: Build and commit.
```bash
git add -A && git commit -m "feat: label AI features as experimental"
```

---

### Task 11: Use async write for large library imports

`LibraryManager.importResults` does a synchronous `pool.write` which blocks the actor for large imports.

**Files:**
- Modify: `Packages/LinnetLibrary/Sources/LinnetLibrary/LibraryManager.swift` — `importResults` method (lines 39-156)

**Approach:**

Step 1: Change `importResults` to use batched writes instead of one giant transaction. Process in chunks of ~500 results to avoid blocking:

```swift
public func importResults(_ results: [ScanResult], into pool: DatabasePool) async throws -> Int {
    var totalImported = 0
    let chunkSize = 500

    for chunk in stride(from: 0, to: results.count, by: chunkSize) {
        let end = min(chunk + chunkSize, results.count)
        let batch = Array(results[chunk..<end])

        let count = try await pool.write { db in
            // ... same import logic but for the batch only
        }
        totalImported += count
    }
    return totalImported
}
```

Alternatively, simply make the function `async` and use `pool.write` as-is — since `LibraryManager` is an actor, the synchronous write already runs off the main thread. The main concern is that a very long write blocks other actor messages. Batching solves this.

Step 2: Update callers in `LibraryViewModel` — they already call this in a `Task`, just need to add `await` if the signature changes to `async throws`.

Step 3: Run LinnetLibrary tests:
```bash
swift test --package-path Packages/LinnetLibrary 2>&1 | tail -10
```

Step 4: Build and commit.
```bash
git add -A && git commit -m "perf: batch library imports to avoid blocking actor with large writes"
```
