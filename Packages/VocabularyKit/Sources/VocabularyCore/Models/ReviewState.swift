import Foundation

public enum FSRSCardState: String, Codable, CaseIterable, Sendable {
    case new
    case learning
    case review
    case relearning
}

public enum ReviewRating: String, Codable, CaseIterable, Sendable {
    case again
    case hard
    case good
    case easy
}

public enum ReviewMode: String, Codable, CaseIterable, Sendable {
    case termToMeaning
    case meaningToTerm
    case listening
    case contextCloze
    case spelling
    case contrast
}

public enum ReviewSessionMode: String, Codable, CaseIterable, Sendable {
    case adaptive
    case termToMeaning
    case meaningToTerm
}

public enum AdaptiveReviewPrompt: String, Codable, CaseIterable, Sendable {
    case recognition
    case listening
    case contextCloze
    case spelling
    case contrast

    public var reviewMode: ReviewMode {
        switch self {
        case .recognition: .termToMeaning
        case .listening: .listening
        case .contextCloze: .contextCloze
        case .spelling: .spelling
        case .contrast: .contrast
        }
    }
}

public enum MasteryLevel: String, Codable, CaseIterable, Sendable {
    case new
    case learning
    case familiar
    case mastered
}

public struct ReviewState: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let cardID: UUID
    public let senseID: UUID?
    public var dueAt: Date
    public var stability: Double
    public var difficulty: Double
    public var elapsedDays: Double
    public var scheduledDays: Double
    public var learningStep: Int
    public var reps: Int
    public var lapses: Int
    public var fsrsState: FSRSCardState
    public var lastReviewedAt: Date?
    public var schedulerVersion: String
    public var updatedAt: Date

    public init(
        id: UUID,
        cardID: UUID,
        senseID: UUID? = nil,
        dueAt: Date,
        stability: Double = 0,
        difficulty: Double = 0,
        elapsedDays: Double = 0,
        scheduledDays: Double = 0,
        learningStep: Int = 0,
        reps: Int = 0,
        lapses: Int = 0,
        fsrsState: FSRSCardState = .new,
        lastReviewedAt: Date? = nil,
        schedulerVersion: String = "fsrs-6",
        updatedAt: Date
    ) {
        self.id = id
        self.cardID = cardID
        self.senseID = senseID
        self.dueAt = dueAt
        self.stability = stability
        self.difficulty = difficulty
        self.elapsedDays = elapsedDays
        self.scheduledDays = scheduledDays
        self.learningStep = learningStep
        self.reps = reps
        self.lapses = lapses
        self.fsrsState = fsrsState
        self.lastReviewedAt = lastReviewedAt
        self.schedulerVersion = schedulerVersion
        self.updatedAt = updatedAt
    }

    public func scoped(to senseID: UUID) -> ReviewState {
        ReviewState(
            id: id,
            cardID: cardID,
            senseID: senseID,
            dueAt: dueAt,
            stability: stability,
            difficulty: difficulty,
            elapsedDays: elapsedDays,
            scheduledDays: scheduledDays,
            learningStep: learningStep,
            reps: reps,
            lapses: lapses,
            fsrsState: fsrsState,
            lastReviewedAt: lastReviewedAt,
            schedulerVersion: schedulerVersion,
            updatedAt: updatedAt
        )
    }
}

public struct ReviewQueueItem: Identifiable, Hashable, Sendable {
    public var id: UUID { card.id }
    public let card: VocabularyCard
    public let state: ReviewState

    public init(card: VocabularyCard, state: ReviewState) {
        self.card = card
        self.state = state
    }
}

public struct SenseReviewQueueItem: Identifiable, Hashable, Sendable {
    public var id: UUID { sense.id }
    public let card: VocabularyCard
    public let sense: VocabularySense
    public let state: ReviewState

    public init(card: VocabularyCard, sense: VocabularySense, state: ReviewState) {
        self.card = card
        self.sense = sense
        self.state = state
    }
}

public struct ReviewRatingPreview: Identifiable, Hashable, Sendable {
    public var id: ReviewRating { rating }
    public let rating: ReviewRating
    public let dueAt: Date
    public let scheduledDays: Double

    public init(rating: ReviewRating, dueAt: Date, scheduledDays: Double) {
        self.rating = rating
        self.dueAt = dueAt
        self.scheduledDays = scheduledDays
    }
}

public struct ReviewLogEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let cardID: UUID
    public let senseID: UUID?
    public let reviewedAt: Date
    public let rating: ReviewRating
    public let reviewMode: ReviewMode
    public let previousState: ReviewState
    public let newState: ReviewState
    public let scheduledIntervalDays: Double
    public let schedulerVersion: String

    public init(
        id: UUID,
        cardID: UUID,
        senseID: UUID? = nil,
        reviewedAt: Date,
        rating: ReviewRating,
        reviewMode: ReviewMode,
        previousState: ReviewState,
        newState: ReviewState,
        scheduledIntervalDays: Double,
        schedulerVersion: String
    ) {
        self.id = id
        self.cardID = cardID
        self.senseID = senseID
        self.reviewedAt = reviewedAt
        self.rating = rating
        self.reviewMode = reviewMode
        self.previousState = previousState
        self.newState = newState
        self.scheduledIntervalDays = scheduledIntervalDays
        self.schedulerVersion = schedulerVersion
    }
}
