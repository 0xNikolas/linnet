import Foundation
import GRDB

/// Protocol for Linnet plugins that need their own database tables.
/// Plugin tables must use the prefix `plugin_{pluginId}_` to avoid collisions.
public protocol LinnetPlugin: Sendable {
    /// Unique identifier for this plugin (e.g. "lyrics", "lastfm").
    var pluginId: String { get }

    /// Register migrations for this plugin's tables.
    /// Table names MUST start with `plugin_{pluginId}_`.
    func registerMigrations(in migrator: inout DatabaseMigrator)
}
