import Foundation
import GRDB
import VocabularyCore

struct TagRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "tags"

    var id: String
    var name: String
    var normalizedName: String
    var isSystem: Bool
    var sortOrder: Int
    var createdAtMS: Int64
    var updatedAtMS: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case normalizedName = "normalized_name"
        case isSystem = "is_system"
        case sortOrder = "sort_order"
        case createdAtMS = "created_at_ms"
        case updatedAtMS = "updated_at_ms"
    }

    enum Columns: String, ColumnExpression {
        case id
        case name
        case normalizedName = "normalized_name"
        case isSystem = "is_system"
        case sortOrder = "sort_order"
    }

    init(
        id: String,
        name: String,
        normalizedName: String,
        isSystem: Bool,
        sortOrder: Int,
        createdAtMS: Int64,
        updatedAtMS: Int64
    ) {
        self.id = id
        self.name = name
        self.normalizedName = normalizedName
        self.isSystem = isSystem
        self.sortOrder = sortOrder
        self.createdAtMS = createdAtMS
        self.updatedAtMS = updatedAtMS
    }

    var domainModel: Tag? {
        guard let id = UUID(uuidString: id) else { return nil }
        return Tag(
            id: id,
            name: name,
            normalizedName: normalizedName,
            isSystem: isSystem,
            sortOrder: sortOrder,
            createdAt: DateStorage.date(createdAtMS),
            updatedAt: DateStorage.date(updatedAtMS)
        )
    }

    init(tag: Tag) {
        id = tag.id.uuidString.lowercased()
        name = tag.name
        normalizedName = tag.normalizedName
        isSystem = tag.isSystem
        sortOrder = tag.sortOrder
        createdAtMS = DateStorage.milliseconds(tag.createdAt)
        updatedAtMS = DateStorage.milliseconds(tag.updatedAt)
    }
}

struct VocabularyCardTagRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "vocabulary_card_tags"

    var cardID: String
    var tagID: String
    var createdAtMS: Int64

    enum CodingKeys: String, CodingKey {
        case cardID = "card_id"
        case tagID = "tag_id"
        case createdAtMS = "created_at_ms"
    }
}
