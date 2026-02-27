import SwiftUI
import AppKit

// MARK: - Sort Option Protocol

protocol SortOptionProtocol: RawRepresentable<String>, CaseIterable, Identifiable, Hashable {
    var displayName: String { get }
    var sqlColumn: String { get }
}

extension SortOptionProtocol {
    var id: String { rawValue }
}

// MARK: - Sort Direction

enum SortDirection: String, CaseIterable {
    case ascending
    case descending

    var sql: String {
        switch self {
        case .ascending: "ASC"
        case .descending: "DESC"
        }
    }

    var label: String {
        switch self {
        case .ascending: "Ascending"
        case .descending: "Descending"
        }
    }

    var icon: String {
        switch self {
        case .ascending: "chevron.up"
        case .descending: "chevron.down"
        }
    }
}

// MARK: - Track Sort Options

enum TrackSortOption: String, SortOptionProtocol {
    case title, artist, album, dateAdded, duration

    var displayName: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .album: "Album"
        case .dateAdded: "Date Added"
        case .duration: "Duration"
        }
    }

    var sqlColumn: String {
        switch self {
        case .title: "track.title COLLATE NOCASE"
        case .artist: "COALESCE(artist.name, 'zzz') COLLATE NOCASE"
        case .album: "COALESCE(album.name, 'zzz') COLLATE NOCASE"
        case .dateAdded: "track.dateAdded"
        case .duration: "track.duration"
        }
    }
}

// MARK: - Artist Sort Options

enum ArtistSortOption: String, SortOptionProtocol {
    case name, albumCount

    var displayName: String {
        switch self {
        case .name: "Name"
        case .albumCount: "Album Count"
        }
    }

    var sqlColumn: String {
        switch self {
        case .name: "artist.name COLLATE NOCASE"
        case .albumCount: "albumCount"
        }
    }
}

// MARK: - Album Sort Options

enum AlbumSortOption: String, SortOptionProtocol {
    case name, artist, year

    var displayName: String {
        switch self {
        case .name: "Name"
        case .artist: "Artist"
        case .year: "Year"
        }
    }

    var sqlColumn: String {
        switch self {
        case .name: "album.name COLLATE NOCASE"
        case .artist: "COALESCE(album.artistName, 'zzz') COLLATE NOCASE"
        case .year: "COALESCE(album.year, 0)"
        }
    }
}

// MARK: - Playlist Sort Options

enum PlaylistSortOption: String, SortOptionProtocol {
    case name, dateCreated, songCount

    var displayName: String {
        switch self {
        case .name: "Name"
        case .dateCreated: "Date Created"
        case .songCount: "Song Count"
        }
    }

    var sqlColumn: String {
        switch self {
        case .name: "name COLLATE NOCASE"
        case .dateCreated: "createdAt"
        case .songCount: "songCount"
        }
    }
}

// MARK: - Sort Filter Menu Button (NSMenu-based, no toolbar pill)

struct SortFilterMenuButton<S: SortOptionProtocol>: NSViewRepresentable {
    @Binding var sortOption: S
    @Binding var sortDirection: SortDirection
    var extraMenuBuilder: ((NSMenu, Coordinator) -> Void)?

    init(
        sortOption: Binding<S>,
        sortDirection: Binding<SortDirection>
    ) {
        self._sortOption = sortOption
        self._sortDirection = sortDirection
        self.extraMenuBuilder = nil
    }

    init(
        sortOption: Binding<S>,
        sortDirection: Binding<SortDirection>,
        extraMenuBuilder: @escaping (NSMenu, Coordinator) -> Void
    ) {
        self._sortOption = sortOption
        self._sortDirection = sortDirection
        self.extraMenuBuilder = extraMenuBuilder
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "line.3.horizontal.decrease.circle", accessibilityDescription: "Sort & Filter")
        button.imagePosition = .imageOnly
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        button.contentTintColor = .secondaryLabelColor
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        button.toolTip = "Sort & Filter"
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject {
        var parent: SortFilterMenuButton<S>

        init(parent: SortFilterMenuButton<S>) {
            self.parent = parent
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()

            // Sort By header
            let header = NSMenuItem(title: "Sort By", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for option in S.allCases {
                let item = NSMenuItem(title: option.displayName, action: #selector(selectSortOption(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = option.rawValue
                item.state = parent.sortOption == option ? .on : .off
                menu.addItem(item)
            }

            menu.addItem(.separator())

            for direction in SortDirection.allCases {
                let item = NSMenuItem(title: direction.label, action: #selector(selectDirection(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = direction.rawValue
                item.state = parent.sortDirection == direction ? .on : .off
                menu.addItem(item)
            }

            parent.extraMenuBuilder?(menu, self)

            let point = NSPoint(x: 0, y: sender.bounds.height + 4)
            menu.popUp(positioning: nil, at: point, in: sender)
        }

        @objc func selectSortOption(_ item: NSMenuItem) {
            guard let raw = item.representedObject as? String,
                  let option = S(rawValue: raw) else { return }
            parent.sortOption = option
        }

        @objc func selectDirection(_ item: NSMenuItem) {
            guard let raw = item.representedObject as? String,
                  let direction = SortDirection(rawValue: raw) else { return }
            parent.sortDirection = direction
        }

        @objc func selectExtra(_ item: NSMenuItem) {
            guard let callback = item.representedObject as? () -> Void else { return }
            callback()
        }
    }
}
