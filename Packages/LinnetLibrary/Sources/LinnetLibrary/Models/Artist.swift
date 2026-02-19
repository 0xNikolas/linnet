import Foundation
import SwiftData

@Model
public final class Artist {
    #Unique<Artist>([\.name])

    public var name: String

    @Relationship(deleteRule: .nullify, inverse: \Album.artist)
    public var albums: [Album]

    @Relationship(deleteRule: .nullify, inverse: \Track.artist)
    public var tracks: [Track]

    public init(name: String) {
        self.name = name
        self.albums = []
        self.tracks = []
    }
}
