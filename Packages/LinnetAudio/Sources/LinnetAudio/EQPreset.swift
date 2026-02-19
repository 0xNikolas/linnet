public struct EQBand: Sendable, Codable {
    public let frequency: Float
    public var gain: Float
    public let bandwidth: Float

    public init(frequency: Float, gain: Float, bandwidth: Float = 1.0) {
        self.frequency = frequency
        self.gain = gain
        self.bandwidth = bandwidth
    }
}

public struct EQPreset: Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public var bands: [EQBand]

    public static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    public static let flat = EQPreset(
        id: "flat", name: "Flat",
        bands: frequencies.map { EQBand(frequency: $0, gain: 0) }
    )

    public static let bassBoost = EQPreset(
        id: "bass_boost", name: "Bass Boost",
        bands: zip(frequencies, [6, 5, 4, 2, 0, 0, 0, 0, 0, 0] as [Float]).map { EQBand(frequency: $0, gain: $1) }
    )

    public static let vocal = EQPreset(
        id: "vocal", name: "Vocal",
        bands: zip(frequencies, [-2, -1, 0, 2, 4, 4, 2, 0, -1, -2] as [Float]).map { EQBand(frequency: $0, gain: $1) }
    )

    public static let rock = EQPreset(
        id: "rock", name: "Rock",
        bands: zip(frequencies, [4, 3, 1, 0, -1, 0, 2, 3, 4, 4] as [Float]).map { EQBand(frequency: $0, gain: $1) }
    )

    public static let electronic = EQPreset(
        id: "electronic", name: "Electronic",
        bands: zip(frequencies, [5, 4, 2, 0, -2, 0, 1, 3, 4, 5] as [Float]).map { EQBand(frequency: $0, gain: $1) }
    )

    public static let allPresets: [EQPreset] = [flat, bassBoost, vocal, rock, electronic]
}
