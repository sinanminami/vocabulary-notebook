import Foundation
import Testing
import VocabularyCore
@testable import VocabularyPersistence

@Suite("FSRS review repository", .serialized)
struct FSRSReviewRepositoryTests {
    @Test("FSRS 6 previews all ratings in increasing first-review intervals")
    func previewIntervals() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let state = ReviewState(id: UUID(), cardID: UUID(), dueAt: now, updatedAt: now)
        let previews = try FSRSReviewScheduler().previews(for: state, at: now)
        let due = Dictionary(uniqueKeysWithValues: previews.map { ($0.rating, $0.dueAt) })

        #expect(previews.count == 4)
        #expect(try #require(due[.again]) < #require(due[.hard]))
        #expect(try #require(due[.hard]) < #require(due[.good]))
        #expect(try #require(due[.good]) < #require(due[.easy]))
    }

    @Test("A rating updates state and appends an immutable review log")
    func recordsReview() async throws {
        let context = try Context()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let card = try await context.cards.create(input("calibrate"), at: now)

        let first = try await context.reviews.recordReview(
            cardID: card.id,
            rating: .good,
            mode: .termToMeaning,
            at: now
        )
        let stateAfterFirst = try #require(await context.reviews.fetchState(cardID: card.id))
        let primarySense = try #require(await context.senses.fetchSenses(cardID: card.id).first)
        let primarySenseState = try #require(await context.senseReviews.fetchState(senseID: primarySense.id))

        #expect(first.previousState.reps == 0)
        #expect(first.newState == stateAfterFirst)
        #expect(stateAfterFirst.reps == 1)
        #expect(stateAfterFirst.schedulerVersion == "fsrs-6")
        #expect(primarySenseState == stateAfterFirst.scoped(to: primarySense.id))

        _ = try await context.reviews.recordReview(
            cardID: card.id,
            rating: .hard,
            mode: .meaningToTerm,
            at: stateAfterFirst.dueAt
        )
        let logs = try await context.reviews.fetchReviewLogs(since: nil)

        #expect(logs.count == 2)
        #expect(logs[0].reviewMode == .meaningToTerm)
        #expect(logs[1].id == first.id)
        #expect(logs[1].previousState.reps == 0)
        let senseLogs = try await context.senseReviews.fetchReviewLogs(senseID: primarySense.id, since: nil)
        #expect(senseLogs.count == 2)
        #expect(senseLogs[1].id == first.id)
        #expect(senseLogs.allSatisfy { $0.senseID == primarySense.id })
    }

    @Test("Queue prioritizes due reviews and applies the new-card limit")
    func buildsQueue() async throws {
        let context = try Context()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reviewed = try await context.cards.create(input("reviewed"), at: now)
        _ = try await context.cards.create(input("new one"), at: now.addingTimeInterval(1))
        _ = try await context.cards.create(input("new two"), at: now.addingTimeInterval(2))

        let firstLog = try await context.reviews.recordReview(
            cardID: reviewed.id,
            rating: .good,
            mode: .termToMeaning,
            at: now
        )
        let queue = try await context.reviews.fetchQueue(
            at: firstLog.newState.dueAt,
            newLimit: 1
        )

        #expect(queue.count == 2)
        #expect(queue.first?.card.id == reviewed.id)
        #expect(queue.last?.state.reps == 0)
    }

    @Test("Sense queue schedules every meaning independently")
    func buildsSenseQueue() async throws {
        let context = try Context()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let card = try await context.cards.create(input("scale"), at: now)
        let primary = try #require(await context.senses.fetchSenses(cardID: card.id).first)
        let secondary = try await context.senses.create(
            cardID: card.id,
            input: NewVocabularySense(
                translationZH: "鳞片",
                definitionEN: "one of the small plates covering a fish",
                exampleSentence: "A silver scale reflected the light."
            ),
            at: now.addingTimeInterval(1)
        )
        let primaryReview = try await context.senseReviews.recordReview(
            senseID: primary.id,
            rating: .good,
            mode: .termToMeaning,
            at: now
        )

        let queue = try await context.senseReviews.fetchQueue(
            at: primaryReview.newState.dueAt,
            newLimit: 1
        )

        #expect(queue.count == 2)
        #expect(queue.first?.sense.id == primary.id)
        #expect(queue.first?.state.reps == 1)
        #expect(queue.last?.sense.id == secondary.id)
        #expect(queue.last?.state.reps == 0)
        #expect(queue.allSatisfy { $0.card.id == card.id })
    }

    @Test("Adaptive prompt type is preserved in the review log")
    func persistsAdaptivePromptType() async throws {
        let context = try Context()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let card = try await context.cards.create(input("auditory"), at: now)
        let primary = try #require(await context.senses.fetchSenses(cardID: card.id).first)

        _ = try await context.senseReviews.recordReview(
            senseID: primary.id,
            rating: .good,
            mode: .listening,
            at: now
        )
        let logs = try await context.senseReviews.fetchReviewLogs(
            senseID: primary.id,
            since: nil
        )

        #expect(logs.count == 1)
        #expect(logs.first?.reviewMode == .listening)
    }

    private func input(_ term: String) -> NewVocabularyCard {
        NewVocabularyCard(
            term: term,
            languageCode: .english,
            translationZH: "测试",
            definitionEN: "a test definition",
            exampleSentence: "This is a test sentence."
        )
    }

    private struct Context {
        let cards: GRDBVocabularyRepository
        let reviews: GRDBReviewStateRepository
        let senses: GRDBVocabularySenseRepository
        let senseReviews: GRDBSenseReviewRepository

        init() throws {
            let database = try AppDatabase.inMemory()
            cards = GRDBVocabularyRepository(database: database)
            reviews = GRDBReviewStateRepository(database: database)
            senses = GRDBVocabularySenseRepository(database: database)
            senseReviews = GRDBSenseReviewRepository(database: database)
        }
    }
}
