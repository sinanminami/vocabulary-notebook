import Foundation
import GRDB
import VocabularyCore

struct VocabularySenseRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "vocabulary_senses"

    var id: String
    var cardID: String
    var sortOrder: Int
    var isPrimary: Bool
    var translationZH: String
    var definitionEN: String
    var exampleSentence: String
    var memoryInsightJSON: String?
    var memoryInsightFeedback: String?
    var createdAtMS: Int64
    var updatedAtMS: Int64

    enum Columns: String, ColumnExpression {
        case id
        case cardID = "card_id"
        case sortOrder = "sort_order"
        case isPrimary = "is_primary"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case cardID = "card_id"
        case sortOrder = "sort_order"
        case isPrimary = "is_primary"
        case translationZH = "translation_zh"
        case definitionEN = "definition_en"
        case exampleSentence = "example_sentence"
        case memoryInsightJSON = "memory_insight_json"
        case memoryInsightFeedback = "memory_insight_feedback"
        case createdAtMS = "created_at_ms"
        case updatedAtMS = "updated_at_ms"
    }

    init(sense: VocabularySense) {
        id = sense.id.uuidString.lowercased()
        cardID = sense.cardID.uuidString.lowercased()
        sortOrder = sense.sortOrder
        isPrimary = sense.isPrimary
        translationZH = sense.translationZH
        definitionEN = sense.definitionEN
        exampleSentence = sense.exampleSentence
        memoryInsightJSON = sense.memoryInsight.flatMap(Self.encodeMemoryInsight)
        memoryInsightFeedback = sense.memoryInsightFeedback?.rawValue
        createdAtMS = DateStorage.milliseconds(sense.createdAt)
        updatedAtMS = DateStorage.milliseconds(sense.updatedAt)
    }

    var domainModel: VocabularySense? {
        guard let id = UUID(uuidString: id),
              let cardID = UUID(uuidString: cardID) else { return nil }
        return VocabularySense(
            id: id,
            cardID: cardID,
            sortOrder: sortOrder,
            isPrimary: isPrimary,
            translationZH: translationZH,
            definitionEN: definitionEN,
            exampleSentence: exampleSentence,
            memoryInsight: memoryInsightJSON.flatMap(Self.decodeMemoryInsight),
            memoryInsightFeedback: memoryInsightFeedback.flatMap(MemoryInsightFeedback.init(rawValue:)),
            createdAt: DateStorage.date(createdAtMS),
            updatedAt: DateStorage.date(updatedAtMS)
        )
    }

    private static func encodeMemoryInsight(_ insight: MemoryInsight) -> String? {
        guard let data = try? JSONEncoder().encode(insight) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decodeMemoryInsight(_ json: String) -> MemoryInsight? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MemoryInsight.self, from: data)
    }
}
