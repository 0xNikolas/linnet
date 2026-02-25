import os

enum Log {
    #if DEBUG
    static let ui = Logger(subsystem: "com.linnet.app", category: "ui")
    static let navigation = Logger(subsystem: "com.linnet.app", category: "navigation")
    static let player = Logger(subsystem: "com.linnet.app", category: "player")
    static let library = Logger(subsystem: "com.linnet.app", category: "library")
    static let artwork = Logger(subsystem: "com.linnet.app", category: "artwork")
    static let general = Logger(subsystem: "com.linnet.app", category: "general")
    #else
    static let ui = Logger(.disabled)
    static let navigation = Logger(.disabled)
    static let player = Logger(.disabled)
    static let library = Logger(.disabled)
    static let artwork = Logger(.disabled)
    static let general = Logger(.disabled)
    #endif
}
