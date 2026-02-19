import Testing
@testable import LinnetAudio

@Test func crossfadeDefaults() {
    let manager = CrossfadeManager()
    #expect(manager.isEnabled == false)
    #expect(manager.duration == 3.0)
}

@Test func crossfadeCanBeConfigured() {
    let manager = CrossfadeManager()
    manager.isEnabled = true
    manager.duration = 5.0
    #expect(manager.isEnabled == true)
    #expect(manager.duration == 5.0)
}

@Test func crossfadeDurationRange() {
    let manager = CrossfadeManager()
    manager.duration = 1.0
    #expect(manager.duration >= 1.0)
    manager.duration = 12.0
    #expect(manager.duration <= 12.0)
}
