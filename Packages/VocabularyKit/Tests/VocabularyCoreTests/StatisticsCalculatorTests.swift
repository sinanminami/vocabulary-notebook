import Foundation
import Testing
@testable import VocabularyCore

@Suite("Statistics calculator")
struct StatisticsCalculatorTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 2
        return value
    }

    @Test("Due Today excludes unseen new cards")
    func dueTodayExcludesNewCards() throws {
        let now = try date(2026, 8, 24, 12)
        let newCard = card(createdAt: try date(2026, 8, 24, 8))
        let learnedCard = card(createdAt: try date(2026, 8, 20, 8))
        let result = StatisticsCalculator().calculate(
            cards: [newCard, learnedCard],
            reviewStates: [
                state(cardID: newCard.id, dueAt: try date(2026, 8, 24, 9), reps: 0, fsrsState: .new),
                state(cardID: learnedCard.id, dueAt: try date(2026, 8, 24, 9), reps: 2, fsrsState: .review)
            ],
            reviewLogs: [],
            now: now,
            calendar: calendar
        )

        #expect(result.dueToday == 1)
        #expect(result.count(.new) == 1)
        #expect(result.count(.learning) == 1)
    }

    @Test("Weekly counts respect the local calendar boundary")
    func weeklyCounts() throws {
        let now = try date(2026, 8, 26, 12)
        let thisWeek = card(createdAt: try date(2026, 8, 24, 0))
        let previousWeek = card(createdAt: try date(2026, 8, 23, 23))
        let logs = [
            log(cardID: thisWeek.id, reviewedAt: try date(2026, 8, 24, 0), previousReps: 0),
            log(cardID: previousWeek.id, reviewedAt: try date(2026, 8, 23, 23), previousReps: 1)
        ]
        let result = StatisticsCalculator().calculate(
            cards: [thisWeek, previousWeek],
            reviewStates: [],
            reviewLogs: logs,
            now: now,
            calendar: calendar
        )

        #expect(result.thisWeekAdded == 1)
        #expect(result.thisWeekReviewed == 1)
    }

    @Test("Retention excludes a card's first review")
    func retentionDefinition() throws {
        let now = try date(2026, 8, 24, 12)
        let cardID = UUID()
        let logs = [
            log(cardID: cardID, reviewedAt: try date(2026, 8, 22, 10), rating: .again, previousReps: 0),
            log(cardID: cardID, reviewedAt: try date(2026, 8, 23, 10), rating: .again, previousReps: 1),
            log(cardID: cardID, reviewedAt: try date(2026, 8, 24, 10), rating: .good, previousReps: 2)
        ]
        let result = StatisticsCalculator().calculate(
            cards: [],
            reviewStates: [],
            reviewLogs: logs,
            now: now,
            calendar: calendar
        )

        #expect(result.retentionSampleCount == 2)
        #expect(result.retentionSuccessPercent == 50)
    }

    @Test("Activity fills empty days")
    func dailyActivity() throws {
        let now = try date(2026, 8, 24, 12)
        let result = StatisticsCalculator().calculate(
            cards: [],
            reviewStates: [],
            reviewLogs: [
                log(cardID: UUID(), reviewedAt: try date(2026, 8, 22, 10), previousReps: 1)
            ],
            now: now,
            calendar: calendar,
            activityDays: 3
        )

        #expect(result.dailyReviewActivity.map(\.reviewCount) == [1, 0, 0])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        )))
    }

    private func card(createdAt: Date) -> VocabularyCard {
        VocabularyCard(
            id: UUID(),
            term: "term",
            normalizedTerm: "term",
            languageCode: .english,
            translationZH: "释义",
            definitionEN: "definition",
            exampleSentence: "Example.",
            encounterCount: 1,
            createdAt: createdAt,
            updatedAt: createdAt,
            lastEncounteredAt: createdAt
        )
    }

    private func state(
        cardID: UUID,
        dueAt: Date,
        reps: Int,
        fsrsState: FSRSCardState
    ) -> ReviewState {
        ReviewState(
            id: UUID(),
            cardID: cardID,
            dueAt: dueAt,
            stability: reps == 0 ? 0 : 2,
            reps: reps,
            fsrsState: fsrsState,
            updatedAt: dueAt
        )
    }

    private func log(
        cardID: UUID,
        reviewedAt: Date,
        rating: ReviewRating = .good,
        previousReps: Int
    ) -> ReviewLogEntry {
        let previous = state(
            cardID: cardID,
            dueAt: reviewedAt,
            reps: previousReps,
            fsrsState: previousReps == 0 ? .new : .review
        )
        var next = previous
        next.reps += 1
        next.fsrsState = .review
        return ReviewLogEntry(
            id: UUID(),
            cardID: cardID,
            reviewedAt: reviewedAt,
            rating: rating,
            reviewMode: .termToMeaning,
            previousState: previous,
            newState: next,
            scheduledIntervalDays: 1,
            schedulerVersion: "fsrs-6"
        )
    }
}
