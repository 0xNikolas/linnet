import Testing
import AVFoundation
@testable import LinnetAudio

@Test func gaplessSchedulerTracksNodes() {
    let scheduler = GaplessScheduler()
    #expect(scheduler.activeNodeIndex == 0)

    scheduler.swap()
    #expect(scheduler.activeNodeIndex == 1)

    scheduler.swap()
    #expect(scheduler.activeNodeIndex == 0)
}

@Test func activeAndNextNodeAreDifferent() {
    let scheduler = GaplessScheduler()
    #expect(scheduler.activeNode !== scheduler.nextNode)
}

@Test func swapChangesActiveNode() {
    let scheduler = GaplessScheduler()
    let firstActive = scheduler.activeNode
    scheduler.swap()
    #expect(scheduler.activeNode !== firstActive)
    #expect(scheduler.nextNode === firstActive)
}
