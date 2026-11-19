import Foundation
import GRDB
import VocabularyCore

struct SenseReviewLogRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "sense_review_logs"

    var id: String
    var cardID: String
    var senseID: String
    var reviewedAtMS: Int64
    var rating: String
    var reviewMode: String
    var previousStateJSON: String
    var newStateJSON: String
    var scheduledIntervalDays: Double
    var schedulerVersion: String

    enum Columns: String, ColumnExpression {
        case senseID = "sense_id"
        case reviewedAtMS = "reviewed_at_ms"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case cardID = "card_id"
        case senseID = "sense_id"
        case reviewedAtMS = "reviewed_at_ms"
        case rating
        case reviewMode = "review_mode"
        case previousStateJSON = "previous_state_json"
        case newStateJSON = "new_state_json"
        case scheduledIntervalDays = "scheduled_interval_days"
        case schedulerVersion = "scheduler_version"
    }

    init(log: ReviewLogEntry, senseID: UUID) throws {
        let encoder = JSONEncoder()
        id = log.id.uuidString.lowercased()
        cardID = log.cardID.uuidString.lowercased()
        self.senseID = senseID.uuidString.lowercased()
        reviewedAtMS = DateStorage.milliseconds(log.reviewedAt)
        rating = log.rating.rawValue
        reviewMode = log.reviewMode.rawValue
        previousStateJSON = String(decoding: try encoder.encode(log.previousState.scoped(to: senseID)), as: UTF8.self)
        newStateJSON = String(decoding: try encoder.encode(log.newState.scoped(to: senseID)), as: UTF8.self)
        scheduledIntervalDays = log.scheduledIntervalDays
        schedulerVersion = log.schedulerVersion
    }

    var domainModel: ReviewLogEntry? {
        let decoder = JSONDecoder()
        guard let id = UUID(uuidString: id),
              let cardID = UUID(uuidString: cardID),
              let senseID = UUID(uuidString: senseID),
              let rating = ReviewRating(rawValue: rating),
              let reviewMode = ReviewMode(rawValue: reviewMode),
              let previousData = previousStateJSON.data(using: .utf8),
              let newData = newStateJSON.data(using: .utf8),
              let previousState = try? decoder.decode(ReviewState.self, from: previousData),
              let newState = try? decoder.decode(ReviewState.self, from: newData) else { return nil }
        return ReviewLogEntry(
            id: id,
            cardID: cardID,
            senseID: senseID,
            reviewedAt: DateStorage.date(reviewedAtMS),
            rating: rating,
            reviewMode: reviewMode,
            previousState: previousState.scoped(to: senseID),
            newState: newState.scoped(to: senseID),
            scheduledIntervalDays: scheduledIntervalDays,
            schedulerVersion: schedulerVersion
        )
    }
}
