import Testing
import Foundation
@testable import LinnetAI

@Test func cosineSimilarityIdentical() {
    let a: [Float] = [1, 0, 0]
    let b: [Float] = [1, 0, 0]
    let sim = VectorUtils.cosineSimilarity(a, b)
    #expect(abs(sim - 1.0) < 0.001)
}

@Test func cosineSimilarityOrthogonal() {
    let a: [Float] = [1, 0, 0]
    let b: [Float] = [0, 1, 0]
    let sim = VectorUtils.cosineSimilarity(a, b)
    #expect(abs(sim) < 0.001)
}

@Test func cosineSimilarityOpposite() {
    let a: [Float] = [1, 0, 0]
    let b: [Float] = [-1, 0, 0]
    let sim = VectorUtils.cosineSimilarity(a, b)
    #expect(abs(sim - (-1.0)) < 0.001)
}

@Test func nearestNeighborsOrdering() {
    let query: [Float] = [1, 0, 0]
    let candidates: [(id: String, embedding: [Float])] = [
        ("a", [0.9, 0.1, 0]),    // most similar
        ("b", [0, 1, 0]),        // orthogonal
        ("c", [0.5, 0.5, 0]),    // medium
    ]
    let results = VectorUtils.nearestNeighbors(query: query, candidates: candidates, k: 3)
    #expect(results[0].id == "a")
    #expect(results[1].id == "c")
    #expect(results[2].id == "b")
}

@Test func embeddingSerializationRoundtrip() {
    let original: [Float] = [1.0, 2.5, -3.14, 0.0, 42.0]
    let data = VectorUtils.serialize(original)
    let restored = VectorUtils.deserialize(data)
    #expect(original == restored)
}

@Test func modelManagerStatuses() async {
    let manager = ModelManager.shared
    for model in AIModelType.allCases {
        let status = await manager.status(for: model)
        // Should be either .notDownloaded or .ready
        switch status {
        case .notDownloaded, .ready: break
        default: Issue.record("Unexpected status for \(model)")
        }
    }
}
