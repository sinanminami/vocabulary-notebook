import Foundation
import Testing
@testable import VocabularyCore

@Suite("Vocabulary export")
struct VocabularyExportServiceTests {
    @Test("CSV escapes user content and includes learning metadata")
    func csvEscaping() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cardID = UUID()
        let tagID = UUID()
        let card = VocabularyCard(
            id: cardID,
            term: "state-of-the-art",
            normalizedTerm: "state-of-the-art",
            languageCode: .english,
            translationZH: "最先进的, 顶尖的",
            definitionEN: "using the newest methods",
            exampleSentence: "The report says, \"state-of-the-art\".",
            encounterCount: 3,
            createdAt: now,
            updatedAt: now,
            lastEncounteredAt: now
        )
        let tag = Tag(
            id: tagID,
            name: "Academic / Paper",
            normalizedName: "academic / paper",
            isSystem: true,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now
        )
        let state = ReviewState(
            id: UUID(),
            cardID: cardID,
            dueAt: now,
            stability: 12,
            reps: 3,
            fsrsState: .review,
            lastReviewedAt: now,
            updatedAt: now
        )

        let data = VocabularyExportService().csvData(
            cards: [card],
            tags: [tag],
            tagIDsByCardID: [cardID: [tagID]],
            reviewStates: [state]
        )
        let csv = String(decoding: data, as: UTF8.self)

        #expect(csv.contains("\"最先进的, 顶尖的\""))
        #expect(csv.contains("\"The report says, \"\"state-of-the-art\"\".\""))
        #expect(csv.contains("Academic / Paper"))
        #expect(csv.contains(",familiar,3,"))
        #expect(csv.contains("memory_strategy"))
        #expect(csv.contains("pronunciation_ipa"))
    }

    @Test("Health report finds incomplete and untagged cards")
    func healthReport() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let card = VocabularyCard(
            id: UUID(),
            term: "term",
            normalizedTerm: "term",
            languageCode: .english,
            translationZH: "释义",
            definitionEN: "",
            exampleSentence: "",
            encounterCount: 1,
            createdAt: now,
            updatedAt: now,
            lastEncounteredAt: now
        )

        let report = VocabularyExportService().healthReport(
            cards: [card],
            tagIDsByCardID: [:]
        )
        #expect(report.incompleteCardCount == 1)
        #expect(report.untaggedCardCount == 1)
        #expect(report.missingMemoryInsightCount == 1)
        #expect(report.missingPronunciationCount == 1)
    }
}
