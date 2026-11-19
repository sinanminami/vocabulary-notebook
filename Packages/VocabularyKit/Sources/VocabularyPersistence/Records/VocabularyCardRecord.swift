import Foundation
import GRDB
import VocabularyCore

struct VocabularyCardRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "vocabulary_cards"

    var id: String
    var term: String
    var normalizedTerm: String
    var languageCode: String
    var pronunciationIPA: String
    var translationZH: String
    var definitionEN: String
    var exampleSentence: String
    var memoryInsightJSON: String?
    var memoryInsightFeedback: String?
    var encounterCount: Int
    var createdAtMS: Int64
    var updatedAtMS: Int64
    var lastEncounteredAtMS: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case term
        case normalizedTerm = "normalized_term"
        case languageCode = "language_code"
        case pronunciationIPA = "pronunciation_ipa"
        case translationZH = "translation_zh"
        case definitionEN = "definition_en"
        case exampleSentence = "example_sentence"
        case memoryInsightJSON = "memory_insight_json"
        case memoryInsightFeedback = "memory_insight_feedback"
        case encounterCount = "encounter_count"
        case createdAtMS = "created_at_ms"
        case updatedAtMS = "updated_at_ms"
        case lastEncounteredAtMS = "last_encountered_at_ms"
    }

    enum Columns: String, ColumnExpression {
        case id
        case term
        case normalizedTerm = "normalized_term"
        case languageCode = "language_code"
        case encounterCount = "encounter_count"
        case createdAtMS = "created_at_ms"
        case updatedAtMS = "updated_at_ms"
        case lastEncounteredAtMS = "last_encountered_at_ms"
    }

    init(card: VocabularyCard) {
        id = card.id.uuidString.lowercased()
        term = card.term
        normalizedTerm = card.normalizedTerm
        languageCode = card.languageCode.rawValue
        pronunciationIPA = card.pronunciationIPA
        translationZH = card.translationZH
        definitionEN = card.definitionEN
        exampleSentence = card.exampleSentence
        memoryInsightJSON = card.memoryInsight.flatMap(Self.encodeMemoryInsight)
        memoryInsightFeedback = card.memoryInsightFeedback?.rawValue
        encounterCount = card.encounterCount
        createdAtMS = DateStorage.milliseconds(card.createdAt)
        updatedAtMS = DateStorage.milliseconds(card.updatedAt)
        lastEncounteredAtMS = DateStorage.milliseconds(card.lastEncounteredAt)
    }

    var domainModel: VocabularyCard? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return VocabularyCard(
            id: uuid,
            term: term,
            normalizedTerm: normalizedTerm,
            languageCode: LanguageCode(rawValue: languageCode),
            pronunciationIPA: pronunciationIPA,
            translationZH: translationZH,
            definitionEN: definitionEN,
            exampleSentence: exampleSentence,
            memoryInsight: memoryInsightJSON.flatMap(Self.decodeMemoryInsight),
            memoryInsightFeedback: memoryInsightFeedback.flatMap(MemoryInsightFeedback.init(rawValue:)),
            encounterCount: encounterCount,
            createdAt: DateStorage.date(createdAtMS),
            updatedAt: DateStorage.date(updatedAtMS),
            lastEncounteredAt: DateStorage.date(lastEncounteredAtMS)
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
