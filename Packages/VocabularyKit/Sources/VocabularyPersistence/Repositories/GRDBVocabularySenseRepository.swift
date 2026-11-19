import Foundation
import GRDB
import VocabularyCore

public final class GRDBVocabularySenseRepository: VocabularySenseRepository, @unchecked Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func fetchSense(id: UUID) async throws -> VocabularySense? {
        try await database.queue.read { database in
            try VocabularySenseRecord
                .filter(VocabularySenseRecord.Columns.id == id.uuidString.lowercased())
                .fetchOne(database)?
                .domainModel
        }
    }

    public func fetchSenses(cardID: UUID) async throws -> [VocabularySense] {
        try await database.queue.read { database in
            try VocabularySenseRecord
                .filter(VocabularySenseRecord.Columns.cardID == cardID.uuidString.lowercased())
                .order(VocabularySenseRecord.Columns.sortOrder.asc)
                .fetchAll(database)
                .compactMap(\.domainModel)
        }
    }

    public func fetchAll() async throws -> [VocabularySense] {
        try await database.queue.read { database in
            try VocabularySenseRecord
                .order(
                    VocabularySenseRecord.Columns.cardID.asc,
                    VocabularySenseRecord.Columns.sortOrder.asc
                )
                .fetchAll(database)
                .compactMap(\.domainModel)
        }
    }

    public func create(
        cardID: UUID,
        input: NewVocabularySense,
        at date: Date
    ) async throws -> VocabularySense {
        let memoryInsight = try input.memoryInsight?.validated()
        return try await database.queue.write { database in
            let cardKey = cardID.uuidString.lowercased()
            guard try VocabularyCardRecord
                .filter(VocabularyCardRecord.Columns.id == cardKey)
                .fetchCount(database) > 0 else {
                throw VocabularySenseRepositoryError.cardNotFound(cardID)
            }

            let nextSortOrder = try Int.fetchOne(
                database,
                sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM vocabulary_senses WHERE card_id = ?",
                arguments: [cardKey]
            ) ?? 0
            let sense = VocabularySense(
                id: UUID(),
                cardID: cardID,
                sortOrder: nextSortOrder,
                isPrimary: false,
                translationZH: input.translationZH.trimmingCharacters(in: .whitespacesAndNewlines),
                definitionEN: input.definitionEN.trimmingCharacters(in: .whitespacesAndNewlines),
                exampleSentence: input.exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines),
                memoryInsight: memoryInsight,
                createdAt: date,
                updatedAt: date
            )
            try VocabularySenseRecord(sense: sense).insert(database)
            let state = ReviewState(
                id: UUID(),
                cardID: cardID,
                senseID: sense.id,
                dueAt: date,
                updatedAt: date
            )
            try SenseReviewStateRecord(state: state, senseID: sense.id).insert(database)
            return sense
        }
    }

    public func update(
        id: UUID,
        changes: VocabularySenseChanges,
        at date: Date
    ) async throws -> VocabularySense {
        let memoryInsight = try changes.memoryInsight?.validated()
        return try await database.queue.write { database in
            guard let record = try VocabularySenseRecord
                .filter(VocabularySenseRecord.Columns.id == id.uuidString.lowercased())
                .fetchOne(database),
                  var sense = record.domainModel else {
                throw VocabularySenseRepositoryError.senseNotFound(id)
            }
            sense.translationZH = changes.translationZH.trimmingCharacters(in: .whitespacesAndNewlines)
            sense.definitionEN = changes.definitionEN.trimmingCharacters(in: .whitespacesAndNewlines)
            sense.exampleSentence = changes.exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if sense.memoryInsight != memoryInsight {
                sense.memoryInsightFeedback = nil
            }
            sense.memoryInsight = memoryInsight
            sense.updatedAt = date
            try VocabularySenseRecord(sense: sense).update(database)
            if sense.isPrimary {
                try Self.mirrorPrimarySenseToCard(sense, in: database)
            }
            return sense
        }
    }

    public func setMemoryInsightFeedback(
        id: UUID,
        feedback: MemoryInsightFeedback?,
        at date: Date
    ) async throws -> VocabularySense {
        try await database.queue.write { database in
            guard let record = try VocabularySenseRecord
                .filter(VocabularySenseRecord.Columns.id == id.uuidString.lowercased())
                .fetchOne(database),
                  var sense = record.domainModel else {
                throw VocabularySenseRepositoryError.senseNotFound(id)
            }
            sense.memoryInsightFeedback = feedback
            sense.updatedAt = date
            try VocabularySenseRecord(sense: sense).update(database)
            if sense.isPrimary {
                try Self.mirrorPrimarySenseToCard(sense, in: database)
            }
            return sense
        }
    }

    public func delete(id: UUID) async throws {
        try await database.queue.write { database in
            guard let record = try VocabularySenseRecord
                .filter(VocabularySenseRecord.Columns.id == id.uuidString.lowercased())
                .fetchOne(database),
                  let sense = record.domainModel else {
                throw VocabularySenseRepositoryError.senseNotFound(id)
            }
            guard !sense.isPrimary else {
                throw VocabularySenseRepositoryError.primarySenseProtected(id)
            }
            try VocabularySenseRecord.deleteOne(database, key: id.uuidString.lowercased())
            try Self.refreshCardEncounterSummary(cardID: sense.cardID, in: database)
        }
    }

    private static func mirrorPrimarySenseToCard(
        _ sense: VocabularySense,
        in database: Database
    ) throws {
        guard let record = try VocabularyCardRecord
            .filter(VocabularyCardRecord.Columns.id == sense.cardID.uuidString.lowercased())
            .fetchOne(database),
              var card = record.domainModel else {
            throw VocabularySenseRepositoryError.cardNotFound(sense.cardID)
        }
        card.translationZH = sense.translationZH
        card.definitionEN = sense.definitionEN
        card.exampleSentence = sense.exampleSentence
        card.memoryInsight = sense.memoryInsight
        card.memoryInsightFeedback = sense.memoryInsightFeedback
        card.updatedAt = sense.updatedAt
        try VocabularyCardRecord(card: card).update(database)
    }

    private static func refreshCardEncounterSummary(
        cardID: UUID,
        in database: Database
    ) throws {
        let cardKey = cardID.uuidString.lowercased()
        guard let record = try VocabularyCardRecord
            .filter(VocabularyCardRecord.Columns.id == cardKey)
            .fetchOne(database),
              var card = record.domainModel else { return }
        let count = try VocabularyEncounterRecord
            .filter(VocabularyEncounterRecord.Columns.cardID == cardKey)
            .fetchCount(database)
        let latest = try Int64.fetchOne(
            database,
            sql: "SELECT MAX(encountered_at_ms) FROM vocabulary_encounters WHERE card_id = ?",
            arguments: [cardKey]
        )
        card.encounterCount = max(1, count)
        card.lastEncounteredAt = latest.map(DateStorage.date) ?? card.createdAt
        try VocabularyCardRecord(card: card).update(database)
    }
}
