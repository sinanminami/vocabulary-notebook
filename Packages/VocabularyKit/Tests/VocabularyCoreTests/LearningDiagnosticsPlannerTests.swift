import Foundation
import Testing
@testable import VocabularyCore

@Suite("Learning diagnostics planner")
struct LearningDiagnosticsPlannerTests {
    @Test("Repeated forgetting prefers a saved contrast")
    func repeatedForgettingUsesContrast() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let card = makeCard(ipa: "/kənˈsɪdərəbəl/")
        let sense = makeSense(
            cardID: card.id,
            insight: MemoryInsight(
                strategy: .contrast,
                titleZH: "可观 vs 体贴",
                cueZH: "一个说数量，一个说待人周到。",
                mnemonic: "先判断是在说规模还是态度。",
                contrastNoteZH: "不要与 considerate 混淆。"
            )
        )
        let record = SenseLearningRecord(
            card: card,
            sense: sense,
            state: makeState(cardID: card.id, senseID: sense.id, now: now, reps: 5, lapses: 2),
            encounters: [],
            reviewLogs: []
        )
        let planner = LearningDiagnosticsPlanner()

        #expect(planner.adaptivePrompt(for: record, now: now) == .contrast)
        #expect(planner.rankedDiagnostics(from: [record], now: now).first?.signal == .repeatedForgetting)
    }

    @Test("Sustained difficulty introduces listening practice")
    func highDifficultyUsesListening() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let card = makeCard(ipa: "/kənˈsɪdərəbəl/")
        let sense = makeSense(cardID: card.id)
        let record = SenseLearningRecord(
            card: card,
            sense: sense,
            state: makeState(cardID: card.id, senseID: sense.id, now: now, reps: 4, difficulty: 8.2),
            encounters: [],
            reviewLogs: []
        )

        #expect(LearningDiagnosticsPlanner().adaptivePrompt(for: record, now: now) == .listening)
    }

    @Test("Context prompts replace only the target term")
    func buildsClozeSentence() {
        let result = LearningDiagnosticsPlanner().clozeSentence(
            term: "Considerable",
            example: "A considerable improvement appeared."
        )
        #expect(result == "A ______ improvement appeared.")
    }

    private func makeCard(ipa: String) -> VocabularyCard {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        return VocabularyCard(
            id: UUID(),
            term: "considerable",
            normalizedTerm: "considerable",
            languageCode: .english,
            pronunciationIPA: ipa,
            translationZH: "相当大的",
            definitionEN: "notably large",
            exampleSentence: "A considerable improvement appeared.",
            encounterCount: 1,
            createdAt: now,
            updatedAt: now,
            lastEncounteredAt: now
        )
    }

    private func makeSense(cardID: UUID, insight: MemoryInsight? = nil) -> VocabularySense {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        return VocabularySense(
            id: UUID(),
            cardID: cardID,
            sortOrder: 0,
            isPrimary: true,
            translationZH: "相当大的",
            definitionEN: "notably large",
            exampleSentence: "A considerable improvement appeared.",
            memoryInsight: insight,
            createdAt: now,
            updatedAt: now
        )
    }

    private func makeState(
        cardID: UUID,
        senseID: UUID,
        now: Date,
        reps: Int,
        lapses: Int = 0,
        difficulty: Double = 5
    ) -> ReviewState {
        ReviewState(
            id: UUID(),
            cardID: cardID,
            senseID: senseID,
            dueAt: now.addingTimeInterval(86_400),
            stability: 4,
            difficulty: difficulty,
            reps: reps,
            lapses: lapses,
            fsrsState: .review,
            lastReviewedAt: now.addingTimeInterval(-86_400),
            updatedAt: now
        )
    }
}
