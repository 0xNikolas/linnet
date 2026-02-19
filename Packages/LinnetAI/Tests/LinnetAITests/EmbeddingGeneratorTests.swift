import Testing
import Foundation
@testable import LinnetAI

@Test func embeddingResultSerialization() {
    let embedding: [Float] = [1.0, 2.0, 3.0, 4.0, 5.0]
    let result = EmbeddingResult(filePath: "/test.mp3", embedding: embedding)

    #expect(result.filePath == "/test.mp3")
    #expect(result.embedding == embedding)

    let deserialized = VectorUtils.deserialize(result.embeddingData)
    #expect(deserialized == embedding)
}
