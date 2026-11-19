import Foundation
import GRDB
import VocabularyCore

public final class GRDBTagRepository: TagRepository, @unchecked Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func fetchAll() async throws -> [Tag] {
        try await database.queue.read { database in
            try TagRecord
                .order(TagRecord.Columns.sortOrder, TagRecord.Columns.name)
                .fetchAll(database)
                .compactMap(\.domainModel)
        }
    }

    public func fetchTagIDsByCardID() async throws -> [UUID: Set<UUID>] {
        try await database.queue.read { database in
            try VocabularyCardTagRecord.fetchAll(database).reduce(into: [:]) { result, record in
                guard let cardID = UUID(uuidString: record.cardID),
                      let tagID = UUID(uuidString: record.tagID) else {
                    return
                }
                result[cardID, default: []].insert(tagID)
            }
        }
    }

    public func create(name: String, at date: Date) async throws -> Tag {
        let values = try Self.normalizedName(name)
        return try await database.queue.write { database in
            guard try TagRecord
                .filter(TagRecord.Columns.normalizedName == values.normalized)
                .fetchCount(database) == 0 else {
                throw TagRepositoryError.duplicateName
            }
            let nextSortOrder = (try Int.fetchOne(
                database,
                sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM tags"
            )) ?? 0
            let tag = Tag(
                id: UUID(),
                name: values.display,
                normalizedName: values.normalized,
                isSystem: false,
                sortOrder: nextSortOrder,
                createdAt: date,
                updatedAt: date
            )
            try TagRecord(tag: tag).insert(database)
            return tag
        }
    }

    public func rename(id: UUID, name: String, at date: Date) async throws -> Tag {
        let values = try Self.normalizedName(name)
        return try await database.queue.write { database in
            guard var record = try TagRecord
                .filter(TagRecord.Columns.id == id.uuidString.lowercased())
                .fetchOne(database) else {
                throw TagRepositoryError.tagNotFound(id)
            }
            guard !record.isSystem else { throw TagRepositoryError.systemTagProtected }
            guard try TagRecord
                .filter(
                    TagRecord.Columns.normalizedName == values.normalized
                        && TagRecord.Columns.id != id.uuidString.lowercased()
                )
                .fetchCount(database) == 0 else {
                throw TagRepositoryError.duplicateName
            }
            record.name = values.display
            record.normalizedName = values.normalized
            record.updatedAtMS = DateStorage.milliseconds(date)
            try record.update(database)
            guard let tag = record.domainModel else {
                throw TagRepositoryError.tagNotFound(id)
            }
            return tag
        }
    }

    public func delete(id: UUID) async throws {
        try await database.queue.write { database in
            guard let record = try TagRecord
                .filter(TagRecord.Columns.id == id.uuidString.lowercased())
                .fetchOne(database) else {
                throw TagRepositoryError.tagNotFound(id)
            }
            guard !record.isSystem else { throw TagRepositoryError.systemTagProtected }
            _ = try record.delete(database)
        }
    }

    private static func normalizedName(_ name: String) throws -> (display: String, normalized: String) {
        let display = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !display.isEmpty, display.count <= 48 else {
            throw TagRepositoryError.invalidName
        }
        return (
            display,
            display.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
                .lowercased(with: Locale(identifier: "en_US_POSIX"))
        )
    }
}
