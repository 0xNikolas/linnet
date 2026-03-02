# Base View Containers Design

## Goal

Create two generic container views (`ListPage` and `DetailPage`) that provide consistent toolbar items (queue toggle, sort/filter) across all views. Refactor existing views to use them. Fix the queue side panel and AudioPlayer callback cascade.

## Architecture

Two container views solve two problems: toolbar items disappear when pushing detail views (SwiftUI replaces toolbar on navigation push), and shared patterns are duplicated across 8+ views.

`ListPage<S: SortOptionProtocol, Content: View>` wraps list views with searchable, sort/filter menu, queue toggle toolbar, and focus-search handling. Passes `searchText` to content via closure parameter.

`DetailPage<Content: View>` wraps detail views with ScrollView and queue toggle toolbar. Content is a free-form `@ViewBuilder` closure.

## Components

### DetailPage

```swift
struct DetailPage<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @AppStorage("showQueueSidePane") private var showQueueSidePane = false

    var body: some View {
        ScrollView {
            content()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showQueueSidePane.toggle() } label: {
                    Image(systemName: "sidebar.trailing")
                }
            }
        }
    }
}
```

### ListPage

```swift
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
                    SortFilterMenuButton(sortOption: $sortOption, sortDirection: $sortDirection, extraMenuBuilder: extraMenuBuilder)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showQueueSidePane.toggle() } label: {
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

### ContentView queue panel

HStack sibling approach inside the detail area:

```swift
} detail: {
    HStack(spacing: 0) {
        NavigationStack(path: $navigationPath) {
            ContentArea(...)
                .navigationDestination(for: AlbumRecord.self) { ... }
                .navigationDestination(for: ArtistRecord.self) { ... }
                .navigationDestination(for: Int64.self) { ... }
            // No .toolbar here — base views handle it
        }
        if showQueueSidePane {
            Divider()
            QueuePanel(isShowing: $showQueueSidePane)
        }
    }
}
```

### AudioPlayer fix

Add `suppressFinishCallback` flag to AudioPlayer to prevent completion callbacks from firing during seek/load/stop, which cascades through the queue.

## Refactoring scope

| View | Container | What moves into container |
|------|-----------|--------------------------|
| ArtistListView | ListPage | searchable, sort toolbar, queue toggle, focusSearch |
| AlbumGridView | ListPage | searchable, sort toolbar, queue toggle, focusSearch |
| SongsGroupingView | ListPage | searchable, sort toolbar (+ grouping extra menu), queue toggle, focusSearch |
| PlaylistsView | ListPage | searchable, sort toolbar, queue toggle, focusSearch |
| LikedSongsView | ListPage | sort toolbar, queue toggle |
| ArtistDetailView | DetailPage | ScrollView wrapper, queue toggle toolbar |
| AlbumDetailView | DetailPage | queue toggle toolbar |
| PlaylistDetailView | DetailPage | queue toggle toolbar |

## New files

- `Linnet/Views/Components/ListPage.swift`
- `Linnet/Views/Components/DetailPage.swift`

## Files modified

- `Linnet/ContentView.swift` — remove toolbar modifier, keep HStack for queue panel
- `Linnet/Views/ArtistListView.swift` — wrap in ListPage
- `Linnet/Views/AlbumGridView.swift` — wrap in ListPage
- `Linnet/Views/SongsGroupingView.swift` — wrap in ListPage
- `Linnet/Views/PlaylistsView.swift` — wrap in ListPage
- `Linnet/Views/LikedSongsView.swift` — wrap in ListPage
- `Linnet/Views/ArtistDetailView.swift` — wrap in DetailPage
- `Linnet/Views/AlbumDetailView.swift` — wrap in DetailPage
- `Linnet/Views/PlaylistDetailView.swift` — wrap in DetailPage
- `Linnet/Views/QueuePanel.swift` — restore custom header (removed during failed inspector attempt)
- `Packages/LinnetAudio/Sources/LinnetAudio/AudioPlayer.swift` — add suppressFinishCallback
