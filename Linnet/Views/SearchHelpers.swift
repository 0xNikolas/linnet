import Foundation

extension String {
    /// Case-insensitive AND diacritic-insensitive search.
    /// "SKA" matches "SKÁLD", "cafe" matches "café", etc.
    func searchContains(_ query: String) -> Bool {
        range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

/// Sanitize a user query for FTS5 MATCH. Returns nil if the query has no usable
/// tokens (in which case callers should fall back to LIKE-only matching).
///
/// Note: FTS5 `MATCH` cannot be combined with `OR` against a LEFT JOINed FTS
/// table ("unable to use function MATCH in the requested context"). Use it via
/// a subquery instead: `track.id IN (SELECT rowid FROM trackFts WHERE trackFts MATCH ?)`.
func sanitizedFTSQuery(_ query: String) -> String? {
    let tokens = query
        .components(separatedBy: .whitespaces)
        .map { $0.filter { $0.isLetter || $0.isNumber } }
        .filter { !$0.isEmpty }
    guard !tokens.isEmpty else { return nil }
    return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
}
