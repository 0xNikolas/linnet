import Testing
@testable import LinnetAudio

@Test func queueAddAndAdvance() {
    var queue = PlaybackQueue()
    queue.add(tracks: ["a.mp3", "b.mp3", "c.mp3"])

    #expect(queue.current == "a.mp3")
    #expect(queue.count == 3)

    let next = queue.advance()
    #expect(next == "b.mp3")
    #expect(queue.current == "b.mp3")
}

@Test func queueGoBack() {
    var queue = PlaybackQueue()
    queue.add(tracks: ["a.mp3", "b.mp3", "c.mp3"])
    _ = queue.advance()
    _ = queue.advance()
    #expect(queue.current == "c.mp3")

    let prev = queue.goBack()
    #expect(prev == "b.mp3")
}

@Test func playNext() {
    var queue = PlaybackQueue()
    queue.add(tracks: ["a.mp3", "b.mp3", "c.mp3"])
    queue.playNext("urgent.mp3")

    let next = queue.advance()
    #expect(next == "urgent.mp3")
}

@Test func playLater() {
    var queue = PlaybackQueue()
    queue.add(tracks: ["a.mp3", "b.mp3"])
    queue.playLater("later.mp3")

    _ = queue.advance() // b.mp3
    let last = queue.advance()
    #expect(last == "later.mp3")
}

@Test func shuffle() {
    var queue = PlaybackQueue()
    queue.add(tracks: (1...20).map { "\($0).mp3" })
    let original = queue.upcoming
    queue.shuffle()
    #expect(queue.current == "1.mp3")
    #expect(queue.upcoming != original)
}

@Test func repeatModes() {
    var queue = PlaybackQueue()
    queue.add(tracks: ["a.mp3", "b.mp3"])

    queue.repeatMode = .one
    let next = queue.advance()
    #expect(next == "a.mp3")

    queue.repeatMode = .all
    _ = queue.advance() // b.mp3
    let wrapped = queue.advance()
    #expect(wrapped == "a.mp3")
}
