import Foundation
import GRDB
import VocabularyCore

struct VocabularyEncounterRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "vocabulary_encounters"

    var id: String
    var cardID: String
    var senseID: String
    var context: String?
    var sourceApplication: String?
    var encounteredAtMS: Int64

    enum Columns: String, ColumnExpression {
        case id
        case cardID = "card_id"
        case senseID = "sense_id"
        case encounteredAtMS = "encountered_at_ms"
    }
    enum CodingKeys: String, CodingKey {
        case id
        case cardID = "card_id"
        case senseID = "sense_id"
        case context
        case sourceApplication = "source_application"
        case encounteredAtMS = "encountered_at_ms"
    }

    init(_ encounter: VocabularyEncounter) {
        id = encounter.id.uuidString.lowercased()
        cardID = encounter.cardID.uuidString.lowercased()
        senseID = encounter.senseID.uuidString.lowercased()
        context = encounter.context
        sourceApplication = encounter.sourceApplication
        encounteredAtMS = DateStorage.milliseconds(encounter.encounteredAt)
    }

    var domainModel: VocabularyEncounter? {
        guard let id = UUID(uuidString: id),
              let cardID = UUID(uuidString: cardID),
              let senseID = UUID(uuidString: senseID) else { return nil }
        return VocabularyEncounter(
            id: id,
            cardID: cardID,
            senseID: senseID,
            context: context,
            sourceApplication: sourceApplication,
            encounteredAt: DateStorage.date(encounteredAtMS)
        )
    }
}
