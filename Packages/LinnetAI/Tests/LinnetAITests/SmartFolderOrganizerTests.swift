import Testing
import Foundation
@testable import LinnetAI

@Test func folderSuggestionCreation() {
    let suggestion = FolderSuggestion(
        folderName: "Rock Classics",
        trackFilePaths: ["/a.mp3", "/b.mp3"],
        description: "2 tracks"
    )
    #expect(suggestion.folderName == "Rock Classics")
    #expect(suggestion.trackFilePaths.count == 2)
}

@Test func organizationPlanTotalTracks() {
    let plan = FolderOrganizationPlan(
        suggestions: [
            FolderSuggestion(folderName: "A", trackFilePaths: ["/1.mp3", "/2.mp3"]),
            FolderSuggestion(folderName: "B", trackFilePaths: ["/3.mp3"]),
        ],
        baseDirectory: "/music"
    )
    #expect(plan.totalTracks == 3)
}

@Test func emptyTracksReturnsEmptyPlan() async throws {
    let organizer = SmartFolderOrganizer()
    let plan = try await organizer.suggestOrganization(
        tracks: [],
        baseDirectory: "/music"
    )
    #expect(plan.suggestions.isEmpty)
}
