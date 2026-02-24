import SwiftUI

/// Persisted sidebar order and visibility for library items.
struct SidebarConfiguration: Codable, Equatable {
    /// Ordered list of items paired with their visibility.
    var entries: [Entry]

    struct Entry: Codable, Equatable, Identifiable {
        var item: SidebarItem
        var isVisible: Bool
        var id: SidebarItem { item }
    }

    /// Items that should appear in the sidebar (visible and in order).
    var visibleItems: [SidebarItem] {
        entries.filter(\.isVisible).map(\.item)
    }

    /// Default configuration matching the original hard-coded order.
    static let `default` = SidebarConfiguration(
        entries: SidebarItem.allLibraryItems.map { Entry(item: $0, isVisible: true) }
    )

    /// Ensure any new items added in future versions are included.
    mutating func mergeDefaults() {
        let existing = Set(entries.map(\.item))
        for item in SidebarItem.allLibraryItems where !existing.contains(item) {
            entries.append(Entry(item: item, isVisible: true))
        }
    }
}

// MARK: - RawRepresentable for @AppStorage
// Encode/decode the entries array directly to avoid infinite recursion
// (JSONEncoder on a Codable+RawRepresentable type calls rawValue, which calls encode, etc.)

extension SidebarConfiguration: RawRepresentable {
    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return nil
        }
        self.entries = entries
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(entries),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }
}
