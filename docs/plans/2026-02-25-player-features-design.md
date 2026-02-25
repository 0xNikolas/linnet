# Player Features Design

Date: 2026-02-25

## Overview

Five feature additions to Linnet: like/dislike system, repeat mode UI, queue side pane, navigation breadcrumbs, and improved playlist creation.

---

## 1. Like/Dislike System

### Data Model

Add to `Track` in LinnetLibrary:

```swift
var likedStatus: Int = 0  // -1 = disliked, 0 = neutral, 1 = liked
```

Int for SwiftData compatibility and easy predicate queries.

### UI Locations

**NowPlayingBar** — Two buttons between track info and playback controls:
- `hand.thumbsdown` / `hand.thumbsdown.fill` (dislike)
- `hand.thumbsup` / `hand.thumbsup.fill` (like)
- Tapping active state toggles back to neutral

**Context menus** — "Like" / "Dislike" toggle items on all track context menus (ArtistTrackRow, SongsTable, AlbumDetailView, QueuePanel).

**Track rows** — Small filled heart icon shown inline when `likedStatus == 1`. Disliked tracks get subtle dimmed style (reduced opacity).

### Sidebar

Add "Liked Songs" to `SidebarItem` — a smart collection querying `likedStatus == 1`. Shows in the library section.

---

## 2. Repeat Mode UI

### Backend

Already implemented: `PlaybackQueue.repeatMode` supports `.off`, `.one`, `.all`. `advance()` handles repeat logic.

### UI

Single button in NowPlayingBar, placed after the forward button:
- **Off**: `repeat` icon, default color
- **All**: `repeat` icon, accent color + dot indicator
- **One**: `repeat.1` icon, accent color + dot indicator
- Cycles: off -> all -> one -> off

### PlayerViewModel

Add `toggleRepeatMode()` method. Expose `repeatMode` as readable property.

---

## 3. Queue Side Pane

### Two Modes (coexist)

**Popover** — Existing queue popover, enhanced with remove/reorder.

**Side pane** — Toggled via button or Cmd+Shift+Q. Opens as trailing panel on the right side of ContentView.

### Side Pane Implementation

- Right-side panel overlay/split in ContentView
- Width: ~300pt, resizable
- State: `@AppStorage("showQueueSidePane")` for persistence
- Shares the same QueuePanel view (adapted for both contexts)

### Queue Enhancements (both modes)

- **Remove tracks**: X button on hover per row
- **Drag-to-reorder**: `.onMove` with ForEach, calls `queue.move(from:to:)` and mirrors in `queuedTracks`
- **Context menu per track**: Play, Remove from Queue
- PlayerViewModel needs `removeFromQueue(at:)` and `moveInQueue(from:to:)` methods

---

## 4. Navigation Breadcrumbs

### Challenge

`NavigationPath` is type-erased — can't read contents. Need parallel tracking.

### Data Structures

```swift
struct BreadcrumbItem: Identifiable {
    let id = UUID()
    let title: String      // "Artists", "Faun", "Midgard"
    let level: Int         // 0 = root, 1 = first push, etc.
}
```

Parallel `[any Hashable]` array stores actual navigation values for popping to specific levels.

### Tracking (ContentView)

- `@State private var breadcrumbs: [BreadcrumbItem]`
- `@State private var navigationValues: [any Hashable]`
- Root set from `selectedSidebarItem` name
- Append on push (via navigationDestination or helper)
- Trim on back navigation (observe `navigationPath.count` changes)

### Visual

Horizontal bar with `>` chevron separators. Current page is bold, non-clickable. Previous segments are accent-colored, clickable. Clicking pops the stack to that level by rebuilding NavigationPath from `navigationValues[0..<level]`.

### Placement

Inside NavigationStack, above content. Either via `.toolbar` or an overlay/VStack at the top.

---

## 5. New Playlist Sheet

### Current Behavior

`AddToPlaylistMenu` > "New Playlist..." creates "New Playlist" inline, no customization.

### New Behavior

"New Playlist..." opens a modal sheet with:
- **Suggested name** (auto-generated):
  - All same artist: "Best of {Artist}"
  - All same album: "{Album} Selection"
  - Mixed: "New Playlist"
- **Editable name field** — pre-filled, focused
- **Track list preview** — read-only list of tracks to be added
- **Create / Cancel buttons**

### Implementation

- New view: `NewPlaylistSheet(tracks: [Track], onComplete: (Playlist) -> Void)`
- Modify `AddToPlaylistMenu`: "New Playlist..." triggers sheet via binding
- Sheet state lifted to a wrapper or parent since `Menu` can't directly present sheets

---

## Implementation Order

1. Like/Dislike (model change first, then UI — foundation for AI features)
2. Repeat Mode (small, self-contained, high value)
3. Queue enhancements (remove/reorder in existing popover)
4. Queue side pane (builds on enhanced queue)
5. Navigation breadcrumbs (independent, moderate complexity)
6. New Playlist sheet (independent, moderate complexity)

## Key Files to Modify

- `Packages/LinnetLibrary/Sources/LinnetLibrary/Models/Track.swift` — add likedStatus
- `Linnet/ViewModels/PlayerViewModel.swift` — repeat mode, queue management methods
- `Linnet/Views/NowPlayingBar.swift` — like/dislike buttons, repeat button
- `Linnet/Views/QueuePanel.swift` — remove, reorder, dual-mode support
- `Linnet/ContentView.swift` — breadcrumbs tracking, side pane layout
- `Linnet/Views/Components/AddToPlaylistMenu.swift` — sheet trigger
- `Linnet/Views/SidebarView.swift` and `SidebarItem.swift` — liked songs item

## New Files

- `Linnet/Views/BreadcrumbBar.swift`
- `Linnet/Views/NewPlaylistSheet.swift`
- `Linnet/Views/QueueSidePane.swift` (wrapper for side pane presentation)
