import os

/// Package-scoped loggers for LinnetLibrary, mirroring the app's `Log` so library
/// diagnostics land in the same unified-logging subsystem (`com.linnet.app`).
///
/// Unlike best-effort `print`, these go through the unified log: they're captured in
/// release builds, filterable by category, and never silently lost. Use `.error` for
/// failures that are handled (e.g. a fallback was taken) and `.fault` for unexpected
/// invariants.
enum LibraryLog {
    static let artwork = Logger(subsystem: "com.linnet.app", category: "artwork")
    static let network = Logger(subsystem: "com.linnet.app", category: "network")
    static let database = Logger(subsystem: "com.linnet.app", category: "database")
}
