import Foundation

/// Where the Linnet database file is stored.
public enum DatabaseLocation: Sendable {
    /// ~/Library/Application Support/Linnet/linnet.db (default)
    case appSupport
    /// Same folder as the first watched music folder
    case musicFolder(URL)
    /// User-specified path
    case custom(URL)

    public var url: URL {
        switch self {
        case .appSupport:
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!
            let dir = appSupport.appendingPathComponent("Linnet", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("linnet.db")
        case .musicFolder(let folder):
            let dir = folder.appendingPathComponent(".linnet", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("linnet.db")
        case .custom(let url):
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return url
        }
    }

    // MARK: - Persistence

    private static let locationTypeKey = "databaseLocationType"
    private static let locationPathKey = "databaseLocationPath"

    /// Save the current location choice to UserDefaults.
    public func save() {
        switch self {
        case .appSupport:
            UserDefaults.standard.set("appSupport", forKey: Self.locationTypeKey)
            UserDefaults.standard.removeObject(forKey: Self.locationPathKey)
        case .musicFolder(let url):
            UserDefaults.standard.set("musicFolder", forKey: Self.locationTypeKey)
            UserDefaults.standard.set(url.path, forKey: Self.locationPathKey)
        case .custom(let url):
            UserDefaults.standard.set("custom", forKey: Self.locationTypeKey)
            UserDefaults.standard.set(url.path, forKey: Self.locationPathKey)
        }
    }

    /// Load the saved location from UserDefaults. Returns `.appSupport` if nothing saved.
    public static func saved() -> DatabaseLocation {
        let type = UserDefaults.standard.string(forKey: locationTypeKey) ?? "appSupport"
        let path = UserDefaults.standard.string(forKey: locationPathKey)

        switch type {
        case "musicFolder":
            if let path, !path.isEmpty {
                return .musicFolder(URL(filePath: path))
            }
            return .appSupport
        case "custom":
            if let path, !path.isEmpty {
                return .custom(URL(filePath: path))
            }
            return .appSupport
        default:
            return .appSupport
        }
    }

    /// Copy database files from one location to another.
    /// Copies the main .db file plus WAL/SHM journals if present.
    public static func copyDatabase(from source: DatabaseLocation, to destination: DatabaseLocation) throws {
        let srcURL = source.url
        let dstURL = destination.url
        guard srcURL != dstURL else { return }

        let fm = FileManager.default
        // Remove existing destination if present
        if fm.fileExists(atPath: dstURL.path) {
            try fm.removeItem(at: dstURL)
        }
        try fm.copyItem(at: srcURL, to: dstURL)

        // Also copy WAL and SHM if they exist
        for suffix in ["-wal", "-shm"] {
            let srcJournal = URL(filePath: srcURL.path + suffix)
            let dstJournal = URL(filePath: dstURL.path + suffix)
            if fm.fileExists(atPath: srcJournal.path) {
                if fm.fileExists(atPath: dstJournal.path) {
                    try fm.removeItem(at: dstJournal)
                }
                try fm.copyItem(at: srcJournal, to: dstJournal)
            }
        }
    }

    /// Human-readable description of the location.
    public var displayString: String {
        switch self {
        case .appSupport:
            return "App Support (default)"
        case .musicFolder(let url):
            return url.lastPathComponent
        case .custom(let url):
            return url.deletingLastPathComponent().path
        }
    }
}
