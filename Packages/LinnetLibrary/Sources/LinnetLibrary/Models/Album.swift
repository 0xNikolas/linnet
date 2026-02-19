import Foundation
import SwiftData

@Model
public final class Album {
    #Unique<Album>([\.name, \.artistName])

    public var name: String
    public var artistName: String?
    public var year: Int?
    public var artworkData: Data?

    @Relationship(deleteRule: .nullify, inverse: \Track.album)
    public var tracks: [Track]

    public var artist: Artist?

    public init(name: String, year: Int? = nil, artistName: String? = nil) {
        self.name = name
        self.year = year
        self.artistName = artistName
        self.tracks = []
    }
}
