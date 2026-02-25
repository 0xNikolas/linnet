# v0.1 Core Playback Wiring — Design

## Goal

Make Linnet a functional music player: users can browse their library, click tracks to play them, navigate album/artist detail views with real data, and see what's queued.

## Scope

Core playback only. Playlists, AI actions, drag-and-drop import, and settings wiring are deferred to v0.2.

## Architecture

**Approach:** Enhance `PlayerViewModel` with Track model awareness. All views pass SwiftData `Track` objects to `PlayerViewModel`, which handles file loading and metadata population. No new types or services needed.

**Key principle:** Views query SwiftData directly via `@Query`. Playback flows through `PlayerViewModel`, which owns `AudioPlayer` and `PlaybackQueue`.

## Components

### 1. PlayerViewModel Enhancement

- Add `playTrack(_ track: Track, queue: [Track], startingAt: Int)` — builds queue from track file paths, loads file, populates metadata (title, artist, album, artwork) from the Track model.
- Add `currentTrack: Track?` property so views can react to what's playing.
- Store `[Track]` reference alongside `PlaybackQueue` so `next()`/`previous()` can update metadata from the corresponding Track model.
- Update `next()` and `previous()` to populate metadata from the stored Track array.

### 2. SongsListView — Double-click to Play

- Add double-click gesture to table rows.
- On double-click: call `playerViewModel.playTrack(track, queue: allTracks, startingAt: index)`.
- Queue contains the full songs list so next/previous works.

### 3. AlbumGridView → AlbumDetailView Navigation

- Wrap album cards in `NavigationLink` passing the `Album` model.
- Requires adding `NavigationStack` to the browse content area.

### 4. AlbumDetailView — Real Data + Playback

- Rewrite to accept `Album` object instead of strings.
- Display `album.tracks` sorted by `discNumber`, then `trackNumber`.
- Play button: `playerViewModel.playTrack(firstTrack, queue: sortedTracks, startingAt: 0)`.
- Shuffle button: same but with shuffled array.
- Each track row is double-clickable to play from that point.

### 5. ArtistListView → ArtistDetailView Navigation

- Wrap artist rows in `NavigationLink` passing the `Artist` model.

### 6. ArtistDetailView — Real Data

- Rewrite to accept `Artist` object.
- Display `artist.albums` with artwork, year, and track count.
- Each album card navigates to `AlbumDetailView`.

### 7. ListenNowView — Click Handlers

- Recently added tracks: click to play (single track + context queue).
- Album cards: click to navigate to `AlbumDetailView`.

### 8. QueuePanel — Real Data

- Replace hardcoded tracks with `playerViewModel` queue data.
- Display current track, upcoming tracks, and history.
- Clear button calls `playerViewModel` queue clear.

### 9. NowPlayingBar Queue Toggle

- Wire queue button to toggle `QueuePanel` as a popover or trailing panel.
- Add `showQueue: Bool` state to manage visibility.

## Navigation Model

```
ContentView (NavigationSplitView)
├── SidebarView (selection)
├── ContentArea
│   ├── ListenNowView
│   │   ├── → AlbumDetailView (via NavigationLink)
│   │   └── track click → play
│   ├── Browse
│   │   ├── AlbumGridView → AlbumDetailView (via NavigationLink)
│   │   ├── ArtistListView → ArtistDetailView (via NavigationLink)
│   │   │   └── → AlbumDetailView (via NavigationLink)
│   │   └── SongsListView (double-click → play)
│   ├── PlaylistsView (v0.2)
│   └── AIChatView (v0.2)
└── NowPlayingBar
    └── Queue button → QueuePanel (popover)
```

## What's NOT in v0.1

- Playlist management (detail view, add-to-playlist, editing)
- AI chat action handlers (play playlist, apply tags)
- Drag-and-drop file import
- Context menus (right-click on tracks)
- NowPlayingExpandedView
- Shuffle/repeat toggle in NowPlayingExpandedView
- Settings wiring (crossfade, AI model download)
- Search functionality
