import Foundation
import Testing
@testable import VocabularyCore

@Suite("Review requeue policy")
struct ReviewRequeuePolicyTests {
    @Test("Again stays in the current session")
    func requeuesAgain() {
        #expect(ReviewRequeuePolicy().shouldRequeue(after: log(rating: .again)))
    }

    @Test("Successful recall can complete the current session")
    func completesAfterRecall() {
        let policy = ReviewRequeuePolicy()
        #expect(!policy.shouldRequeue(after: log(rating: .hard)))
        #expect(!policy.shouldRequeue(after: log(rating: .good)))
        #expect(!policy.shouldRequeue(after: log(rating: .easy)))
    }

    private func log(rating: ReviewRating) -> ReviewLogEntry {
        let reviewedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let cardID = UUID()
        let senseID = UUID()
        let previous = ReviewState(
            id: UUID(),
            cardID: cardID,
            senseID: senseID,
            dueAt: reviewedAt,
            reps: 4,
            fsrsState: .review,
            updatedAt: reviewedAt
        )
        var next = previous
        next.dueAt = reviewedAt.addingTimeInterval(60)
        next.reps += 1
        next.fsrsState = rating == .again ? .learning : .review
        return ReviewLogEntry(
            id: UUID(),
            cardID: cardID,
            senseID: senseID,
            reviewedAt: reviewedAt,
            rating: rating,
            reviewMode: .termToMeaning,
            previousState: previous,
            newState: next,
            scheduledIntervalDays: next.scheduledDays,
            schedulerVersion: "fsrs-6"
        )
    }
}
