import Foundation
import Testing
@testable import VocabularyCore

@Suite("Mastery policy")
struct MasteryPolicyTests {
    private let policy = MasteryPolicy()

    @Test("A card with no reviews is new")
    func newCard() {
        #expect(policy.level(for: state(reps: 0, stability: 0, fsrsState: .new)) == .new)
    }

    @Test("Learning and low-stability cards are learning")
    func learningCard() {
        #expect(policy.level(for: state(reps: 2, stability: 12, fsrsState: .learning)) == .learning)
        #expect(policy.level(for: state(reps: 3, stability: 6.99, fsrsState: .review)) == .learning)
        #expect(policy.level(for: state(reps: 8, stability: 60, fsrsState: .relearning)) == .learning)
    }

    @Test("Review cards between thresholds are familiar")
    func familiarCard() {
        #expect(policy.level(for: state(reps: 3, stability: 15, fsrsState: .review)) == .familiar)
        #expect(policy.level(for: state(reps: 4, stability: 30, fsrsState: .review)) == .familiar)
    }

    @Test("Mastered requires review state, stability, and repetitions")
    func masteredCard() {
        #expect(policy.level(for: state(reps: 5, stability: 30, fsrsState: .review)) == .mastered)
    }

    private func state(
        reps: Int,
        stability: Double,
        fsrsState: FSRSCardState
    ) -> ReviewState {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return ReviewState(
            id: UUID(),
            cardID: UUID(),
            dueAt: now,
            stability: stability,
            reps: reps,
            fsrsState: fsrsState,
            updatedAt: now
        )
    }
}
