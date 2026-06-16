import Foundation

/// A SQL ORDER BY fragment that is safe to interpolate into a query.
///
/// Its initializer is internal to LinnetLibrary, so values can only be produced by the
/// library's own sort-column enums (`TrackSortColumn`, `AlbumSortColumn`, …) from fixed
/// string constants — never from external or user input. Consumers receive a `SortSQL`
/// rather than a bare `String`, which makes ORDER BY injection impossible by construction
/// rather than by convention. `CustomStringConvertible` lets it interpolate to its raw SQL.
public struct SortSQL: Sendable, Hashable, CustomStringConvertible {
    public let description: String

    /// Internal: only LinnetLibrary's column enums mint these from compile-time constants.
    init(_ sql: String) {
        self.description = sql
    }
}
