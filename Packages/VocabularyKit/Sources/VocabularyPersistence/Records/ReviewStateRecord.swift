import Foundation
import GRDB
import VocabularyCore

struct ReviewStateRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "review_states"

    var id: String
    var cardID: String
    var dueAtMS: Int64
    var stability: Double
    var difficulty: Double
    var elapsedDays: Double
    var scheduledDays: Double
    var learningStep: Int
    var reps: Int
    var lapses: Int
    var fsrsState: String
    var lastReviewedAtMS: Int64?
    var schedulerVersion: String
    var updatedAtMS: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case cardID = "card_id"
        case dueAtMS = "due_at_ms"
        case stability
        case difficulty
        case elapsedDays = "elapsed_days"
        case scheduledDays = "scheduled_days"
        case learningStep = "learning_step"
        case reps
        case lapses
        case fsrsState = "fsrs_state"
        case lastReviewedAtMS = "last_reviewed_at_ms"
        case schedulerVersion = "scheduler_version"
        case updatedAtMS = "updated_at_ms"
    }

    enum Columns: String, ColumnExpression {
        case id
        case cardID = "card_id"
        case dueAtMS = "due_at_ms"
        case fsrsState = "fsrs_state"
    }

    init(state: ReviewState) {
        id = state.id.uuidString.lowercased()
        cardID = state.cardID.uuidString.lowercased()
        dueAtMS = DateStorage.milliseconds(state.dueAt)
        stability = state.stability
        difficulty = state.difficulty
        elapsedDays = state.elapsedDays
        scheduledDays = state.scheduledDays
        learningStep = state.learningStep
        reps = state.reps
        lapses = state.lapses
        fsrsState = state.fsrsState.rawValue
        lastReviewedAtMS = state.lastReviewedAt.map(DateStorage.milliseconds)
        schedulerVersion = state.schedulerVersion
        updatedAtMS = DateStorage.milliseconds(state.updatedAt)
    }

    var domainModel: ReviewState? {
        guard let id = UUID(uuidString: id),
              let cardID = UUID(uuidString: cardID),
              let fsrsState = FSRSCardState(rawValue: fsrsState) else {
            return nil
        }
        return ReviewState(
            id: id,
            cardID: cardID,
            dueAt: DateStorage.date(dueAtMS),
            stability: stability,
            difficulty: difficulty,
            elapsedDays: elapsedDays,
            scheduledDays: scheduledDays,
            learningStep: learningStep,
            reps: reps,
            lapses: lapses,
            fsrsState: fsrsState,
            lastReviewedAt: lastReviewedAtMS.map(DateStorage.date),
            schedulerVersion: schedulerVersion,
            updatedAt: DateStorage.date(updatedAtMS)
        )
    }
}
