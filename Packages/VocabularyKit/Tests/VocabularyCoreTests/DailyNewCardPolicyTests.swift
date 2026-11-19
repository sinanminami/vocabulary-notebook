import Foundation
import Testing
@testable import VocabularyCore

@Suite("Daily new-card policy")
struct DailyNewCardPolicyTests {
    @Test("Counts each newly introduced card once per calendar day")
    func uniqueNewCards() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        let firstCardID = UUID()
        let secondCardID = UUID()
        let logs = [
            log(cardID: firstCardID, reviewedAt: today, previousReps: 0),
            log(cardID: firstCardID, reviewedAt: today.addingTimeInterval(60), previousReps: 1),
            log(cardID: secondCardID, reviewedAt: today.addingTimeInterval(120), previousReps: 0),
            log(cardID: UUID(), reviewedAt: today.addingTimeInterval(-86_400), previousReps: 0)
        ]

        let policy = DailyNewCardPolicy()
        #expect(policy.consumedCount(from: logs, on: today, calendar: calendar) == 2)
        #expect(policy.remainingCount(dailyLimit: 5, logs: logs, on: today, calendar: calendar) == 3)
    }

    @Test("Never returns a negative remaining quota")
    func clampsAtZero() {
        let now = Date()
        let logs = (0..<3).map { _ in
            log(cardID: UUID(), reviewedAt: now, previousReps: 0)
        }
        #expect(DailyNewCardPolicy().remainingCount(dailyLimit: 1, logs: logs, on: now) == 0)
    }

    @Test("Counts two new meanings of one spelling as two learning units")
    func countsSenseLearningUnits() {
        let now = Date()
        let cardID = UUID()
        let logs = [
            log(cardID: cardID, senseID: UUID(), reviewedAt: now, previousReps: 0),
            log(cardID: cardID, senseID: UUID(), reviewedAt: now.addingTimeInterval(1), previousReps: 0)
        ]

        #expect(DailyNewCardPolicy().consumedCount(from: logs, on: now) == 2)
    }

    private func log(
        cardID: UUID,
        senseID: UUID? = nil,
        reviewedAt: Date,
        previousReps: Int
    ) -> ReviewLogEntry {
        let previous = ReviewState(
            id: UUID(),
            cardID: cardID,
            senseID: senseID,
            dueAt: reviewedAt,
            reps: previousReps,
            fsrsState: previousReps == 0 ? .new : .review,
            updatedAt: reviewedAt
        )
        var next = previous
        next.reps += 1
        next.fsrsState = .review
        return ReviewLogEntry(
            id: UUID(),
            cardID: cardID,
            senseID: senseID,
            reviewedAt: reviewedAt,
            rating: .good,
            reviewMode: .termToMeaning,
            previousState: previous,
            newState: next,
            scheduledIntervalDays: 1,
            schedulerVersion: "test"
        )
    }
}
