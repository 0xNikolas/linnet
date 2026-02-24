import Foundation

extension String {
    /// Case-insensitive AND diacritic-insensitive search.
    /// "SKA" matches "SKÁLD", "cafe" matches "café", etc.
    func searchContains(_ query: String) -> Bool {
        range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
