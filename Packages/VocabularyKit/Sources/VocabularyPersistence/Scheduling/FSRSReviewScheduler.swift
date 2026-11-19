import Foundation
import FSRS
import VocabularyCore

public struct FSRSReviewScheduler: Sendable {
    public static let version = "fsrs-6"

    public init() {}

    public func previews(
        for state: ReviewState,
        at date: Date
    ) throws -> [ReviewRatingPreview] {
        try ReviewRating.allCases.map { rating in
            let next = try schedule(state, rating: rating, at: date)
            return ReviewRatingPreview(
                rating: rating,
                dueAt: next.dueAt,
                scheduledDays: next.scheduledDays
            )
        }
    }

    public func schedule(
        _ state: ReviewState,
        rating: ReviewRating,
        at date: Date
    ) throws -> ReviewState {
        let scheduler = FSRS(parameters: .init(w: FSRSDefaults.defaultWv6))
        let result = try scheduler.next(
            card: makeCard(from: state),
            now: date,
            grade: makeRating(from: rating)
        )
        let card = result.card
        return ReviewState(
            id: state.id,
            cardID: state.cardID,
            senseID: state.senseID,
            dueAt: card.due,
            stability: card.stability,
            difficulty: card.difficulty,
            elapsedDays: card.elapsedDays,
            scheduledDays: card.scheduledDays,
            learningStep: card.learningSteps,
            reps: card.reps,
            lapses: card.lapses,
            fsrsState: makeState(from: card.state),
            lastReviewedAt: card.lastReview,
            schedulerVersion: Self.version,
            updatedAt: date
        )
    }

    private func makeCard(from state: ReviewState) -> Card {
        Card(
            due: state.dueAt,
            stability: state.stability,
            difficulty: state.difficulty,
            elapsedDays: state.elapsedDays,
            scheduledDays: state.scheduledDays,
            learningSteps: state.learningStep,
            reps: state.reps,
            lapses: state.lapses,
            state: makeState(from: state.fsrsState),
            lastReview: state.lastReviewedAt
        )
    }

    private func makeRating(from rating: ReviewRating) -> Rating {
        switch rating {
        case .again: .again
        case .hard: .hard
        case .good: .good
        case .easy: .easy
        }
    }

    private func makeState(from state: FSRSCardState) -> CardState {
        switch state {
        case .new: .new
        case .learning: .learning
        case .review: .review
        case .relearning: .relearning
        }
    }

    private func makeState(from state: CardState) -> FSRSCardState {
        switch state {
        case .new: .new
        case .learning: .learning
        case .review: .review
        case .relearning: .relearning
        }
    }
}
