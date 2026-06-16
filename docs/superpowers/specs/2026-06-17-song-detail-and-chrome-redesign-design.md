# Song-detail & chrome redesign

Date: 2026-06-17

Apply Apple Music-inspired design to the song-listing detail views, tidy the
sidebar, and redesign playlist creation. Reference: Apple Music playlist detail
and "New Playlist" modal.

## 1. Sidebar chrome

- Rename `SidebarItem.listenNow`: label `"Listen Now"` → `"Home"`, icon
  `play.circle` → `house`. Keep the internal case name `listenNow` to avoid
  breaking persisted selection/config (Codable encodes by case name).
- Remove the AI feature: drop `sidebarLabel(.ai)`, the `.ai` case, its
  `ContentArea` route, and `AIChatView`. The first sidebar section then contains
  only Home; remove its now-redundant "Home" section header.

## 2. Unified song-detail design (Album, Playlist, Artist detail)

Liked Songs and Songs are out of scope (Songs uses grouping; Liked stays a flat
searchable list).

- **Shared `TrackTable`** replaces the three current implementations
  (`SongsTableView`, `AlbumTrackListView`, `PlaylistDetailView.trackTable`).
  Columns: **Song** (album-art thumbnail + title) · **Artist** · **Album** ·
  **Time**. Preserves selection, now-playing indicator, context menu, and the
  existing optional metadata/audio columns where already present.
- **Per-row artwork thumbnails**: each row shows its track's album art (by
  `albumId`), loaded async and cached so the `Table` stays smooth. Fallback to a
  music-note glyph.
- **Shared `DetailHeader`**: large square artwork (left), title, subtitle,
  metadata line, **Play** (prominent/accent) + **Shuffle** (bordered).
- **Footer**: "N songs, M minutes" below the table.
- Apply header + table + footer consistently to Album / Playlist / Artist detail.

## 3. New Playlist modal (fully functional)

Centered card matching the reference: title "New Playlist", a square artwork well
with a red **+** (choose a custom cover), **Playlist Title** field, **Description
(Optional)** multiline field, Cancel / Create.

- **DB migration**: add `description` (text, nullable) to `playlist`; add
  `description` to `PlaylistRecord`.
- **Custom artwork**: store via the existing `artwork` table with
  `ownerType = "playlist"`, `ownerId = playlist.id`. Show the custom cover on the
  playlist detail header and the sidebar row; fall back to the existing
  auto-generated cover when none is set.
- Create still works with title only; description and cover are optional.

## Risks / notes

- Per-row async artwork in a SwiftUI `Table` must be cached to avoid jank; reuse
  the album-art fetch path already used by `AlbumGridItem`.
- The migration is additive (nullable column), so existing playlists are
  unaffected.
- Unifying three tables touches several files; verify Songs/Liked still render
  after the swap.
