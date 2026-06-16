import Foundation
import GRDB

/// Single source of truth for building track search SQL, shared by the repository
/// (imperative `pool.read` queries) and by SwiftUI `ValueObservation` closures.
///
/// Keeping this in one place avoids the kind of drift that previously broke
/// search: a view had duplicated the matching SQL and used `trackFts MATCH` in an
/// `OR`/`JOIN` context, which SQLite rejects at runtime
/// ("unable to use function MATCH in the requested context"). The condition below
/// always uses the subquery form, which is safe to combine with `AND`/`OR` and joins.
public enum TrackSearch {
    /// Sanitize a user query for an FTS5 `MATCH`. Returns nil when the query has no
    /// usable tokens, in which case callers fall back to LIKE-only matching.
    public static func sanitizedFTSQuery(_ query: String) -> String? {
        let tokens = query
            .components(separatedBy: .whitespaces)
            .map { $0.filter { $0.isLetter || $0.isNumber } }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    /// A parenthesized boolean SQL condition (no leading `WHERE`/`AND`) matching the
    /// query against title, artist, and album, plus its bound arguments. Returns nil
    /// when there is nothing to search for, so callers can omit the clause entirely.
    ///
    /// Assumes the surrounding query joins `artist` and `album` (see `TrackInfo.baseSQL`).
    public static func condition(for query: String?) -> (sql: String, arguments: [any DatabaseValueConvertible])? {
        guard let query, !query.isEmpty else { return nil }
        let like = "%\(query)%"
        if let fts = sanitizedFTSQuery(query) {
            return (
                "(track.id IN (SELECT rowid FROM trackFts WHERE trackFts MATCH ?) OR track.title LIKE ? OR artist.name LIKE ? OR album.name LIKE ?)",
                [fts, like, like, like]
            )
        } else {
            return (
                "(track.title LIKE ? OR artist.name LIKE ? OR album.name LIKE ?)",
                [like, like, like]
            )
        }
    }
}
