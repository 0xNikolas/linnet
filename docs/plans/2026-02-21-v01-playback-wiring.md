# v0.1 Core Playback Wiring — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Wire SwiftUI views to the audio engine so users can browse their library and play music.

**Architecture:** Enhance `PlayerViewModel` with a `playTrack(_:queue:startingAt:)` method that accepts SwiftData `Track` models. Views pass Track objects to play; PlayerViewModel handles file loading, metadata population, and queue management. Wrap the detail area in `NavigationStack` for drill-down navigation from grids to detail views.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, LinnetAudio (AudioPlayer, PlaybackQueue), LinnetLibrary (Track, Album, Artist)

---

### Task 1: PlayerViewModel — Track-Aware Playback

The core bridge between SwiftData models and the audio engine. All other tasks depend on this.

**Files:**
- Modify: `Linnet/ViewModels/PlayerViewModel.swift`

**Context:**
- `PlayerViewModel` is `@MainActor @Observable` — it can hold `[Track]` references safely
- `PlaybackQueue` stores `[String]` file paths — we keep a parallel `[Track]` array in the view model
- `Track` has: `filePath`, `title`, `artist?.name`, `album?.name`, `artworkData`, `lastPlayed`, `playCount`
- Current `playTracks(_:startingAt:)` (line 101) accepts `[String]` — we add a new overload for `[Track]`
- Current `loadAndPlay(filePath:)` (line 112) sets `currentTrackTitle` from filename — we need to set it from Track model
- Current `next()` (line 71) and `previous()` (line 79) call `loadAndPlay(filePath:)` — they need to also update metadata

**Step 1: Add track storage and metadata population**

Add these properties after `queue` (line 30):

```swift
private var queuedTracks: [Track] = []
private var currentTrackIndex: Int = 0
```

Add this method after `playTracks` (after line 110):

```swift
func playTrack(_ track: Track, queue: [Track], startingAt index: Int = 0) {
    queuedTracks = queue
    currentTrackIndex = index
    let filePaths = queue.map(\.filePath)
    self.queue = PlaybackQueue()
    self.queue.add(tracks: filePaths)
    for _ in 0..<index {
        _ = self.queue.advance()
    }
    if let current = self.queue.current {
        updateMetadata(for: queuedTracks[index])
        loadAndPlay(filePath: current)
    }
}
```

Add this private helper:

```swift
private func updateMetadata(for track: Track) {
    currentTrackTitle = track.title
    currentTrackArtist = track.artist?.name ?? "Unknown Artist"
    currentTrackAlbum = track.album?.name ?? ""
    currentArtworkData = track.artworkData
    track.lastPlayed = Date()
    track.playCount += 1
}
```

**Step 2: Update `next()` and `previous()` to populate metadata**

Replace `next()` (lines 71-77):

```swift
func next() {
    if let nextPath = queue.advance() {
        currentTrackIndex += 1
        if currentTrackIndex < queuedTracks.count {
            updateMetadata(for: queuedTracks[currentTrackIndex])
        }
        loadAndPlay(filePath: nextPath)
    } else {
        stop()
    }
}
```

Replace `previous()` (lines 79-87):

```swift
func previous() {
    if currentTime > 3 {
        seek(to: 0)
        return
    }
    if let prevPath = queue.goBack() {
        currentTrackIndex -= 1
        if currentTrackIndex >= 0, currentTrackIndex < queuedTracks.count {
            updateMetadata(for: queuedTracks[currentTrackIndex])
        }
        loadAndPlay(filePath: prevPath)
    }
}
```

**Step 3: Remove redundant title-from-filename logic**

In `loadAndPlay(filePath:)` (line 121), replace:
```swift
currentTrackTitle = url.deletingPathExtension().lastPathComponent
```
with:
```swift
// Only set title from filename if no Track metadata was provided (e.g. direct file playback)
if currentTrackTitle == "No Track Playing" {
    currentTrackTitle = url.deletingPathExtension().lastPathComponent
}
```

**Step 4: Build to verify**

Run: `cd /Users/nicu/Projects/linnet && xcodegen generate && xcodebuild build -project Linnet.xcodeproj -scheme Linnet -configuration Debug 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```
feat(player): add Track-aware playback to PlayerViewModel
```

---

### Task 2: NavigationStack for Drill-Down Navigation

Wrap the detail area in `NavigationStack` so views can push to detail pages (album → album detail, artist → artist detail).

**Files:**
- Modify: `Linnet/ContentView.swift`
- Modify: `Linnet/Views/ContentArea.swift`

**Context:**
- `ContentView` uses `NavigationSplitView` with sidebar + detail (line 9)
- Detail area renders `ContentArea(tab:sidebarItem:)` (line 12)
- `ContentArea` switches between views based on tab/sidebar (lines 7-43)
- We need `NavigationStack` inside the detail column with `.navigationDestination` for `Album` and `Artist`
- SwiftData models (`Album`, `Artist`) already conform to `Identifiable` and `Hashable`

**Step 1: Wrap detail content in NavigationStack**

In `ContentView.swift`, replace the detail closure (line 12):

```swift
} detail: {
    NavigationStack {
        ContentArea(tab: selectedTab, sidebarItem: selectedSidebarItem)
    }
    .id(selectedTab)
    .id(selectedSidebarItem)
}
```

The `.id()` modifiers reset the navigation stack when the user switches tabs or sidebar items, preventing stale drill-down views.

**Step 2: Build to verify**

Run: `cd /Users/nicu/Projects/linnet && xcodebuild build -project Linnet.xcodeproj -scheme Linnet -configuration Debug 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```
feat(nav): wrap detail area in NavigationStack for drill-down
```

---

### Task 3: SongsListView — Play on Double-Click

Replace the Table with a List-based layout that supports double-click to play. Table doesn't support double-click gestures in SwiftUI; a List with manual columns is simpler and functional.

**Files:**
- Modify: `Linnet/Views/SongsListView.swift`

**Context:**
- Current view uses `Table(tracks)` with columns for #, Title, Artist, Album, Duration (lines 12-42)
- `@Query(sort: \Track.title)` fetches all tracks (line 6)
- Needs `@Environment(PlayerViewModel.self)` to trigger playback
- On double-click: call `player.playTrack(track, queue: tracks, startingAt: index)`

**Step 1: Rewrite SongsListView**

Replace the entire file content:

```swift
import SwiftUI
import SwiftData
import LinnetLibrary

struct SongsListView: View {
    @Query(sort: \Track.title) private var tracks: [Track]
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        if tracks.isEmpty {
            ContentUnavailableView("No Songs", systemImage: "music.note", description: Text("Add a music folder in Settings to get started."))
        } else {
            List {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    HStack {
                        Text("\(track.trackNumber)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)

                        Text(track.title)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(track.artist?.name ?? "Unknown")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 150, alignment: .leading)

                        Text(track.album?.name ?? "Unknown")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 150, alignment: .leading)

                        Text(formatDuration(track.duration))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        player.playTrack(track, queue: tracks, startingAt: index)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
```

**Step 2: Build to verify**

Run: `cd /Users/nicu/Projects/linnet && xcodebuild build -project Linnet.xcodeproj -scheme Linnet -configuration Debug 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```
feat(songs): add double-click to play in SongsListView
```

---

### Task 4: AlbumDetailView — Real Data + Playback

Rewrite AlbumDetailView to accept an `Album` model, display real tracks sorted by disc/track number, and wire Play/Shuffle buttons.

**Files:**
- Modify: `Linnet/Views/AlbumDetailView.swift`

**Context:**
- Current view accepts `albumName: String` and `artistName: String` with hardcoded dummy tracks (lines 4-13)
- Album model has: `name`, `artistName`, `year`, `artworkData`, `tracks: [Track]`
- Track model has: `discNumber`, `trackNumber`, `title`, `duration`, `artist?.name`
- Play button should call `player.playTrack(firstTrack, queue: sortedTracks, startingAt: 0)`
- Shuffle button should randomize the track order before playing
- Each track row should be double-clickable to play from that position

**Step 1: Rewrite AlbumDetailView**

Replace the entire file content:

```swift
import SwiftUI
import LinnetLibrary

struct AlbumDetailView: View {
    let album: Album
    @Environment(PlayerViewModel.self) private var player

    private var sortedTracks: [Track] {
        album.tracks.sorted {
            ($0.discNumber, $0.trackNumber) < ($1.discNumber, $1.trackNumber)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(alignment: .bottom, spacing: 20) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .frame(width: 200, height: 200)
                        .overlay {
                            if let artData = album.artworkData, let img = NSImage(data: artData) {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "music.note")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(album.name)
                            .font(.system(size: 28, weight: .bold))
                        Text(album.artistName ?? "Unknown Artist")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            if let year = album.year {
                                Text(String(year))
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                            }
                            Text("\(sortedTracks.count) songs")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                        }

                        HStack(spacing: 12) {
                            Button("Play") {
                                if let first = sortedTracks.first {
                                    player.playTrack(first, queue: sortedTracks, startingAt: 0)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.accentColor)

                            Button("Shuffle") {
                                let shuffled = sortedTracks.shuffled()
                                if let first = shuffled.first {
                                    player.playTrack(first, queue: shuffled, startingAt: 0)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(20)

                Divider()

                // Track list
                ForEach(Array(sortedTracks.enumerated()), id: \.element.id) { index, track in
                    HStack {
                        Text("\(track.trackNumber)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)

                        Text(track.title)
                            .font(.system(size: 13))

                        Spacer()

                        Text(formatDuration(track.duration))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        player.playTrack(track, queue: sortedTracks, startingAt: index)
                    }

                    if index < sortedTracks.count - 1 {
                        Divider()
                            .padding(.leading, 60)
                    }
                }
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
```

**Step 2: Build to verify**

Run: `cd /Users/nicu/Projects/linnet && xcodebuild build -project Linnet.xcodeproj -scheme Linnet -configuration Debug 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```
feat(albums): rewrite AlbumDetailView with real data and playback
```

---

### Task 5: AlbumGridView — Navigation to AlbumDetailView

Add `NavigationLink` around album cards so clicking navigates to the detail view.

**Files:**
- Modify: `Linnet/Views/AlbumGridView.swift`

**Context:**
- Current view uses `ForEach(albums)` rendering `AlbumCard` components (lines 16-22)
- `AlbumCard` is a passive display component — wrap it in `NavigationLink`
- `NavigationStack` is already set up in `ContentView` (Task 2)
- Register `.navigationDestination(for: Album.self)` here since AlbumGridView is the natural owner

**Step 1: Add NavigationLink and destination**

Replace the entire file content:

```swift
import SwiftUI
import SwiftData
import LinnetLibrary

struct AlbumGridView: View {
    @Query(sort: \Album.name) private var albums: [Album]
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]

    var body: some View {
        ScrollView {
            if albums.isEmpty {
                ContentUnavailableView("No Albums", systemImage: "square.stack", description: Text("Add a music folder in Settings to get started."))
                    .frame(maxHeight: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(albums) { album in
                        NavigationLink(value: album) {
                            AlbumCard(
                                name: album.name,
                                artist: album.artistName ?? "Unknown Artist",
                                artwork: album.artworkData.flatMap { NSImage(data: $0) }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
                .animation(.default, value: albums.count)
            }
        }
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
    }
}
```

**Step 2: Build to verify**

Run: `cd /Users/nicu/Projects/linnet && xcodebuild build -project Linnet.xcodeproj -scheme Linnet -configuration Debug 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```
feat(albums): add navigation from AlbumGridView to AlbumDetailView
```

---

### Task 6: ArtistDetailView — Real Data

Rewrite ArtistDetailView to accept an `Artist` model and display real albums.

**Files:**
- Modify: `Linnet/Views/ArtistDetailView.swift`

**Context:**
- Current view accepts `artistName: String` with hardcoded "Album 1-3" placeholders (lines 41-43)
- Artist model has: `name`, `albums: [Album]`, `tracks: [Track]`
- Album model has: `name`, `artistName`, `year`, `artworkData`, `tracks`
- Play button should play all artist tracks
- Each album card should navigate to `AlbumDetailView`

**Step 1: Rewrite ArtistDetailView**

Replace the entire file content:

```swift
import SwiftUI
import LinnetLibrary

struct ArtistDetailView: View {
    let artist: Artist
    @Environment(PlayerViewModel.self) private var player

    private var allTracks: [Track] {
        artist.tracks.sorted {
            ($0.album?.name ?? "", $0.discNumber, $0.trackNumber) < ($1.album?.name ?? "", $1.discNumber, $1.trackNumber)
        }
    }

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
                        Text(artist.name)
                            .font(.system(size: 28, weight: .bold))

                        Text("\(artist.albums.count) albums, \(artist.tracks.count) songs")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)

                        HStack(spacing: 12) {
                            Button("Play") {
                                if let first = allTracks.first {
                                    player.playTrack(first, queue: allTracks, startingAt: 0)
                                }
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Shuffle") {
                                let shuffled = allTracks.shuffled()
                                if let first = shuffled.first {
                                    player.playTrack(first, queue: shuffled, startingAt: 0)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(20)

                // Albums section
                if !artist.albums.isEmpty {
                    Text("Albums")
                        .font(.headline)
                        .padding(.horizontal, 20)

                    let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(artist.albums.sorted(by: { ($0.year ?? 0) > ($1.year ?? 0) })) { album in
                            NavigationLink(value: album) {
                                AlbumCard(
                                    name: album.name,
                                    artist: artist.name,
                                    artwork: album.artworkData.flatMap { NSImage(data: $0) }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
    }
}
```

**Step 2: Build to verify**

Run: `cd /Users/nicu/Projects/linnet && xcodebuild build -project Linnet.xcodeproj -scheme Linnet -configuration Debug 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```
feat(artists): rewrite ArtistDetailView with real data and playback
```

---

### Task 7: ArtistListView — Navigation to ArtistDetailView

Add `NavigationLink` around artist rows.

**Files:**
- Modify: `Linnet/Views/ArtistListView.swift`

**Context:**
- Current view uses `ForEach(artists)` rendering rows with name and album count (lines 14-33)
- Wrap each row in `NavigationLink(value: artist)`
- Register `.navigationDestination(for: Artist.self)` here

**Step 1: Rewrite ArtistListView**

Replace the entire file content:

```swift
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
        .navigationDestination(for: Artist.self) { artist in
            ArtistDetailView(artist: artist)
        }
    }
}
```

**Step 2: Build to verify**

Run: `cd /Users/nicu/Projects/linnet && xcodebuild build -project Linnet.xcodeproj -scheme Linnet -configuration Debug 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```
feat(artists): add navigation from ArtistListView to ArtistDetailView
```

---

### Task 8: ListenNowView — Click Handlers

Make recently added tracks playable and album cards navigable.

**Files:**
- Modify: `Linnet/Views/ListenNowView.swift`

**Context:**
- Recently added tracks section (lines 22-51): each track card should play on click
- Albums section (lines 54-65): each album card should navigate to AlbumDetailView
- `@Query(sort: \Track.dateAdded, order: .reverse)` provides `recentTracks` (line 7)
- Need `@Environment(PlayerViewModel.self)` for playback
- Need `.navigationDestination(for: Album.self)` for album navigation

**Step 1: Add environment and click handlers**

Replace the entire file content:

```swift
import SwiftUI
import SwiftData
import LinnetLibrary

struct ListenNowView: View {
    @Query(sort: \Album.name) private var albums: [Album]
    @Query(sort: \Track.dateAdded, order: .reverse) private var recentTracks: [Track]
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("Listen Now")
                    .font(.largeTitle.bold())
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                if albums.isEmpty && recentTracks.isEmpty {
                    ContentUnavailableView("Welcome to Linnet", systemImage: "music.note.house", description: Text("Add a music folder in Settings to get started."))
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    if !recentTracks.isEmpty {
                        let displayedTracks = Array(recentTracks.prefix(10))
                        HorizontalScrollRow(title: "Recently Added") {
                            ForEach(Array(displayedTracks.enumerated()), id: \.element.id) { index, track in
                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.quaternary)
                                        .frame(width: 160, height: 160)
                                        .overlay {
                                            if let artData = track.artworkData, let img = NSImage(data: artData) {
                                                Image(nsImage: img)
                                                    .resizable()
                                                    .scaledToFill()
                                            } else {
                                                Image(systemName: "music.note")
                                                    .font(.system(size: 30))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    Text(track.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                    Text(track.artist?.name ?? "Unknown")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(width: 160)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    player.playTrack(track, queue: displayedTracks, startingAt: index)
                                }
                            }
                        }
                    }

                    if !albums.isEmpty {
                        HorizontalScrollRow(title: "Albums") {
                            ForEach(albums.prefix(10)) { album in
                                NavigationLink(value: album) {
                                    AlbumCard(
                                        name: album.name,
                                        artist: album.artistName ?? "Unknown",
                                        artwork: album.artworkData.flatMap { NSImage(data: $0) }
                                    )
                                    .frame(width: 160)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HorizontalScrollRow(title: "AI Suggestions") {
                        ForEach(1...6, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.quaternary)
                                    .frame(width: 160, height: 160)
                                    .overlay {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 30))
                                            .foregroundStyle(.secondary)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                Text("Set up AI")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text("Enable in Settings")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(width: 160)
                        }
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
    }
}
```

**Step 2: Build to verify**

Run: `cd /Users/nicu/Projects/linnet && xcodebuild build -project Linnet.xcodeproj -scheme Linnet -configuration Debug 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```
feat(listen-now): add track playback and album navigation to ListenNowView
```

---

### Task 9: QueuePanel — Real Data from PlayerViewModel

Replace hardcoded dummy tracks with real queue data from PlayerViewModel.

**Files:**
- Modify: `Linnet/Views/QueuePanel.swift`

**Context:**
- Current view has hardcoded `upNext` and `history` arrays (lines 6-14)
- `PlayerViewModel` has `queue: PlaybackQueue` which exposes `current`, `upcoming`, and `count`
- `PlaybackQueue` stores file paths as `[String]` — we also have `queuedTracks: [Track]` in PlayerViewModel
- We need to expose queue track info from PlayerViewModel
- `QueuePanel` already accepts `@Binding var isShowing: Bool` (line 4)
- Clear button (line 22) should call a queue clear method

**Step 1: Add queue accessors to PlayerViewModel**

In `Linnet/ViewModels/PlayerViewModel.swift`, add these computed properties after the `isPlaying` property (after line 19):

```swift
var currentQueueTrack: Track? {
    guard currentTrackIndex >= 0, currentTrackIndex < queuedTracks.count else { return nil }
    return queuedTracks[currentTrackIndex]
}

var upcomingTracks: [Track] {
    guard currentTrackIndex + 1 < queuedTracks.count else { return [] }
    return Array(queuedTracks[(currentTrackIndex + 1)...])
}

var queueCount: Int { queuedTracks.count }
```

Add a `clearQueue()` method after `playTrack`:

```swift
func clearQueue() {
    queue.clear()
    let currentTrack = currentQueueTrack
    queuedTracks = currentTrack.map { [$0] } ?? []
    currentTrackIndex = 0
}
```

**Step 2: Rewrite QueuePanel**

Replace the entire file content:

```swift
import SwiftUI
import LinnetLibrary

struct QueuePanel: View {
    @Binding var isShowing: Bool
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Queue")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    player.clearQueue()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
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
                    if let current = player.currentQueueTrack {
                        Section {
                            queueRow(title: current.title, artist: current.artist?.name ?? "Unknown", artwork: current.artworkData, isCurrent: true)
                                .padding(.horizontal)
                        } header: {
                            sectionHeader("Now Playing")
                        }
                    }

                    // Up Next
                    let upcoming = player.upcomingTracks
                    if !upcoming.isEmpty {
                        Section {
                            ForEach(upcoming) { track in
                                queueRow(title: track.title, artist: track.artist?.name ?? "Unknown", artwork: track.artworkData, isCurrent: false)
                                    .padding(.horizontal)
                            }
                        } header: {
                            sectionHeader("Up Next \u{2014} \(upcoming.count) songs")
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .frame(width: 300)
        .background(.ultraThinMaterial)
    }

    private func queueRow(title: String, artist: String, artwork: Data?, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(width: 36, height: 36)
                .overlay {
                    if let data = artwork, let img = NSImage(data: data) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading) {
                Text(title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                Text(artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal)
    }
}
```

**Step 3: Build to verify**

Run: `cd /Users/nicu/Projects/linnet && xcodebuild build -project Linnet.xcodeproj -scheme Linnet -configuration Debug 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```
feat(queue): wire QueuePanel to real playback queue data
```

---

### Task 10: NowPlayingBar — Queue Toggle

Wire the queue button in NowPlayingBar to show/hide the QueuePanel.

**Files:**
- Modify: `Linnet/Views/NowPlayingBar.swift`
- Modify: `Linnet/ContentView.swift`

**Context:**
- NowPlayingBar has a queue button with empty handler (line 94)
- QueuePanel accepts `@Binding var isShowing: Bool`
- The queue panel should appear as a trailing overlay or sheet — a `.popover` anchored to the queue button works well for macOS
- We manage `showQueue` state in ContentView and pass it down, since QueuePanel needs to overlay the main content

**Step 1: Add queue toggle to NowPlayingBar**

The simplest approach: use a `.popover` on the queue button in NowPlayingBar. Add a `@State` for the popover:

In `NowPlayingBar.swift`, add state at the top of the struct (after line 4):

```swift
@State private var showQueue = false
```

Replace the queue button (lines 93-98):

```swift
Button(action: { showQueue.toggle() }) {
    Image(systemName: "list.bullet")
        .font(.system(size: 14))
        .foregroundStyle(showQueue ? .tint : .primary)
}
.buttonStyle(.plain)
.popover(isPresented: $showQueue, arrowEdge: .top) {
    QueuePanel(isShowing: $showQueue)
}
```

**Step 2: Build to verify**

Run: `cd /Users/nicu/Projects/linnet && xcodebuild build -project Linnet.xcodeproj -scheme Linnet -configuration Debug 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```
feat(now-playing): wire queue button to show QueuePanel popover
```

---

### Task 11: Final Build and Integration Verification

Verify the entire app builds and all pieces work together.

**Files:** None (verification only)

**Step 1: Clean build**

Run: `cd /Users/nicu/Projects/linnet && xcodegen generate && xcodebuild clean build -project Linnet.xcodeproj -scheme Linnet -configuration Debug 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

**Step 2: Run package tests**

Run:
```bash
swift test --package-path Packages/LinnetAudio 2>&1 | tail -5
swift test --package-path Packages/LinnetLibrary 2>&1 | tail -5
swift test --package-path Packages/LinnetAI 2>&1 | tail -5
```
Expected: All tests pass (existing tests should not break)

**Step 3: Commit any final adjustments**

If any build or test issues were found and fixed, commit them:
```
fix: resolve build issues from v0.1 playback wiring integration
```
