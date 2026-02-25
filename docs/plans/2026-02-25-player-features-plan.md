# Player Features Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add like/dislike, repeat mode UI, enhanced queue with side pane, navigation breadcrumbs, and improved playlist creation to Linnet.

**Architecture:** SwiftUI views with SwiftData models. Player state managed through `PlayerViewModel` (Observable). Queue backend in `PlaybackQueue` (LinnetAudio package). Navigation via `NavigationSplitView` + `NavigationStack` with `NavigationPath`.

**Tech Stack:** SwiftUI, SwiftData, macOS (AppKit interop), LinnetAudio/LinnetLibrary packages, XcodeGen for project generation.

**Important:** After creating or deleting any Swift file, run `xcodegen generate` to regenerate the Xcode project. Build with: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | tail -5`

---

### Task 1: Add likedStatus to Track model

**Files:**
- Modify: `Packages/LinnetLibrary/Sources/LinnetLibrary/Models/Track.swift:36` (after `playCount`)

**Step 1: Add the property**

In `Track.swift`, after line 36 (`public var playCount: Int`), add:

```swift
public var likedStatus: Int = 0  // -1 = disliked, 0 = neutral, 1 = liked
```

SwiftData handles schema migration automatically for new properties with defaults.

**Step 2: Build to verify**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```
feat: add likedStatus property to Track model
```

---

### Task 2: Add like/dislike buttons to NowPlayingBar

**Files:**
- Modify: `Linnet/Views/NowPlayingBar.swift:98-101` (between track info frame and Spacer)
- Modify: `Linnet/ViewModels/PlayerViewModel.swift` (add toggleLike method)

**Step 1: Add toggleLike/toggleDislike to PlayerViewModel**

In `PlayerViewModel.swift`, add after the `clearQueue()` method (around line 184):

```swift
func toggleLike() {
    guard let track = currentQueueTrack else { return }
    track.likedStatus = track.likedStatus == 1 ? 0 : 1
    try? modelContext?.save()
}

func toggleDislike() {
    guard let track = currentQueueTrack else { return }
    track.likedStatus = track.likedStatus == -1 ? 0 : -1
    try? modelContext?.save()
}
```

**Step 2: Add buttons to NowPlayingBar**

In `NowPlayingBar.swift`, after the `.frame(width: 160, alignment: .leading)` line (line 99) and before the first `Spacer()` (line 101), insert:

```swift
// Like/Dislike
HStack(spacing: 8) {
    Button(action: { player.toggleDislike() }) {
        Image(systemName: player.currentQueueTrack?.likedStatus == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            .font(.system(size: 14))
            .foregroundStyle(player.currentQueueTrack?.likedStatus == -1 ? .red : .secondary)
    }
    .buttonStyle(.plain)
    .disabled(player.currentQueueTrack == nil)

    Button(action: { player.toggleLike() }) {
        Image(systemName: player.currentQueueTrack?.likedStatus == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
            .font(.system(size: 14))
            .foregroundStyle(player.currentQueueTrack?.likedStatus == 1 ? .accentColor : .secondary)
    }
    .buttonStyle(.plain)
    .disabled(player.currentQueueTrack == nil)
}
```

**Step 3: Build to verify**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```
feat: add like/dislike buttons to now playing bar
```

---

### Task 3: Add like/dislike to context menus

**Files:**
- Create: `Linnet/Views/Components/LikeDislikeMenu.swift`
- Modify: `Linnet/Views/ArtistDetailView.swift:363-370` (ArtistTrackRow context menu)
- Modify: `Linnet/Views/SongsListView.swift:371` (contextMenuContent)
- Modify: `Linnet/Views/AlbumDetailView.swift:210` (contextMenuContent)
- Modify: `Linnet/Views/QueuePanel.swift` (queue row)

**Step 1: Create reusable LikeDislikeMenu component**

Create `Linnet/Views/Components/LikeDislikeMenu.swift`:

```swift
import SwiftUI
import LinnetLibrary

struct LikeDislikeMenu: View {
    let tracks: [Track]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let allLiked = tracks.allSatisfy { $0.likedStatus == 1 }
        let allDisliked = tracks.allSatisfy { $0.likedStatus == -1 }

        Button(allLiked ? "Remove Like" : "Like") {
            let newStatus = allLiked ? 0 : 1
            for track in tracks { track.likedStatus = newStatus }
            try? modelContext.save()
        }
        Button(allDisliked ? "Remove Dislike" : "Dislike") {
            let newStatus = allDisliked ? 0 : -1
            for track in tracks { track.likedStatus = newStatus }
            try? modelContext.save()
        }
    }
}
```

**Step 2: Add to ArtistTrackRow context menu**

In `ArtistDetailView.swift`, in ArtistTrackRow's context menu (around line 363-370), add before the Divider/Remove:

```swift
LikeDislikeMenu(tracks: [track])
Divider()
```

**Step 3: Add to SongsListView context menu**

In `SongsListView.swift`, find `contextMenuContent(for:)` function. Add `LikeDislikeMenu` and `Divider()` before the existing Remove button. The function resolves `ids` to tracks — pass those tracks to `LikeDislikeMenu`.

**Step 4: Add to AlbumDetailView context menu**

In `AlbumDetailView.swift`, find `contextMenuContent(for:)` function. Same pattern — add `LikeDislikeMenu` before Remove.

**Step 5: Add to ListenNowView context menus**

In `ListenNowView.swift`, find the context menus (lines 96, 143). Add `LikeDislikeMenu(tracks: [track])` and `Divider()`.

**Step 6: Add to AlbumGridView context menu**

In `AlbumGridView.swift`, find the context menu (line 105). Add `LikeDislikeMenu(tracks: album.tracks)` for album-level like.

**Step 7: Run xcodegen and build**

Run: `xcodegen generate && xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 8: Commit**

```
feat: add like/dislike to all track context menus
```

---

### Task 4: Show like indicator in track rows

**Files:**
- Modify: `Linnet/Views/ArtistDetailView.swift:327-350` (ArtistTrackRow body)
- Modify: `Linnet/Views/SongsListView.swift` (table columns or row view)

**Step 1: Add heart icon to ArtistTrackRow**

In `ArtistDetailView.swift`, in ArtistTrackRow's body HStack, after the track title VStack and before `Spacer(minLength: 12)` (around line 344-345), add:

```swift
if track.likedStatus == 1 {
    Image(systemName: "heart.fill")
        .font(.system(size: 10))
        .foregroundStyle(.red)
}
```

**Step 2: Add liked column to SongsListView**

In `SongsListView.swift`, check if it uses a `Table` — if so, add a narrow column with heart icon. If it uses a custom row layout, add the heart icon inline similar to ArtistTrackRow.

**Step 3: Add dimming for disliked tracks**

In ArtistTrackRow, wrap the HStack content in an `.opacity(track.likedStatus == -1 ? 0.5 : 1.0)` modifier.

**Step 4: Build to verify**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```
feat: show like indicator in track rows, dim disliked tracks
```

---

### Task 5: Add Liked Songs to sidebar

**Files:**
- Modify: `Linnet/Views/SidebarItem.swift:3-9` (add case)
- Modify: `Linnet/Views/SidebarItem.swift:12-14` (add to allLibraryItems)
- Modify: `Linnet/Views/SidebarItem.swift:16-37` (add label and systemImage)
- Modify: `Linnet/Views/ContentArea.swift` or wherever SidebarItem drives content (add case for likedSongs)

**Step 1: Add likedSongs case to SidebarItem**

In `SidebarItem.swift`, add after `case songs`:

```swift
case likedSongs
```

Add to `allLibraryItems` after `.songs`:

```swift
static let allLibraryItems: [SidebarItem] = [
    .songs, .likedSongs, .recentlyAdded, .artists, .albums, .folders
]
```

Add label and systemImage:

```swift
case .likedSongs: return "Liked Songs"
// ...
case .likedSongs: return "heart.fill"
```

**Step 2: Add content view for likedSongs**

Find where `SidebarItem` drives the detail content (likely `ContentArea` view or a switch in `ContentView`). Add a case for `.likedSongs` that shows a filtered SongsListView with a `#Predicate<Track> { $0.likedStatus == 1 }` or passes a filter parameter.

**Step 3: Build to verify**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```
feat: add Liked Songs to sidebar
```

---

### Task 6: Add repeat mode UI

**Files:**
- Modify: `Linnet/ViewModels/PlayerViewModel.swift` (expose repeatMode, add toggle)
- Modify: `Linnet/Views/NowPlayingBar.swift:127-128` (add repeat button after forward)

**Step 1: Add repeat mode to PlayerViewModel**

In `PlayerViewModel.swift`, add a computed property and toggle method:

```swift
var repeatMode: RepeatMode {
    queue.repeatMode
}

func toggleRepeatMode() {
    switch queue.repeatMode {
    case .off: queue.repeatMode = .all
    case .all: queue.repeatMode = .one
    case .one: queue.repeatMode = .off
    }
}
```

Note: `RepeatMode` is defined in LinnetAudio — make sure the import is present.

**Step 2: Add repeat button to NowPlayingBar**

In `NowPlayingBar.swift`, after the forward button (line ~127) and before the closing `}` of the HStack(spacing: 24), add:

```swift
Button(action: { player.toggleRepeatMode() }) {
    Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
        .font(.system(size: controlSize - 4))
        .foregroundColor(player.repeatMode == .off ? .primary : .accentColor)
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if player.repeatMode != .off {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 4, height: 4)
                    .offset(y: 2)
            }
        }
}
.buttonStyle(.plain)
```

**Step 3: Import LinnetAudio in NowPlayingBar if needed**

`RepeatMode` is in LinnetAudio. The NowPlayingBar accesses it through `PlayerViewModel.repeatMode` which returns `RepeatMode`. If the compiler complains, add `import LinnetAudio` to NowPlayingBar.swift.

**Step 4: Build to verify**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```
feat: add repeat mode toggle button to now playing bar
```

---

### Task 7: Add queue remove and reorder support to PlayerViewModel

**Files:**
- Modify: `Packages/LinnetAudio/Sources/LinnetAudio/PlaybackQueue.swift` (add remove method)
- Modify: `Linnet/ViewModels/PlayerViewModel.swift` (add removeFromQueue, moveInQueue)

**Step 1: Add remove(at:) to PlaybackQueue**

In `PlaybackQueue.swift`, add after the `move(from:to:)` method (line 77):

```swift
/// Remove a track at the given offset from upcoming tracks.
/// offset 0 = first upcoming track (currentIndex + 1).
public mutating func remove(at offset: Int) {
    let adjustedIndex = currentIndex + 1 + offset
    guard adjustedIndex < tracks.count else { return }
    tracks.remove(at: adjustedIndex)
}
```

**Step 2: Add methods to PlayerViewModel**

In `PlayerViewModel.swift`, add after `clearQueue()`:

```swift
func removeFromQueue(at offsets: IndexSet) {
    // Remove from upcoming (offsets are relative to upcomingTracks)
    for offset in offsets.sorted().reversed() {
        queue.remove(at: offset)
        let trackIndex = queue.currentIndex + 1 + offset
        if trackIndex < queuedTracks.count {
            queuedTracks.remove(at: trackIndex)
        }
    }
}

func moveInQueue(from source: IndexSet, to destination: Int) {
    // source/destination are relative to upcoming tracks
    guard let sourceIndex = source.first else { return }
    queue.move(from: sourceIndex, to: destination > sourceIndex ? destination - 1 : destination)

    // Mirror in queuedTracks
    let adjustedSource = queue.currentIndex + 1 + sourceIndex
    let adjustedDest = queue.currentIndex + 1 + (destination > sourceIndex ? destination - 1 : destination)
    guard adjustedSource < queuedTracks.count else { return }
    let track = queuedTracks.remove(at: adjustedSource)
    queuedTracks.insert(track, at: min(adjustedDest, queuedTracks.count))
}
```

**Step 3: Build to verify**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```
feat: add queue remove and reorder support
```

---

### Task 8: Enhance QueuePanel with remove, reorder, and context menus

**Files:**
- Modify: `Linnet/Views/QueuePanel.swift`

**Step 1: Rewrite QueuePanel with enhanced features**

Replace the "Up Next" section in `QueuePanel.swift` to support drag-to-reorder, hover-to-remove, and context menus. The key changes:

In the "Up Next" ForEach, change from a simple `ForEach` to one that supports `.onMove` and `.onDelete`:

```swift
// Up Next
let upcoming = player.upcomingTracks
if !upcoming.isEmpty {
    Section {
        ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, track in
            queueRow(title: track.title, artist: track.artist?.name ?? "Unknown", artwork: track.artworkData, isCurrent: false)
                .padding(.horizontal)
                .contextMenu {
                    Button("Play") {
                        // Jump to this track: advance queue to this index
                        for _ in 0...index {
                            _ = player.queue.advance()
                        }
                        if let current = player.queue.current {
                            let queueIndex = player.queue.currentIndex
                            if queueIndex < player.queuedTracks.count {
                                player.updateMetadataPublic(for: player.queuedTracks[queueIndex])
                            }
                            player.loadAndPlay(filePath: current)
                        }
                    }
                    Button("Remove from Queue", role: .destructive) {
                        player.removeFromQueue(at: IndexSet(integer: index))
                    }
                }
                .overlay(alignment: .trailing) {
                    Button(action: {
                        player.removeFromQueue(at: IndexSet(integer: index))
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                    .opacity(0)
                    .onHover { hovering in
                        // Show on hover — handled by parent
                    }
                }
        }
        .onMove { source, destination in
            player.moveInQueue(from: source, to: destination)
        }
    } header: {
        sectionHeader("Up Next — \(upcoming.count) songs")
    }
}
```

Note: The hover-to-show-X-button is tricky in SwiftUI. A simpler approach: always show a subtle X button on the trailing edge of each row. Or use `.swipeActions` if available. Keep it simple — always-visible subtle X button is fine.

Actually, simplify: just add a trailing X button that's always visible (secondary color, small), plus the context menu. Skip the hover complexity.

**Step 2: Make queuedTracks accessible**

`PlayerViewModel.queuedTracks` is currently `private`. We need it accessible for the queue panel play-from-queue feature. Either:
- Make it `private(set)` (already may be if it's used by `upcomingTracks`)
- Or just use the existing `upcomingTracks` computed property

Check: `upcomingTracks` already returns `Array(queuedTracks[(queue.currentIndex + 1)...])`. The "play from queue" feature needs to advance the queue. Simplest approach: add a `playFromQueue(at upcomingIndex: Int)` method to PlayerViewModel:

```swift
func playFromQueue(at upcomingIndex: Int) {
    let targetIndex = queue.currentIndex + 1 + upcomingIndex
    guard targetIndex < queuedTracks.count else { return }
    // Set queue position
    queue.currentIndex = targetIndex // Need to make this settable
    let track = queuedTracks[targetIndex]
    updateMetadata(for: track)
    loadAndPlay(filePath: track.filePath)
}
```

This requires making `currentIndex` settable or adding a `jumpTo(index:)` method to `PlaybackQueue`. Add to PlaybackQueue:

```swift
public mutating func jumpTo(index: Int) {
    guard index < tracks.count else { return }
    history.append(currentIndex)
    currentIndex = index
}
```

Then in PlayerViewModel:

```swift
func playFromQueue(at upcomingIndex: Int) {
    let targetIndex = queue.currentIndex + 1 + upcomingIndex
    guard targetIndex < queuedTracks.count else { return }
    queue.jumpTo(index: targetIndex)
    updateMetadata(for: queuedTracks[targetIndex])
    loadAndPlay(filePath: queuedTracks[targetIndex].filePath)
}
```

**Step 3: Build to verify**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```
feat: enhance queue panel with remove, reorder, and context menus
```

---

### Task 9: Add queue side pane to ContentView

**Files:**
- Create: `Linnet/Views/QueueSidePane.swift`
- Modify: `Linnet/ContentView.swift`
- Modify: `Linnet/Views/NowPlayingBar.swift` (add side pane toggle button)

**Step 1: Create QueueSidePane wrapper**

Create `Linnet/Views/QueueSidePane.swift`:

```swift
import SwiftUI
import LinnetLibrary

struct QueueSidePane: View {
    @Binding var isShowing: Bool
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        VStack(spacing: 0) {
            QueuePanel(isShowing: $isShowing)
        }
        .frame(width: 300)
        .background(.ultraThinMaterial)
    }
}
```

**Step 2: Add side pane state and layout to ContentView**

In `ContentView.swift`, add state:

```swift
@AppStorage("showQueueSidePane") private var showQueueSidePane = false
```

Wrap the existing `NavigationSplitView` detail + NowPlayingBar in an HStack with the side pane:

The current structure is:
```
NavigationSplitView {
    SidebarView
} detail: {
    NavigationStack { ... }
}
.safeAreaInset(edge: .bottom) { NowPlayingBar() }
```

Change to add the side pane as a trailing panel. The side pane should sit to the right of the NavigationSplitView content, above the NowPlayingBar. Use an HStack or overlay approach:

```swift
NavigationSplitView {
    SidebarView(selectedItem: $selectedSidebarItem)
} detail: {
    HStack(spacing: 0) {
        NavigationStack(path: $navigationPath) {
            // ... existing content ...
        }

        if showQueueSidePane {
            Divider()
            QueueSidePane(isShowing: $showQueueSidePane)
        }
    }
}
```

**Step 3: Add keyboard shortcut**

In ContentView, add to the view chain:

```swift
.keyboardShortcut("Q", modifiers: [.command, .shift])
```

Actually, keyboard shortcuts need to be on a Button or in `.commands`. Add to LinnetApp.swift commands or use `.onKeyPress`. Simplest: add a hidden button or use the existing keyboard shortcut mechanism. Check how existing shortcuts work in LinnetApp.swift.

Alternative: Add `.onReceive` for a notification, similar to existing patterns. Or add to the app's `.commands` modifier.

**Step 4: Add side pane toggle to NowPlayingBar**

In `NowPlayingBar.swift`, add a new button next to the existing queue popover button (or replace it with a dual-purpose button). Add after the EQ button (around line 175), before the queue popover button:

```swift
// Queue side pane toggle
Button(action: {
    NotificationCenter.default.post(name: .toggleQueueSidePane, object: nil)
}) {
    Image(systemName: "sidebar.trailing")
        .font(.system(size: 14))
}
.buttonStyle(.plain)
```

Add the notification name:

```swift
static let toggleQueueSidePane = Notification.Name("toggleQueueSidePane")
```

In ContentView, add the receiver:

```swift
.onReceive(NotificationCenter.default.publisher(for: .toggleQueueSidePane)) { _ in
    showQueueSidePane.toggle()
}
```

**Step 5: Run xcodegen and build**

Run: `xcodegen generate && xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```
feat: add queue side pane with toggle button
```

---

### Task 10: Add navigation breadcrumbs

**Files:**
- Create: `Linnet/Views/BreadcrumbBar.swift`
- Modify: `Linnet/ContentView.swift`

**Step 1: Create BreadcrumbBar view**

Create `Linnet/Views/BreadcrumbBar.swift`:

```swift
import SwiftUI

struct BreadcrumbItem: Identifiable {
    let id = UUID()
    let title: String
    let level: Int
}

struct BreadcrumbBar: View {
    let items: [BreadcrumbItem]
    let onNavigate: (Int) -> Void  // called with level to pop to

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                if index < items.count - 1 {
                    // Clickable ancestor
                    Button(item.title) {
                        onNavigate(item.level)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.accent)
                } else {
                    // Current page — not clickable
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
}
```

**Step 2: Add breadcrumb tracking state to ContentView**

In `ContentView.swift`, add state variables:

```swift
@State private var breadcrumbs: [BreadcrumbItem] = []
@State private var navigationValues: [AnyHashable] = []
```

**Step 3: Update navigation destinations to track breadcrumbs**

Modify the `navigationDestination` closures to record breadcrumb info. The challenge: `navigationDestination` is a view builder, not a callback. We need to track pushes separately.

Create a helper method in ContentView:

```swift
private func pushNavigation<T: Hashable>(_ value: T, title: String) {
    navigationPath.append(value)
    let level = navigationPath.count
    breadcrumbs.append(BreadcrumbItem(title: title, level: level))
    navigationValues.append(value as! AnyHashable)
}
```

But wait — pushes happen from child views (e.g., ArtistDetailView pushes albums). We need a different approach.

Better approach: observe `navigationPath.count` changes and use notifications to communicate breadcrumb titles:

```swift
.onChange(of: navigationPath.count) { oldCount, newCount in
    if newCount < oldCount {
        // Popped — trim breadcrumbs
        breadcrumbs = Array(breadcrumbs.prefix(newCount + 1))  // +1 for root
        navigationValues = Array(navigationValues.prefix(newCount))
    }
    // Pushes are handled by notification from child views
}
```

Add a notification for registering breadcrumbs:

```swift
static let registerBreadcrumb = Notification.Name("registerBreadcrumb")
```

In `navigationDestination` closures, post the notification:

```swift
.navigationDestination(for: Album.self) { album in
    AlbumDetailView(album: album)
        .onAppear {
            NotificationCenter.default.post(
                name: .registerBreadcrumb,
                object: nil,
                userInfo: ["title": album.name, "value": album]
            )
        }
}
```

And receive it in ContentView:

```swift
.onReceive(NotificationCenter.default.publisher(for: .registerBreadcrumb)) { notification in
    guard let title = notification.userInfo?["title"] as? String else { return }
    let level = navigationPath.count
    // Only add if not already tracked at this level
    if breadcrumbs.count <= level {
        breadcrumbs.append(BreadcrumbItem(title: title, level: level))
        if let value = notification.userInfo?["value"] as? AnyHashable {
            navigationValues.append(value)
        }
    }
}
```

**Step 4: Set root breadcrumb from sidebar selection**

```swift
.onChange(of: selectedSidebarItem) { _, newItem in
    navigationPath = NavigationPath()
    breadcrumbs = [BreadcrumbItem(title: newItem?.label ?? "Browse", level: 0)]
    navigationValues = []
    // ... existing code ...
}
```

Initialize on appear too:

```swift
.onAppear {
    breadcrumbs = [BreadcrumbItem(title: selectedSidebarItem?.label ?? "Browse", level: 0)]
}
```

**Step 5: Add BreadcrumbBar to the view**

In ContentView, add the breadcrumb bar above the content inside the NavigationStack. Place it before the `ContentArea`:

```swift
NavigationStack(path: $navigationPath) {
    VStack(spacing: 0) {
        if breadcrumbs.count > 1 {
            BreadcrumbBar(items: breadcrumbs) { level in
                // Pop to level
                let popCount = navigationPath.count - level
                for _ in 0..<popCount {
                    navigationPath.removeLast()
                }
            }
            Divider()
        }
        ContentArea(tab: selectedTab, sidebarItem: selectedSidebarItem, highlightedTrackID: $highlightedTrackID)
    }
    .navigationDestination(for: Album.self) { ... }
    .navigationDestination(for: Artist.self) { ... }
}
```

**Step 6: Handle back navigation from ArtistDetailView to album**

In `ArtistDetailView.swift`, when navigating to an album, also post the breadcrumb notification. The `onNavigate` closure already calls `navigationPath.append(album)`. Breadcrumb will be registered via the `navigationDestination` `.onAppear`.

**Step 7: Run xcodegen and build**

Run: `xcodegen generate && xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 8: Commit**

```
feat: add navigation breadcrumbs
```

---

### Task 11: Create NewPlaylistSheet

**Files:**
- Create: `Linnet/Views/NewPlaylistSheet.swift`

**Step 1: Create NewPlaylistSheet**

Create `Linnet/Views/NewPlaylistSheet.swift`:

```swift
import SwiftUI
import SwiftData
import LinnetLibrary

struct NewPlaylistSheet: View {
    let tracks: [Track]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var playlistName: String = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Playlist")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Name field
            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Playlist name", text: $playlistName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFieldFocused)
            }
            .padding()

            Divider()

            // Track preview
            if !tracks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(tracks.count) songs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    List {
                        ForEach(tracks) { track in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(track.title)
                                        .font(.system(size: 13))
                                        .lineLimit(1)
                                    Text(track.artist?.name ?? "Unknown Artist")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Create Playlist") {
                    createPlaylist()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(playlistName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 450)
        .onAppear {
            playlistName = suggestedName()
            nameFieldFocused = true
        }
    }

    private func suggestedName() -> String {
        let artists = Set(tracks.compactMap { $0.artist?.name })
        let albums = Set(tracks.compactMap { $0.album?.name })

        if artists.count == 1, let artist = artists.first {
            return "Best of \(artist)"
        } else if albums.count == 1, let album = albums.first {
            return "\(album) Selection"
        }
        return "New Playlist"
    }

    private func createPlaylist() {
        let name = playlistName.trimmingCharacters(in: .whitespaces)
        let playlist = Playlist(name: name)
        modelContext.insert(playlist)

        for (i, track) in tracks.enumerated() {
            let entry = PlaylistEntry(track: track, order: i)
            entry.playlist = playlist
            playlist.entries.append(entry)
            modelContext.insert(entry)
        }
        try? modelContext.save()
    }
}
```

**Step 2: Run xcodegen and build**

Run: `xcodegen generate && xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```
feat: add new playlist sheet with suggested names
```

---

### Task 12: Wire NewPlaylistSheet into AddToPlaylistMenu

**Files:**
- Modify: `Linnet/Views/Components/AddToPlaylistMenu.swift`

**Step 1: Replace inline creation with sheet**

The challenge: `Menu` can't present a `.sheet` directly. Solution: wrap the menu in a view that manages sheet state.

Replace `AddToPlaylistMenu` with:

```swift
import SwiftUI
import SwiftData
import LinnetLibrary

struct AddToPlaylistMenu: View {
    let tracks: [Track]

    @Query(sort: \Playlist.name) private var playlists: [Playlist]
    @Environment(\.modelContext) private var modelContext
    @State private var showNewPlaylistSheet = false

    var body: some View {
        Menu("Add to Playlist") {
            ForEach(playlists) { playlist in
                Button(playlist.name) {
                    addTracks(to: playlist)
                }
            }
            if !playlists.isEmpty { Divider() }
            Button("New Playlist...") {
                showNewPlaylistSheet = true
            }
        }
        .sheet(isPresented: $showNewPlaylistSheet) {
            NewPlaylistSheet(tracks: tracks)
        }
    }

    private func addTracks(to playlist: Playlist) {
        let startOrder = playlist.entries.count
        for (i, track) in tracks.enumerated() {
            let entry = PlaylistEntry(track: track, order: startOrder + i)
            entry.playlist = playlist
            playlist.entries.append(entry)
            modelContext.insert(entry)
        }
        try? modelContext.save()
    }
}
```

Note: `.sheet` on a `Menu` might not work in all SwiftUI contexts. If it doesn't, use a `background` modifier with an empty view that presents the sheet, triggered by the same binding. This is a known SwiftUI pattern:

```swift
Menu("Add to Playlist") { ... }
.background {
    Color.clear
        .sheet(isPresented: $showNewPlaylistSheet) {
            NewPlaylistSheet(tracks: tracks)
        }
}
```

**Step 2: Build to verify**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```
feat: wire new playlist sheet into add-to-playlist menu
```

---

### Task 13: Final build verification and cleanup

**Step 1: Full clean build**

Run: `xcodebuild -scheme Linnet -destination 'platform=macOS' clean build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

**Step 2: Fix any warnings**

Check build output for warnings. Fix any that are related to changes made in this plan.

**Step 3: Final commit if any cleanup was needed**

```
chore: clean up warnings from player features
```
