import Testing
import Foundation
@testable import LinnetAudio

@Test func playbackStateTransitions() {
    var state = PlaybackState.stopped
    #expect(state == .stopped)

    state = .playing
    #expect(state == .playing)

    state = .paused
    #expect(state == .paused)
}

@Test func audioPlayerInitialization() async throws {
    let player = AudioPlayer()
    let state = await player.state
    #expect(state == .stopped)
}
