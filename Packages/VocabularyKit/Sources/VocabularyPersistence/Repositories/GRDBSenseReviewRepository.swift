import Foundation
import GRDB
import VocabularyCore

public final class GRDBSenseReviewRepository: SenseReviewRepository, @unchecked Sendable {
    private let database: AppDatabase
    private let scheduler: FSRSReviewScheduler

    public init(database: AppDatabase, scheduler: FSRSReviewScheduler = FSRSReviewScheduler()) {
        self.database = database
        self.scheduler = scheduler
    }

    public func fetchState(senseID: UUID) async throws -> ReviewState? {
        try await database.queue.read { database in
            try SenseReviewStateRecord
                .filter(SenseReviewStateRecord.Columns.senseID == senseID.uuidString.lowercased())
                .fetchOne(database)?
                .domainModel
        }
    }

    public func fetchAllStates() async throws -> [ReviewState] {
        try await database.queue.read { database in
            try SenseReviewStateRecord.fetchAll(database).compactMap(\.domainModel)
        }
    }

    public func fetchQueue(at date: Date, newLimit: Int) async throws -> [SenseReviewQueueItem] {
        try await database.queue.read { database in
            let cards = try VocabularyCardRecord.fetchAll(database).compactMap(\.domainModel)
            let senses = try VocabularySenseRecord.fetchAll(database).compactMap(\.domainModel)
            let states = try SenseReviewStateRecord.fetchAll(database).compactMap(\.domainModel)
            let cardsByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
            let statesBySenseID = Dictionary(
                uniqueKeysWithValues: states.compactMap { state in
                    state.senseID.map { ($0, state) }
                }
            )
            let items = senses.compactMap { sense -> SenseReviewQueueItem? in
                guard let card = cardsByID[sense.cardID],
                      let state = statesBySenseID[sense.id] else { return nil }
                return SenseReviewQueueItem(card: card, sense: sense, state: state)
            }
            let due = items
                .filter { $0.state.reps > 0 && $0.state.dueAt <= date }
                .sorted { $0.state.dueAt < $1.state.dueAt }
            let newSenses = items
                .filter { $0.state.reps == 0 || $0.state.fsrsState == .new }
                .sorted {
                    if $0.sense.createdAt != $1.sense.createdAt {
                        return $0.sense.createdAt < $1.sense.createdAt
                    }
                    return $0.sense.sortOrder < $1.sense.sortOrder
                }
                .prefix(max(0, newLimit))
            return due + newSenses
        }
    }

    public func previews(senseID: UUID, at date: Date) async throws -> [ReviewRatingPreview] {
        guard let state = try await fetchState(senseID: senseID) else {
            throw SenseReviewRepositoryError.reviewStateNotFound(senseID)
        }
        return try scheduler.previews(for: state, at: date)
    }

    public func recordReview(
        senseID: UUID,
        rating: ReviewRating,
        mode: ReviewMode,
        at date: Date
    ) async throws -> ReviewLogEntry {
        try await database.queue.write { database in
            guard let senseRecord = try VocabularySenseRecord
                .filter(VocabularySenseRecord.Columns.id == senseID.uuidString.lowercased())
                .fetchOne(database),
                  let sense = senseRecord.domainModel,
                  let previousState = try SenseReviewStateRecord
                    .filter(SenseReviewStateRecord.Columns.senseID == senseID.uuidString.lowercased())
                    .fetchOne(database)?
                    .domainModel else {
                throw SenseReviewRepositoryError.reviewStateNotFound(senseID)
            }
            let newState = try scheduler.schedule(previousState, rating: rating, at: date)
            let log = ReviewLogEntry(
                id: UUID(),
                cardID: sense.cardID,
                senseID: senseID,
                reviewedAt: date,
                rating: rating,
                reviewMode: mode,
                previousState: previousState,
                newState: newState,
                scheduledIntervalDays: newState.scheduledDays,
                schedulerVersion: FSRSReviewScheduler.version
            )
            try SenseReviewStateRecord(state: newState, senseID: senseID).update(database)
            try SenseReviewLogRecord(log: log, senseID: senseID).insert(database)

            // During the transition the visible app still reads card-level review
            // data. Keep only the primary sense mirrored in both directions.
            if sense.isPrimary {
                try ReviewStateRecord(state: newState).update(database)
                try ReviewLogRecord(log: log).insert(database)
            }
            return log
        }
    }

    public func fetchReviewLogs(
        senseID: UUID? = nil,
        since date: Date? = nil
    ) async throws -> [ReviewLogEntry] {
        try await database.queue.read { database in
            var request = SenseReviewLogRecord.order(SenseReviewLogRecord.Columns.reviewedAtMS.desc)
            if let senseID {
                request = request.filter(
                    SenseReviewLogRecord.Columns.senseID == senseID.uuidString.lowercased()
                )
            }
            if let date {
                request = request.filter(
                    SenseReviewLogRecord.Columns.reviewedAtMS >= DateStorage.milliseconds(date)
                )
            }
            return try request.fetchAll(database).compactMap(\.domainModel)
        }
    }
}
