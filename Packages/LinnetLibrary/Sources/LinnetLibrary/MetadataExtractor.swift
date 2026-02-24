@preconcurrency import AVFoundation
import CoreMedia

public struct TrackMetadata: Sendable {
    public let title: String?
    public let artist: String?
    public let album: String?
    public let trackNumber: Int?
    public let discNumber: Int?
    public let year: Int?
    public let genre: String?
    public let duration: Double
    public let artwork: Data?
    public let bitrate: Int?
    public let sampleRate: Int?
    public let channels: Int?
    public let codec: String?
    public let fileSize: Int64?

    public init(title: String?, artist: String?, album: String?, trackNumber: Int?, discNumber: Int?, year: Int?, genre: String?, duration: Double, artwork: Data?, bitrate: Int? = nil, sampleRate: Int? = nil, channels: Int? = nil, codec: String? = nil, fileSize: Int64? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.year = year
        self.genre = genre
        self.duration = duration
        self.artwork = artwork
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channels = channels
        self.codec = codec
        self.fileSize = fileSize
    }
}

public actor MetadataExtractor {
    public init() {}

    public func extract(from url: URL) async throws -> TrackMetadata {
        let asset = AVURLAsset(url: url)
        let commonMetadata = (try? await asset.load(.commonMetadata)) ?? []
        let durationCM = try await asset.load(.duration)
        let duration = durationCM.seconds.isFinite ? durationCM.seconds : 0

        var title: String?
        var artist: String?
        var album: String?
        var trackNumber: Int?
        var discNumber: Int?
        var year: Int?
        var genre: String?
        var artwork: Data?

        // Read common metadata (title, artist, album, artwork)
        for item in commonMetadata {
            guard let key = item.commonKey else { continue }
            switch key {
            case .commonKeyTitle: title = try? await item.load(.stringValue)
            case .commonKeyArtist: artist = try? await item.load(.stringValue)
            case .commonKeyAlbumName: album = try? await item.load(.stringValue)
            case .commonKeyArtwork: artwork = try? await item.load(.dataValue)
            default: break
            }
        }

        // Read format-specific metadata for trackNumber, discNumber, year, genre
        let availableFormats = (try? await asset.load(.availableMetadataFormats)) ?? []
        for format in availableFormats {
            let formatMetadata = try await asset.loadMetadata(for: format)
            for item in formatMetadata {
                let identifier = item.identifier
                let keyString = item.key as? String

                // Match by identifier (ID3, iTunes) or by Vorbis comment key string
                if let identifier {
                    switch identifier {
                    // ID3 tags
                    case .id3MetadataTrackNumber:
                        if let str = try? await item.load(.stringValue) {
                            trackNumber = trackNumber ?? parseTrackDisc(str)
                        }
                    case .id3MetadataPartOfASet:
                        if let str = try? await item.load(.stringValue) {
                            discNumber = discNumber ?? parseTrackDisc(str)
                        }
                    case .id3MetadataYear, .id3MetadataRecordingTime:
                        if let str = try? await item.load(.stringValue) {
                            year = year ?? parseYear(str)
                        }
                    case .id3MetadataContentType:
                        if genre == nil { genre = try? await item.load(.stringValue) }

                    // iTunes / MP4 tags
                    case .iTunesMetadataTrackNumber:
                        if let data = try? await item.load(.dataValue) {
                            trackNumber = trackNumber ?? parseITunesTrackDisc(data)
                        }
                    case .iTunesMetadataDiscNumber:
                        if let data = try? await item.load(.dataValue) {
                            discNumber = discNumber ?? parseITunesTrackDisc(data)
                        }
                    case .iTunesMetadataReleaseDate:
                        if let str = try? await item.load(.stringValue) {
                            year = year ?? parseYear(str)
                        }
                    case .iTunesMetadataUserGenre, .iTunesMetadataPredefinedGenre:
                        if genre == nil { genre = try? await item.load(.stringValue) }

                    // ISO user data
                    case .isoUserDataDate:
                        if let str = try? await item.load(.stringValue) {
                            year = year ?? parseYear(str)
                        }

                    default: break
                    }
                }

                // Vorbis comments (FLAC, OGG) — keys are uppercase strings
                if let key = keyString?.uppercased() {
                    switch key {
                    case "TITLE":
                        if title == nil { title = try? await item.load(.stringValue) }
                    case "ARTIST":
                        if artist == nil { artist = try? await item.load(.stringValue) }
                    case "ALBUM":
                        if album == nil { album = try? await item.load(.stringValue) }
                    case "TRACKNUMBER":
                        if let str = try? await item.load(.stringValue) {
                            trackNumber = trackNumber ?? parseTrackDisc(str)
                        }
                    case "DISCNUMBER":
                        if let str = try? await item.load(.stringValue) {
                            discNumber = discNumber ?? parseTrackDisc(str)
                        }
                    case "DATE", "YEAR":
                        if let str = try? await item.load(.stringValue) {
                            year = year ?? parseYear(str)
                        }
                    case "GENRE":
                        if genre == nil { genre = try? await item.load(.stringValue) }
                    default: break
                    }
                }
            }
        }

        // Fallback: parse metadata from filename pattern like "01 - Artist - Title"
        if title == nil && artist == nil {
            let filename = url.deletingPathExtension().lastPathComponent
            let parsed = parseFilename(filename)
            title = parsed.title ?? filename
            artist = parsed.artist
            trackNumber = trackNumber ?? parsed.trackNumber
        } else if title == nil {
            title = url.deletingPathExtension().lastPathComponent
        }

        // Use parent folder name as album if not set
        if album == nil {
            let parentName = url.deletingLastPathComponent().lastPathComponent
            if !parentName.isEmpty && parentName != "/" {
                album = parentName
            }
        }

        // Extract audio properties
        var bitrate: Int?
        var sampleRate: Int?
        var channels: Int?
        var codec: String?

        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        if let audioTrack = audioTracks.first {
            let dataRate = (try? await audioTrack.load(.estimatedDataRate)) ?? 0
            if dataRate > 0 {
                bitrate = Int(dataRate / 1000) // kbps
            }
            if let formatDescriptions = try? await audioTrack.load(.formatDescriptions),
               let desc = formatDescriptions.first {
                let basicDesc = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee
                if let basicDesc {
                    sampleRate = Int(basicDesc.mSampleRate)
                    channels = Int(basicDesc.mChannelsPerFrame)
                }
                let formatID = CMFormatDescriptionGetMediaSubType(desc)
                codec = codecName(for: formatID)
            }
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil

        return TrackMetadata(
            title: title, artist: artist, album: album,
            trackNumber: trackNumber, discNumber: discNumber,
            year: year, genre: genre, duration: duration, artwork: artwork,
            bitrate: bitrate, sampleRate: sampleRate, channels: channels,
            codec: codec, fileSize: fileSize
        )
    }

    /// Parse filenames like "01 - Artist - Title" or "01 - Title" or "Artist - Title"
    private func parseFilename(_ name: String) -> (title: String?, artist: String?, trackNumber: Int?) {
        let parts = name.components(separatedBy: " - ")
        switch parts.count {
        case 3...:
            // "01 - Artist - Title (extra info)"
            let num = Int(parts[0].trimmingCharacters(in: .whitespaces))
            let artist = parts[1].trimmingCharacters(in: .whitespaces)
            let title = parts[2...].joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            return (title, artist, num)
        case 2:
            let first = parts[0].trimmingCharacters(in: .whitespaces)
            let second = parts[1].trimmingCharacters(in: .whitespaces)
            if let num = Int(first) {
                // "01 - Title"
                return (second, nil, num)
            } else {
                // "Artist - Title"
                return (second, first, nil)
            }
        default:
            return (name, nil, nil)
        }
    }

    /// Parse "3/12" or "3" format into the first number
    private func parseTrackDisc(_ str: String) -> Int? {
        let part = str.split(separator: "/").first.map(String.init) ?? str
        return Int(part.trimmingCharacters(in: .whitespaces))
    }

    /// Parse 4-digit year from strings like "2023", "2023-05-01", "2023-05-01T00:00:00Z"
    private func parseYear(_ str: String) -> Int? {
        let digits = str.prefix(4)
        guard digits.count == 4 else { return nil }
        return Int(digits)
    }

    /// Parse iTunes binary track/disc number (big-endian: 2 bytes padding, 2 bytes value, 2 bytes total)
    private func parseITunesTrackDisc(_ data: Data) -> Int? {
        guard data.count >= 4 else { return nil }
        let value = Int(data[2]) << 8 | Int(data[3])
        return value > 0 ? value : nil
    }

    private func codecName(for formatID: FourCharCode) -> String {
        switch formatID {
        case kAudioFormatMPEGLayer3: return "MP3"
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2: return "AAC"
        case kAudioFormatAppleLossless: return "ALAC"
        case kAudioFormatFLAC: return "FLAC"
        case kAudioFormatLinearPCM: return "WAV"
        case kAudioFormatAC3: return "AC3"
        case kAudioFormatOpus: return "Opus"
        case kAudioFormatAppleIMA4: return "IMA4"
        default:
            let chars = [
                UInt8((formatID >> 24) & 0xFF),
                UInt8((formatID >> 16) & 0xFF),
                UInt8((formatID >> 8) & 0xFF),
                UInt8(formatID & 0xFF)
            ]
            let str = String(bytes: chars, encoding: .ascii) ?? "Unknown"
            return str.trimmingCharacters(in: .whitespaces)
        }
    }
}
