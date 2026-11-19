import Foundation
import Testing
@testable import VocabularyCore

@Suite("Review queue randomizer")
struct ReviewQueueRandomizerTests {
    @Test("Shuffles the session while preserving every card exactly once")
    func shufflesWithoutChangingMembership() {
        let queue = (0..<8).map(makeItem)
        var generator = SeededGenerator(seed: 42)

        let randomized = ReviewQueueRandomizer().randomized(queue, using: &generator)

        #expect(randomized.map(\.id) != queue.map(\.id))
        #expect(Set(randomized.map(\.id)) == Set(queue.map(\.id)))
        #expect(randomized.count == queue.count)
    }

    private func makeItem(index: Int) -> ReviewQueueItem {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cardID = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
        let card = VocabularyCard(
            id: cardID,
            term: "word-\(index)",
            normalizedTerm: "word-\(index)",
            languageCode: .english,
            translationZH: "词-\(index)",
            definitionEN: "definition-\(index)",
            exampleSentence: "Example \(index).",
            encounterCount: 1,
            createdAt: now,
            updatedAt: now,
            lastEncounteredAt: now
        )
        let state = ReviewState(
            id: UUID(),
            cardID: cardID,
            dueAt: now,
            updatedAt: now
        )
        return ReviewQueueItem(card: card, state: state)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
