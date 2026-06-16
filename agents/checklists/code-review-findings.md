# Code Review Findings — Tracking Checklist

Whole-codebase review (app + `LinnetLibrary`, `LinnetAudio`, `LinnetAI`). Items are grouped by severity. Critical items were verified against source; some High/Medium are confidence-based and noted as such.

## 🔴 Critical

- [x] **Playlist removal crashes on empty set / unparameterized SQL** — `Packages/LinnetLibrary/Sources/LinnetLibrary/Database/Repositories/PlaylistRepository.swift:171`. `trackIds` string-interpolated into `IN (…)`; empty set → `IN ()` → SQLite syntax error → crash. Replace with `PlaylistEntryRecord.filter(Column("playlistId") == playlistId && trackIds.contains(Column("trackId"))).deleteAll(db)`.
- [x] **Data race on `suppressFinishCallback`** — `Packages/LinnetAudio/Sources/LinnetAudio/AudioPlayer.swift:72-77,103-161`. Plain `Bool` written on caller thread, read on the AVFoundation I/O thread; race with `seek()` can advance the queue a track early. Flag is also cleared immediately after `engine.stop()` while latent callbacks still fire. Use a generation/UUID counter (discard stale callbacks) or lock-protect.
- [x] **Gapless track-finish callback dropped after node swap** — `Packages/LinnetAudio/Sources/LinnetAudio/GaplessScheduler.swift:45`, `AudioPlayer.swift:120`. `scheduleNext` uses the no-completion-handler overload; after a crossfade swap the track's end never fires `onTrackFinished` → queue stalls. Route a completion callback through `scheduleNext`.
- [x] **`seek()` to end-of-file freezes playback** — `Packages/LinnetAudio/Sources/LinnetAudio/AudioPlayer.swift:167`. `guard remainingFrames > 0 else { return }` returns silently without `onTrackFinished`; progress bar freezes, queue stuck. Call `onTrackFinished?()`.
- [x] **`PlaybackQueue.jumpTo` allows negative index** — `Packages/LinnetAudio/Sources/LinnetAudio/PlaybackQueue.swift:90`. `guard index < tracks.count` passes for `-1` → `currentIndex = -1` → crash. Add `index >= 0 &&`.
- [x] **Actor reentrancy double-loads the model** — `Packages/LinnetAI/Sources/LinnetAI/AIService.swift:36-53`. Concurrent `ensureModelLoaded` callers pass the `contains` check across the `await loadLLM()` suspension → container loaded twice. Insert sentinel into `loadedModels` before the first `await`, roll back on failure.

## 🟠 High

### Audio
- [x] **EQ never bypasses when disabled** — `Packages/LinnetAudio/Sources/LinnetAudio/Equalizer.swift:159`. `eqBand.bypass = false` unconditional; disabled EQ still runs every IIR filter. Set `bypass = !enabled`.
- [x] **Crossfade timer self-deadlock** — `Packages/LinnetAudio/Sources/LinnetAudio/CrossfadeManager.swift:56`. `cancelFade()` holds `lock` while calling `timer.cancel()`, which waits for the running handler that also wants `lock`. Snapshot timer under lock, unlock, then cancel.
- [x] **Remote command handlers leak** — `Packages/LinnetAudio/Sources/LinnetAudio/NowPlayingManager.swift:37`. `addTarget` tokens discarded; re-invocation stacks duplicate handlers. Store tokens and `removeTarget` before re-registering.
- [x] **Loudness analysis hardcodes 44100** — `Packages/LinnetAudio/Sources/LinnetAudio/LoudnessAnalyzer.swift:33`. 30 s cap assumes 44.1 kHz; analyzes less at 48/96 kHz. Use `format.sampleRate * 30`.

### Library
- [x] **`DatabaseObserver` extra `Task { @MainActor }` hop** — `Packages/LinnetLibrary/Sources/LinnetLibrary/Database/DatabaseObserver.swift:18`. `.immediate` + unstructured Task can deliver snapshots out of order. Prefer `.async(onQueue: .main)` / mainActor scheduling.
- [ ] **N+1 duplicate check in import loop** — `Packages/LinnetLibrary/Sources/LinnetLibrary/LibraryManager.swift:62`. `SELECT COUNT(*)` per track per chunk, can't see same-transaction inserts. Use an in-memory set or unique index.
- [x] **Raw-`String` `ORDER BY` column (injection surface)** — `TrackRepository.swift:80`, `AlbumRepository.swift:68`, `ArtistRepository.swift:59`. Use the existing typed sort enums; drop the String overload.
- [x] **Errors swallowed (ArtworkService)** — `ArtworkService.swift:60,102` returned `true` after a `try?` upsert; now logs and returns `false` on failure. _Still open: `DatabaseLocation.swift:16` `try?` on dir creation — deferred (making `url` throwing touches many call sites)._
- [ ] **FTS5 full-text search is broken** — `searchAllInfo` in `TrackRepository.swift` issues `... LEFT JOIN trackFts ... WHERE trackFts MATCH ?`, which SQLite rejects: "unable to use function MATCH in the requested context" (caught by the pre-existing failing `FTS5 search by title` test). Restructure as a subquery: `track.id IN (SELECT rowid FROM trackFts WHERE trackFts MATCH ?)`. _(Found while fixing the library package — full-text search currently returns nothing / errors.)_

### AI
- [x] **Path traversal from LLM / library data** — `Packages/LinnetAI/Sources/LinnetAI/SmartFolderOrganizer.swift:53,80`. Track titles flow unsanitized into prompts; LLM-returned `folderName` passed to `FileManager.moveItem` with no containment check. Validate `destURL.standardized` is under `baseDirectory`; strip newlines/separators from titles.
- [x] **Batch ops swallow errors & ignore cancellation** — `EmbeddingGenerator.swift:29,36`, `AutoTagger.swift:43,50`. Bare `continue` on failures (incomplete looks complete); no `Task.isCancelled` check. Surface failures; check cancellation per iteration.

### UI
- [x] **Unstructured load tasks race** — `Linnet/ViewModels/PlayerViewModel.swift:292`. `loadAndPlay` spawns uncancelled `Task`; rapid switches finish out of order. Store/cancel a `loadTask`; also stop the time-update timer before reload (`:369`).
- [x] **Shared `nonisolated(unsafe)` globals** — `Linnet/Views/ArtistDetailView.swift:7-9`. Click-time + two data/artwork caches are file-level globals shared across all instances → cross-album mis-fired double-clicks, cross-artist cache bleed. Move to per-view `@State`.

## 🟡 Medium

- [x] **`DetailPage.swift` is dead code** (zero references) and still carries the old `@AppStorage("showQueueSidePane")` toggle removed elsewhere. Delete `Linnet/Views/Components/DetailPage.swift`.
- [ ] **Stale cache on metadata edits** — caching keyed on `onChange(of: tracks.count)` (`AlbumDetailView.swift:191`, `SongsGroupingView.swift:121`) misses title/like/artwork edits. Key on the observer value.
- [ ] **Dead UI** — shuffle/repeat buttons are empty closures (`NowPlayingExpandedView.swift:57,82`); model download progress stuck at 0% (`ModelManager.swift:114`).
- [ ] **`engine.start()` failure swallowed** — `AudioPlayer.swift:126` `try?`; no `AVAudioEngineConfigurationChange` handling → no recovery after device/route changes.
- [ ] **`artwork` table has no FK/cleanup** — `DatabaseManager.swift:87` → orphan rows accumulate on album/artist delete.
- [ ] **`copyDatabase` copies WAL/SHM with pool open** — `DatabaseLocation.swift:75` → possible corruption. Use GRDB `backup(to:)`.
- [x] **`deleteByFolder` LIKE prefix unescaped** — `TrackRepository.swift:383`; `%`/`_` in paths act as wildcards. Escape + `ESCAPE`.
- [ ] **Grouping queries load whole track table into memory** — `TrackRepository.swift:223-315`. Push `GROUP BY` to SQL or stream with a cursor.
- [ ] **`PlaylistsView.swift:78`** force-unwraps `playlist.id!`. Use optional mapping.
- [ ] **`removeFromQueue` offset arithmetic fragile** — `PlayerViewModel.swift:246`; `currentIndex` may shift mid-loop on multi-select removal. *(Confidence-dependent — verify against `PlaybackQueue.remove`.)*

---

## Progress — session 1

**Done (18 items): all 6 Critical + 8 High + 4 Medium.** Verified by building each package (`swift build` + `swift test`) and a full `xcodebuild` of the app (BUILD SUCCEEDED).
- Audio: generation-counter replaces racy `suppressFinishCallback` (fixes seek/load race + seek-to-end freeze), gapless completion wired, `jumpTo` guard (+3 regression tests), EQ bypass, crossfade deadlock, remote-command leak, loudness sample-rate.
- Library: parameterized playlist delete, `.mainActor` observer scheduling, quoted `ORDER BY`, ArtworkService error handling, escaped `deleteByFolder`.
- AI: coalesced model load (reentrancy), path-traversal sanitization + containment, batch error/cancellation callbacks.
- UI: cancellable `loadAndPlay`, per-card click state, deleted dead `DetailPage.swift` (regenerated Xcode project).

**Remaining (10 items):** the larger/riskier refactors — N+1 import, FTS5 search fix (newly found), artwork FK cleanup, `copyDatabase` via GRDB backup, grouping-query memory, `DatabaseLocation.url` throwing, engine-start/route-change recovery, stale-cache-on-edit, dead shuffle/repeat + download progress, `PlaylistsView` force-unwrap, `removeFromQueue` arithmetic. Each is self-contained and can be its own focused change.

_Generated from a parallel multi-agent code review. Critical items verified against source; confidence-dependent items flagged inline._
