import Foundation
import SwiftData

@Model
public final class WatchedFolder {
    #Unique<WatchedFolder>([\.path])

    public var path: String
    public var lastScanned: Date?
    public var isEnabled: Bool

    public init(path: String) {
        self.path = path
        self.isEnabled = true
    }
}
