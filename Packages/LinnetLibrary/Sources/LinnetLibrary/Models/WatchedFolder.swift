import Foundation
import SwiftData

@Model
public final class WatchedFolder {
    #Unique<WatchedFolder>([\.path])

    public var path: String
    public var lastScanned: Date?
    public var isEnabled: Bool
    public var bookmarkData: Data?

    public init(path: String, bookmarkData: Data? = nil) {
        self.path = path
        self.isEnabled = true
        self.bookmarkData = bookmarkData
    }
}
