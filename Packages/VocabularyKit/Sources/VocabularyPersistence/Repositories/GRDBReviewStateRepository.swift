import Foundation
import GRDB
import VocabularyCore

public final class GRDBReviewStateRepository: ReviewStateRepository, ReviewSessionRepository, @unchecked Sendable {
    private let database: AppDatabase
    private let scheduler: FSRSReviewScheduler

    public init(database: AppDatabase, scheduler: FSRSReviewScheduler = FSRSReviewScheduler()) {
        self.database = database
        self.scheduler = scheduler
    }

    public func fetchState(cardID: UUID) async throws -> ReviewState? {
        try await database.queue.read { database in
            try ReviewStateRecord
                .filter(ReviewStateRecord.Columns.cardID == cardID.uuidString.lowercased())
                .fetchOne(database)?
                .domainModel
        }
    }

    public func fetchAll() async throws -> [ReviewState] {
        try await database.queue.read { database in
            try ReviewStateRecord
                .fetchAll(database)
                .compactMap(\.domainModel)
        }
    }

    public func fetchQueue(at date: Date, newLimit: Int) async throws -> [ReviewQueueItem] {
        try await database.queue.read { database in
            let cards = try VocabularyCardRecord.fetchAll(database).compactMap(\.domainModel)
            let states = try ReviewStateRecord.fetchAll(database).compactMap(\.domainModel)
            let statesByCardID = Dictionary(uniqueKeysWithValues: states.map { ($0.cardID, $0) })
            let items = cards.compactMap { card -> ReviewQueueItem? in
                guard let state = statesByCardID[card.id] else { return nil }
                return ReviewQueueItem(card: card, state: state)
            }
            let due = items
                .filter { $0.state.reps > 0 && $0.state.dueAt <= date }
                .sorted { $0.state.dueAt < $1.state.dueAt }
            let newCards = items
                .filter { $0.state.reps == 0 || $0.state.fsrsState == .new }
                .sorted { $0.card.createdAt < $1.card.createdAt }
                .prefix(max(0, newLimit))
            return due + newCards
        }
    }

    public func previews(cardID: UUID, at date: Date) async throws -> [ReviewRatingPreview] {
        let state = try await fetchState(cardID: cardID)
        guard let state else {
            throw ReviewSessionRepositoryError.reviewStateNotFound(cardID)
        }
        return try scheduler.previews(for: state, at: date)
    }

    public func recordReview(
        cardID: UUID,
        rating: ReviewRating,
        mode: ReviewMode,
        at date: Date
    ) async throws -> ReviewLogEntry {
        try await database.queue.write { database in
            guard let previousState = try ReviewStateRecord
                .filter(ReviewStateRecord.Columns.cardID == cardID.uuidString.lowercased())
                .fetchOne(database)?
                .domainModel else {
                throw ReviewSessionRepositoryError.reviewStateNotFound(cardID)
            }
            let newState = try scheduler.schedule(previousState, rating: rating, at: date)
            let log = ReviewLogEntry(
                id: UUID(),
                cardID: cardID,
                reviewedAt: date,
                rating: rating,
                reviewMode: mode,
                previousState: previousState,
                newState: newState,
                scheduledIntervalDays: newState.scheduledDays,
                schedulerVersion: FSRSReviewScheduler.version
            )
            try ReviewStateRecord(state: newState).update(database)
            try ReviewLogRecord(log: log).insert(database)
            if let primarySense = try VocabularySenseRecord
                .filter(
                    VocabularySenseRecord.Columns.cardID == cardID.uuidString.lowercased()
                        && VocabularySenseRecord.Columns.isPrimary == true
                )
                .fetchOne(database),
               let senseID = UUID(uuidString: primarySense.id) {
                let scopedState = newState.scoped(to: senseID)
                if try SenseReviewStateRecord
                    .filter(SenseReviewStateRecord.Columns.senseID == primarySense.id)
                    .fetchCount(database) > 0 {
                    try SenseReviewStateRecord(state: scopedState, senseID: senseID).update(database)
                } else {
                    try SenseReviewStateRecord(state: scopedState, senseID: senseID).insert(database)
                }
                try SenseReviewLogRecord(log: log, senseID: senseID).insert(database)
            }
            return log
        }
    }

    public func fetchReviewLogs(since date: Date? = nil) async throws -> [ReviewLogEntry] {
        try await database.queue.read { database in
            var request = ReviewLogRecord.order(ReviewLogRecord.Columns.reviewedAtMS.desc)
            if let date {
                request = request.filter(
                    ReviewLogRecord.Columns.reviewedAtMS >= DateStorage.milliseconds(date)
                )
            }
            return try request.fetchAll(database).compactMap(\.domainModel)
        }
    }
}
