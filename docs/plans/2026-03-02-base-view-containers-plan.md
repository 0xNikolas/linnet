# Base View Containers Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create `ListPage` and `DetailPage` container views that provide consistent toolbar items across all views, then refactor existing views to use them.

**Architecture:** Two generic container views — `ListPage<S, Content>` wraps list views with searchable/sort/toolbar, `DetailPage<Content>` wraps detail views with ScrollView/toolbar. Queue panel uses HStack sibling approach in ContentView. AudioPlayer gets suppressFinishCallback to prevent queue cascade on seek.

**Tech Stack:** SwiftUI, GRDB, macOS 15+

---

### Task 1: Apply stashed AudioPlayer and PlayerViewModel fixes

These fixes from the stash prevent a critical bug where seeking causes all queued tracks to disappear.

**Files:**
- Modify: `Packages/LinnetAudio/Sources/LinnetAudio/AudioPlayer.swift`
- Modify: `Packages/LinnetAudio/Sources/LinnetAudio/PlaybackQueue.swift`
- Modify: `Linnet/ViewModels/PlayerViewModel.swift`

**Step 1: Apply the stash**

```bash
git stash pop
```

This applies all stashed changes. We'll keep the AudioPlayer/PlaybackQueue/PlayerViewModel fixes and revert the ContentView/QueuePanel/NowPlayingBar/etc changes that we're redesigning.

**Step 2: Revert UI files to committed state, keep only audio/viewmodel fixes**

```bash
git checkout HEAD -- Linnet/ContentView.swift Linnet/Views/QueuePanel.swift Linnet/Views/NowPlayingBar.swift Linnet/Views/ArtistDetailView.swift Linnet/Views/AlbumDetailView.swift Linnet/Views/AlbumGridView.swift Linnet/Views/ArtistListView.swift
```

**Step 3: Build and verify**

Run: `xcodebuild -scheme Linnet -configuration Debug build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add Packages/LinnetAudio/Sources/LinnetAudio/AudioPlayer.swift Packages/LinnetAudio/Sources/LinnetAudio/PlaybackQueue.swift Linnet/ViewModels/PlayerViewModel.swift
git commit -m "fix: prevent queue cascade on seek and support addNext/addLater for arrays"
```

---

### Task 2: Create DetailPage container

**Files:**
- Create: `Linnet/Views/Components/DetailPage.swift`

**Step 1: Create the DetailPage container**

Create `Linnet/Views/Components/DetailPage.swift`:

```swift
import SwiftUI

struct DetailPage<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @AppStorage("showQueueSidePane") private var showQueueSidePane = false

    var body: some View {
        ScrollView {
            content()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showQueueSidePane.toggle()
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
            }
        }
    }
}
```

**Step 2: Build and verify**

Run: `xcodebuild -scheme Linnet -configuration Debug build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add Linnet/Views/Components/DetailPage.swift
git commit -m "feat: add DetailPage container with queue toggle toolbar"
```

---

### Task 3: Create ListPage container

**Files:**
- Create: `Linnet/Views/Components/ListPage.swift`

**Step 1: Create the ListPage container**

Create `Linnet/Views/Components/ListPage.swift`:

```swift
import SwiftUI
import LinnetLibrary

struct ListPage<S: SortOptionProtocol, Content: View>: View {
    let searchPrompt: String
    @Binding var sortOption: S
    @Binding var sortDirection: SortDirection
    var extraMenuBuilder: ((NSMenu, SortFilterMenuButton<S>.Coordinator) -> Void)?
    @ViewBuilder var content: (_ searchText: String) -> Content

    @AppStorage("showQueueSidePane") private var showQueueSidePane = false
    @State private var searchText = ""
    @State private var isSearchPresented = false

    var body: some View {
        content(searchText)
            .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: searchPrompt)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    if let extraMenuBuilder {
                        SortFilterMenuButton(
                            sortOption: $sortOption,
                            sortDirection: $sortDirection,
                            extraMenuBuilder: extraMenuBuilder
                        )
                    } else {
                        SortFilterMenuButton(
                            sortOption: $sortOption,
                            sortDirection: $sortDirection
                        )
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showQueueSidePane.toggle()
                    } label: {
                        Image(systemName: "sidebar.trailing")
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
                isSearchPresented = true
            }
    }
}
```

**Step 2: Build and verify**

Run: `xcodebuild -scheme Linnet -configuration Debug build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add Linnet/Views/Components/ListPage.swift
git commit -m "feat: add ListPage container with search, sort/filter, and queue toggle"
```

---

### Task 4: Refactor ArtistDetailView to use DetailPage

**Files:**
- Modify: `Linnet/Views/ArtistDetailView.swift`

**Step 1: Wrap body content in DetailPage**

Replace the `ScrollViewReader { proxy in ScrollView { ... } ... }` structure with `DetailPage`. The ScrollViewReader stays inside DetailPage's content closure since it wraps the scroll content.

The current body structure is:
```swift
var body: some View {
    ScrollViewReader { proxy in
    ScrollView {
        VStack(alignment: .leading, spacing: 20) { ... }
        .animation(...)
    }
    .task { ... }
    .onChange(...)
    .onReceive(...)
    } // ScrollViewReader
}
```

Change to:
```swift
var body: some View {
    DetailPage {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 20) { ... }
                .animation(...)
                .onReceive(NotificationCenter.default.publisher(for: .highlightTrackInDetail)) { notification in
                    guard let trackID = notification.userInfo?["trackID"] as? Int64 else { return }
                    guard allTracks.contains(where: { $0.id == trackID }) else { return }
                    selectedTrackID = trackID
                    selectedAlbumID = nil
                    withAnimation {
                        proxy.scrollTo(trackID, anchor: .center)
                    }
                }
        }
    }
    .task { ... }
    .onChange(...)
}
```

Key changes:
1. Remove the outer `ScrollView` — `DetailPage` provides it
2. Move `ScrollViewReader` inside the `DetailPage` content closure
3. Keep `.task`, `.onChange` modifiers on the outer `DetailPage` (they don't need to be inside `ScrollView`)
4. The `.onReceive(.highlightTrackInDetail)` stays inside `ScrollViewReader` since it uses `proxy`

Also remove the `navigationPath` parameter if it exists (use `@Environment(\.navigationPath)` instead, which is already set up in the current committed code).

**Step 2: Build and verify**

Run: `xcodebuild -scheme Linnet -configuration Debug build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add Linnet/Views/ArtistDetailView.swift
git commit -m "refactor: wrap ArtistDetailView in DetailPage container"
```

---

### Task 5: Refactor AlbumDetailView to use DetailPage

**Files:**
- Modify: `Linnet/Views/AlbumDetailView.swift`

**Step 1: Wrap body content in DetailPage**

AlbumDetailView currently uses `VStack` (not `ScrollView`) because it has a fixed header + scrolling `List` for tracks. Since `DetailPage` wraps content in `ScrollView`, and the track list inside is already a `List` (which has its own scroll), we need to be careful.

For AlbumDetailView, the `DetailPage`'s `ScrollView` would conflict with the inner `List`'s scrolling. Instead, use `DetailPage` but override to NOT use ScrollView. Better approach: make `DetailPage` accept a `usesScrollView` parameter, or just add the toolbar directly.

**Revised approach:** Since AlbumDetailView's layout (fixed header + List) doesn't fit inside a ScrollView, just add the toolbar modifier directly:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 0) {
        // ... existing header and track list ...
    }
    .toolbar {
        ToolbarItem(placement: .primaryAction) {
            Button {
                AppStorage("showQueueSidePane").wrappedValue.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
        }
    }
    // ... existing .task, .onChange, .sheet modifiers ...
}
```

Wait — we can't use `AppStorage` like that inline. Better: add an `@AppStorage` property and a `.toolbar` modifier.

Add to AlbumDetailView:
```swift
@AppStorage("showQueueSidePane") private var showQueueSidePane = false
```

Then after the `.sheet(isPresented: $showEditSheet)` modifier, add:
```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button { showQueueSidePane.toggle() } label: {
            Image(systemName: "sidebar.trailing")
        }
    }
}
```

**Step 2: Build and verify**

Run: `xcodebuild -scheme Linnet -configuration Debug build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add Linnet/Views/AlbumDetailView.swift
git commit -m "refactor: add queue toggle toolbar to AlbumDetailView"
```

---

### Task 6: Refactor PlaylistDetailView to use DetailPage

**Files:**
- Modify: `Linnet/Views/PlaylistDetailView.swift`

**Step 1: Add queue toggle toolbar**

Same as AlbumDetailView — PlaylistDetailView uses `VStack` with header + `Table`, so ScrollView wrapper doesn't fit. Add toolbar directly.

Add property:
```swift
@AppStorage("showQueueSidePane") private var showQueueSidePane = false
```

Add toolbar modifier after `.onChange(of: tracks.count)`:
```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button { showQueueSidePane.toggle() } label: {
            Image(systemName: "sidebar.trailing")
        }
    }
}
```

**Step 2: Build and verify**

Run: `xcodebuild -scheme Linnet -configuration Debug build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add Linnet/Views/PlaylistDetailView.swift
git commit -m "refactor: add queue toggle toolbar to PlaylistDetailView"
```

---

### Task 7: Refactor ArtistListView to use ListPage

**Files:**
- Modify: `Linnet/Views/ArtistListView.swift`

**Step 1: Wrap in ListPage, remove duplicated searchable/toolbar/focusSearch**

Current body:
```swift
var body: some View {
    List(selection: $selectedArtistID) { ... }
    .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search artists...")
    .toolbar {
        ToolbarItem(placement: .automatic) {
            SortFilterMenuButton(sortOption: $sortOption, sortDirection: $sortDirection)
        }
    }
    .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
        isSearchPresented = true
    }
    .task { ... }
    .onChange(of: ...) { ... }
}
```

Change to:
```swift
var body: some View {
    ListPage(
        searchPrompt: "Search artists...",
        sortOption: $sortOption,
        sortDirection: $sortDirection
    ) { searchText in
        List(selection: $selectedArtistID) { ... }
        .contextMenu(forSelectionType: Int64.self, menu: { _ in }, primaryAction: { identifiers in
            guard let id = identifiers.first,
                  let artist = artists.first(where: { $0.id == id }) else { return }
            let artistRecord = ArtistRecord(id: artist.id, name: artist.name)
            navigationPath.wrappedValue.append(artistRecord)
        })
        .task { ... }
        .onChange(of: artists) { ... }
        .onChange(of: searchText) { _, _ in reobserve() }
        .onChange(of: sortOption) { _, _ in reobserve() }
        .onChange(of: sortDirection) { _, _ in reobserve() }
    }
}
```

Remove the `@State private var searchText` and `@State private var isSearchPresented` properties — ListPage owns them now.

The `searchText` parameter from the `ListPage` closure replaces `self.searchText`. Update `makeObservation()` and `reobserve()` to accept `searchText` as a parameter or store it in a local state that's updated from the closure.

**Important:** The `searchText` from the ListPage closure is a `String` value, not a binding. The view needs to observe changes. Best approach: keep a local `@State private var searchText = ""` that's synchronized via `.onChange`:

Actually, simpler: just keep `searchText` as a `@State` on ArtistListView. ListPage passes it, and we use `.onChange(of:)` on the outer wrapper:

```swift
var body: some View {
    ListPage(
        searchPrompt: "Search artists...",
        sortOption: $sortOption,
        sortDirection: $sortDirection
    ) { searchText in
        artistList
            .onChange(of: searchText) { _, newValue in
                self.searchText = newValue
                reobserve()
            }
    }
}
```

Wait — `searchText` from the closure is a snapshot, not reactive. We need to think about this differently.

**Revised approach for searchText flow:**

Option: Give `ListPage` a `@Binding var searchText` instead of owning it. This way the parent controls the state:

Change ListPage to accept a binding:
```swift
struct ListPage<S: SortOptionProtocol, Content: View>: View {
    let searchPrompt: String
    @Binding var sortOption: S
    @Binding var sortDirection: SortDirection
    @Binding var searchText: String
    var extraMenuBuilder: ((NSMenu, SortFilterMenuButton<S>.Coordinator) -> Void)?
    @ViewBuilder var content: () -> Content
    ...
}
```

This is actually simpler — each list view keeps its `@State searchText` and passes a binding. The content closure doesn't need a parameter. Update ListPage (Task 3) accordingly.

**Revised ListPage (update Task 3's code):**

```swift
struct ListPage<S: SortOptionProtocol, Content: View>: View {
    let searchPrompt: String
    @Binding var sortOption: S
    @Binding var sortDirection: SortDirection
    @Binding var searchText: String
    var extraMenuBuilder: ((NSMenu, SortFilterMenuButton<S>.Coordinator) -> Void)?
    @ViewBuilder var content: () -> Content

    @AppStorage("showQueueSidePane") private var showQueueSidePane = false
    @State private var isSearchPresented = false

    var body: some View {
        content()
            .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: searchPrompt)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    if let extraMenuBuilder {
                        SortFilterMenuButton(
                            sortOption: $sortOption,
                            sortDirection: $sortDirection,
                            extraMenuBuilder: extraMenuBuilder
                        )
                    } else {
                        SortFilterMenuButton(
                            sortOption: $sortOption,
                            sortDirection: $sortDirection
                        )
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showQueueSidePane.toggle()
                    } label: {
                        Image(systemName: "sidebar.trailing")
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
                isSearchPresented = true
            }
    }
}
```

Then ArtistListView becomes:
```swift
var body: some View {
    ListPage(
        searchPrompt: "Search artists...",
        sortOption: $sortOption,
        sortDirection: $sortDirection,
        searchText: $searchText
    ) {
        List(selection: $selectedArtistID) { ... }
        .contextMenu(...)
    }
    .task { ... }
    .onChange(of: artists) { ... }
    .onChange(of: searchText) { _, _ in reobserve() }
    .onChange(of: sortOption) { _, _ in reobserve() }
    .onChange(of: sortDirection) { _, _ in reobserve() }
}
```

Remove `.searchable`, `.toolbar`, `.onReceive(.focusSearch)` from ArtistListView — ListPage provides them.
Keep `@State private var searchText = ""` — it's still owned here, just bound to ListPage.
Remove `@State private var isSearchPresented` — ListPage owns that.

**Step 2: Build and verify**

Run: `xcodebuild -scheme Linnet -configuration Debug build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add Linnet/Views/ArtistListView.swift Linnet/Views/Components/ListPage.swift
git commit -m "refactor: wrap ArtistListView in ListPage container"
```

---

### Task 8: Refactor AlbumGridView to use ListPage

**Files:**
- Modify: `Linnet/Views/AlbumGridView.swift`

**Step 1: Wrap in ListPage**

Remove `.searchable`, `.toolbar`, `.onReceive(.focusSearch)` from AlbumGridView.
Remove `@State private var isSearchPresented`.
Keep `@State private var searchText`.
Wrap body in `ListPage`:

```swift
var body: some View {
    ListPage(
        searchPrompt: "Search albums...",
        sortOption: $sortOption,
        sortDirection: $sortDirection,
        searchText: $searchText
    ) {
        ScrollView {
            if albums.isEmpty {
                // ... existing empty state ...
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    // ... existing grid ...
                }
                .padding(20)
                .animation(.default, value: albums.count)
            }
        }
    }
    .task { ... }
    .onChange(of: albums) { ... }
    .onChange(of: searchText) { _, _ in reobserve() }
    .onChange(of: sortOption) { _, _ in reobserve() }
    .onChange(of: sortDirection) { _, _ in reobserve() }
}
```

**Step 2: Build and verify**

Run: `xcodebuild -scheme Linnet -configuration Debug build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add Linnet/Views/AlbumGridView.swift
git commit -m "refactor: wrap AlbumGridView in ListPage container"
```

---

### Task 9: Refactor SongsGroupingView to use ListPage

**Files:**
- Modify: `Linnet/Views/SongsGroupingView.swift`

**Step 1: Wrap in ListPage with extraMenuBuilder**

SongsGroupingView has a custom extra menu for grouping. Pass it via `extraMenuBuilder`.

Remove `.searchable`, `.toolbar`, `.onReceive(.focusSearch)`.
Remove `@State private var isSearchPresented`.
Keep `@State private var searchText`.

```swift
var body: some View {
    ListPage(
        searchPrompt: "Search songs...",
        sortOption: $sortOption,
        sortDirection: $sortDirection,
        searchText: $searchText,
        extraMenuBuilder: { menu, coordinator in
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Group By", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for option in SongsGrouping.allCases {
                let item = NSMenuItem(
                    title: option.rawValue,
                    action: #selector(type(of: coordinator).selectExtra(_:)),
                    keyEquivalent: ""
                )
                item.target = coordinator
                item.state = grouping == option ? .on : .off
                item.representedObject = { [self] in
                    grouping = option
                } as () -> Void
                menu.addItem(item)
            }
        }
    ) {
        SongsListView(
            tracks: tracks,
            sections: grouping == .allSongs ? [] : sections,
            highlightedTrackID: $highlightedTrackID
        )
    }
    .task { ... }
    .onChange(of: tracks.count) { ... }
    .onChange(of: grouping) { _, _ in reobserve() }
    .onChange(of: sortOption) { _, _ in reobserve() }
    .onChange(of: sortDirection) { _, _ in reobserve() }
    .onChange(of: searchText) { _, _ in reobserve() }
}
```

**Step 2: Build and verify**

Run: `xcodebuild -scheme Linnet -configuration Debug build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add Linnet/Views/SongsGroupingView.swift
git commit -m "refactor: wrap SongsGroupingView in ListPage container"
```

---

### Task 10: Refactor PlaylistsView to use ListPage

**Files:**
- Modify: `Linnet/Views/PlaylistsView.swift`

**Step 1: Wrap in ListPage**

PlaylistsView has a custom header with title + "New Playlist" button. The SortFilterMenuButton is currently in that custom header, not in `.toolbar`. Move it to ListPage's toolbar. Keep the "New Playlist" button in the header.

Remove `.searchable`, `.onReceive(.focusSearch)`.
Remove `@State private var isSearchPresented`.
Keep `@State private var searchText`.
Remove the `SortFilterMenuButton` from the custom header HStack.

```swift
var body: some View {
    ListPage(
        searchPrompt: "Search playlists...",
        sortOption: $sortOption,
        sortDirection: $sortDirection,
        searchText: $searchText
    ) {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Playlists")
                    .font(.largeTitle.bold())
                Spacer()
                Button(action: createPlaylist) {
                    Label("New Playlist", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(20)

            if playlists.isEmpty {
                // ... existing empty state ...
            } else {
                List(playlists, id: \.id, selection: $selectedPlaylistID) { ... }
                .contextMenu(...)
            }
        }
    }
    .task { ... }
    .onChange(of: playlists.count) { ... }
    .onChange(of: searchText) { _, _ in reobserve() }
    .onChange(of: sortOption) { _, _ in reobserve() }
    .onChange(of: sortDirection) { _, _ in reobserve() }
}
```

**Step 2: Build and verify**

Run: `xcodebuild -scheme Linnet -configuration Debug build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add Linnet/Views/PlaylistsView.swift
git commit -m "refactor: wrap PlaylistsView in ListPage container"
```

---

### Task 11: Refactor LikedSongsView to use ListPage

**Files:**
- Modify: `Linnet/Views/LikedSongsView.swift`

**Step 1: Wrap in ListPage**

LikedSongsView doesn't have search currently. Add it via ListPage. It does have `.toolbar` with SortFilterMenuButton — remove that.

Add `@State private var searchText = ""` (it doesn't currently have one).
Remove `@State private var isSearchPresented` (if present).
Remove `.toolbar { ... }`.

```swift
var body: some View {
    ListPage(
        searchPrompt: "Search liked songs...",
        sortOption: $sortOption,
        sortDirection: $sortDirection,
        searchText: $searchText
    ) {
        SongsListView(tracks: observer?.value ?? [], highlightedTrackID: $highlightedTrackID)
            .navigationTitle("Liked Songs")
    }
    .task { ... }
    .onChange(of: observer?.value) { ... }
    .onChange(of: sortOption) { _, _ in reobserve() }
    .onChange(of: sortDirection) { _, _ in reobserve() }
}
```

Note: LikedSongsView doesn't currently filter by search. For now, leave searchText unused (ListPage shows the search UI, but LikedSongsView doesn't filter by it). Adding search filtering can be a follow-up.

**Step 2: Build and verify**

Run: `xcodebuild -scheme Linnet -configuration Debug build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add Linnet/Views/LikedSongsView.swift
git commit -m "refactor: wrap LikedSongsView in ListPage container"
```

---

### Task 12: Update ContentView — remove toolbar, keep HStack for queue panel

**Files:**
- Modify: `Linnet/ContentView.swift`

**Step 1: Remove the queue toggle from ContentView's toolbar and the toggleQueueSidePane notification handler**

The queue toggle is now provided by each individual view via ListPage/DetailPage. Remove:
1. The `.onReceive(NotificationCenter.default.publisher(for: .toggleQueueSidePane))` handler
2. Any toolbar items on ContentView that duplicate what the containers provide

The HStack approach for the queue panel is already in the committed code and works. No changes needed there.

Actually — check if the committed code already has the toolbar button. If it does, remove it since ListPage/DetailPage now provide it.

Looking at the committed ContentView: it does NOT have a toolbar button for queue toggle. It uses the HStack approach with `if showQueueSidePane { Divider(); QueuePanel(...) }`. This is correct — keep it.

The only change: remove the `.onReceive(.toggleQueueSidePane)` handler since it's unused now (the toggle is handled by each view's toolbar button via `@AppStorage`).

```swift
// Remove this block:
.onReceive(NotificationCenter.default.publisher(for: .toggleQueueSidePane)) { _ in
    showQueueSidePane.toggle()
}
```

**Step 2: Build and verify**

Run: `xcodebuild -scheme Linnet -configuration Debug build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Launch and test**

```bash
pkill -x Linnet 2>/dev/null; sleep 0.5
open /Users/nicu/Library/Developer/Xcode/DerivedData/Linnet-gmptllbhryqszjfmdqhbfausrdtn/Build/Products/Debug/Linnet.app
```

Verify:
- Queue toggle button (sidebar.trailing icon) appears in toolbar on ALL views: Artists list, Albums grid, Songs list, Liked Songs, Playlists
- Queue toggle button appears when navigating INTO detail views: Artist detail, Album detail, Playlist detail
- Sort/filter button appears on all list views
- Search works on all list views
- Queue side panel opens/closes correctly from any view

**Step 4: Commit**

```bash
git add Linnet/ContentView.swift
git commit -m "refactor: remove toggleQueueSidePane notification handler from ContentView"
```
