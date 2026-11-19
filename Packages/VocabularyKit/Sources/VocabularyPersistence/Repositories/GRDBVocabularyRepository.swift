import Foundation
import GRDB
import VocabularyCore

public final class GRDBVocabularyRepository: VocabularyRepository, @unchecked Sendable {
    private let database: AppDatabase
    private let normalizer: TermNormalizer

    public init(database: AppDatabase, normalizer: TermNormalizer = TermNormalizer()) {
        self.database = database
        self.normalizer = normalizer
    }

    public func create(_ input: NewVocabularyCard, at date: Date) async throws -> VocabularyCard {
        let term = try normalizer.displayTerm(input.term)
        let normalizedTerm = try normalizer.normalize(term)
        let memoryInsight = try input.memoryInsight?.validated()
        let card = VocabularyCard(
            id: UUID(),
            term: term,
            normalizedTerm: normalizedTerm,
            languageCode: input.languageCode,
            pronunciationIPA: input.pronunciationIPA.trimmingCharacters(in: .whitespacesAndNewlines),
            translationZH: input.translationZH,
            definitionEN: input.definitionEN,
            exampleSentence: input.exampleSentence,
            memoryInsight: memoryInsight,
            encounterCount: 1,
            createdAt: date,
            updatedAt: date,
            lastEncounteredAt: date
        )

        return try await database.queue.write { database in
            if let duplicate = try Self.fetchDuplicate(
                in: database,
                normalizedTerm: normalizedTerm,
                languageCode: input.languageCode,
                excluding: nil
            ), let duplicateID = UUID(uuidString: duplicate.id) {
                throw VocabularyRepositoryError.duplicate(existingCardID: duplicateID)
            }

            try Self.validateTags(input.tagIDs, in: database)
            try VocabularyCardRecord(card: card).insert(database)
            let primarySense = VocabularySense(
                id: UUID(),
                cardID: card.id,
                sortOrder: 0,
                isPrimary: true,
                translationZH: card.translationZH,
                definitionEN: card.definitionEN,
                exampleSentence: card.exampleSentence,
                memoryInsight: card.memoryInsight,
                createdAt: date,
                updatedAt: date
            )
            try VocabularySenseRecord(sense: primarySense).insert(database)
            try VocabularyEncounterRecord(
                VocabularyEncounter(
                    id: UUID(),
                    cardID: card.id,
                    senseID: primarySense.id,
                    context: input.encounterContext,
                    sourceApplication: input.encounterSourceApplication,
                    encounteredAt: date
                )
            ).insert(database)

            let state = ReviewState(
                id: UUID(),
                cardID: card.id,
                dueAt: date,
                updatedAt: date
            )
            try ReviewStateRecord(state: state).insert(database)
            try SenseReviewStateRecord(state: state.scoped(to: primarySense.id), senseID: primarySense.id)
                .insert(database)
            try Self.replaceTagLinks(cardID: card.id, tagIDs: input.tagIDs, at: date, in: database)
            return card
        }
    }

    public func fetchCard(id: UUID) async throws -> VocabularyCard? {
        try await database.queue.read { database in
            try VocabularyCardRecord
                .filter(VocabularyCardRecord.Columns.id == id.uuidString.lowercased())
                .fetchOne(database)?
                .domainModel
        }
    }

    public func fetchAll() async throws -> [VocabularyCard] {
        try await database.queue.read { database in
            try VocabularyCardRecord
                .order(VocabularyCardRecord.Columns.createdAtMS.desc)
                .fetchAll(database)
                .compactMap(\.domainModel)
        }
    }

    public func fetchCards(normalizedTerm: String) async throws -> [VocabularyCard] {
        try await database.queue.read { database in
            try VocabularyCardRecord
                .filter(VocabularyCardRecord.Columns.normalizedTerm == normalizedTerm)
                .fetchAll(database)
                .compactMap(\.domainModel)
        }
    }

    public func update(
        id: UUID,
        changes: VocabularyCardChanges,
        at date: Date
    ) async throws -> VocabularyCard {
        let term = try normalizer.displayTerm(changes.term)
        let normalizedTerm = try normalizer.normalize(term)
        let memoryInsight = try changes.memoryInsight?.validated()

        return try await database.queue.write { database in
            guard let existingRecord = try VocabularyCardRecord
                .filter(VocabularyCardRecord.Columns.id == id.uuidString.lowercased())
                .fetchOne(database),
                  var card = existingRecord.domainModel else {
                throw VocabularyRepositoryError.cardNotFound(id)
            }
            if let duplicate = try Self.fetchDuplicate(
                in: database,
                normalizedTerm: normalizedTerm,
                languageCode: changes.languageCode,
                excluding: id
            ), let duplicateID = UUID(uuidString: duplicate.id) {
                throw VocabularyRepositoryError.duplicate(existingCardID: duplicateID)
            }

            try Self.validateTags(changes.tagIDs, in: database)
            card.term = term
            card.normalizedTerm = normalizedTerm
            card.languageCode = changes.languageCode
            card.pronunciationIPA = changes.pronunciationIPA
                .trimmingCharacters(in: .whitespacesAndNewlines)
            card.translationZH = changes.translationZH
            card.definitionEN = changes.definitionEN
            card.exampleSentence = changes.exampleSentence
            if card.memoryInsight != memoryInsight {
                card.memoryInsightFeedback = nil
            }
            card.memoryInsight = memoryInsight
            card.updatedAt = date

            try VocabularyCardRecord(card: card).update(database)
            try Self.mirrorCardContentToPrimarySense(card, in: database)
            try Self.replaceTagLinks(cardID: id, tagIDs: changes.tagIDs, at: date, in: database)
            return card
        }
    }

    public func setMemoryInsight(
        id: UUID,
        insight: MemoryInsight,
        at date: Date
    ) async throws -> VocabularyCard {
        let validatedInsight = try insight.validated()
        return try await database.queue.write { database in
            guard let existingRecord = try VocabularyCardRecord
                .filter(VocabularyCardRecord.Columns.id == id.uuidString.lowercased())
                .fetchOne(database),
                  var card = existingRecord.domainModel else {
                throw VocabularyRepositoryError.cardNotFound(id)
            }
            card.memoryInsight = validatedInsight
            card.memoryInsightFeedback = nil
            card.updatedAt = date
            try VocabularyCardRecord(card: card).update(database)
            try Self.mirrorCardContentToPrimarySense(card, in: database)
            return card
        }
    }

    public func setMemoryInsightFeedback(
        id: UUID,
        feedback: MemoryInsightFeedback?,
        at date: Date
    ) async throws -> VocabularyCard {
        try await database.queue.write { database in
            guard let existingRecord = try VocabularyCardRecord
                .filter(VocabularyCardRecord.Columns.id == id.uuidString.lowercased())
                .fetchOne(database),
                  var card = existingRecord.domainModel else {
                throw VocabularyRepositoryError.cardNotFound(id)
            }
            guard card.memoryInsight != nil else {
                throw VocabularyRepositoryError.cardNotFound(id)
            }
            card.memoryInsightFeedback = feedback
            card.updatedAt = date
            try VocabularyCardRecord(card: card).update(database)
            try Self.mirrorCardContentToPrimarySense(card, in: database)
            return card
        }
    }

    public func setPronunciationIPA(
        id: UUID,
        pronunciationIPA: String,
        at date: Date
    ) async throws -> VocabularyCard {
        let cleanIPA = pronunciationIPA.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanIPA.isEmpty, cleanIPA.count <= 120 else {
            throw VocabularyRepositoryError.invalidPronunciation
        }
        return try await database.queue.write { database in
            guard let existingRecord = try VocabularyCardRecord
                .filter(VocabularyCardRecord.Columns.id == id.uuidString.lowercased())
                .fetchOne(database),
                  var card = existingRecord.domainModel else {
                throw VocabularyRepositoryError.cardNotFound(id)
            }
            card.pronunciationIPA = cleanIPA
            card.updatedAt = date
            try VocabularyCardRecord(card: card).update(database)
            return card
        }
    }

    public func fetchEncounters(cardID: UUID) async throws -> [VocabularyEncounter] {
        try await database.queue.read { database in
            try VocabularyEncounterRecord.filter(VocabularyEncounterRecord.Columns.cardID == cardID.uuidString.lowercased())
                .order(VocabularyEncounterRecord.Columns.encounteredAtMS.desc).fetchAll(database).compactMap(\.domainModel)
        }
    }

    public func fetchEncounters(senseID: UUID) async throws -> [VocabularyEncounter] {
        try await database.queue.read { database in
            try VocabularyEncounterRecord
                .filter(VocabularyEncounterRecord.Columns.senseID == senseID.uuidString.lowercased())
                .order(VocabularyEncounterRecord.Columns.encounteredAtMS.desc)
                .fetchAll(database)
                .compactMap(\.domainModel)
        }
    }

    public func fetchAllEncounters() async throws -> [VocabularyEncounter] {
        try await database.queue.read { database in
            try VocabularyEncounterRecord
                .order(VocabularyEncounterRecord.Columns.encounteredAtMS.desc)
                .fetchAll(database)
                .compactMap(\.domainModel)
        }
    }

    public func addEncounter(id: UUID, at date: Date) async throws -> VocabularyCard {
        try await addEncounter(id: id, context: nil, sourceApplication: nil, at: date)
    }

    public func addEncounter(id: UUID, context: String?, sourceApplication: String?, at date: Date) async throws -> VocabularyCard {
        try await addEncounter(
            id: id,
            targetSenseID: nil,
            context: context,
            sourceApplication: sourceApplication,
            at: date
        )
    }

    public func addEncounter(
        id: UUID,
        senseID: UUID,
        context: String?,
        sourceApplication: String?,
        at date: Date
    ) async throws -> VocabularyCard {
        try await addEncounter(
            id: id,
            targetSenseID: senseID,
            context: context,
            sourceApplication: sourceApplication,
            at: date
        )
    }

    private func addEncounter(
        id: UUID,
        targetSenseID: UUID?,
        context: String?,
        sourceApplication: String?,
        at date: Date
    ) async throws -> VocabularyCard {
        try await database.queue.write { database in
            guard let existingRecord = try VocabularyCardRecord
                .filter(VocabularyCardRecord.Columns.id == id.uuidString.lowercased())
                .fetchOne(database),
                  var card = existingRecord.domainModel else {
                throw VocabularyRepositoryError.cardNotFound(id)
            }
            card.encounterCount += 1
            card.lastEncounteredAt = date
            card.updatedAt = date
            try VocabularyCardRecord(card: card).update(database)
            let senseID: UUID
            if let targetSenseID {
                let belongsToCard = try VocabularySenseRecord
                    .filter(
                        VocabularySenseRecord.Columns.id == targetSenseID.uuidString.lowercased()
                            && VocabularySenseRecord.Columns.cardID == id.uuidString.lowercased()
                    )
                    .fetchCount(database) > 0
                guard belongsToCard else {
                    throw VocabularySenseRepositoryError.senseNotFound(targetSenseID)
                }
                senseID = targetSenseID
            } else {
                senseID = try Self.primarySenseID(cardID: id, in: database)
            }
            try VocabularyEncounterRecord(
                VocabularyEncounter(
                    id: UUID(),
                    cardID: id,
                    senseID: senseID,
                    context: context,
                    sourceApplication: sourceApplication,
                    encounteredAt: date
                )
            ).insert(database)
            return card
        }
    }

    public func delete(id: UUID) async throws {
        try await database.queue.write { database in
            let deleted = try VocabularyCardRecord.deleteOne(
                database,
                key: id.uuidString.lowercased()
            )
            guard deleted else {
                throw VocabularyRepositoryError.cardNotFound(id)
            }
        }
    }

    private static func fetchDuplicate(
        in database: Database,
        normalizedTerm: String,
        languageCode: LanguageCode,
        excluding cardID: UUID?
    ) throws -> VocabularyCardRecord? {
        var request = VocabularyCardRecord.filter(
            VocabularyCardRecord.Columns.normalizedTerm == normalizedTerm
                && VocabularyCardRecord.Columns.languageCode == languageCode.rawValue
        )
        if let cardID {
            request = request.filter(
                VocabularyCardRecord.Columns.id != cardID.uuidString.lowercased()
            )
        }
        return try request.fetchOne(database)
    }

    private static func validateTags(_ tagIDs: Set<UUID>, in database: Database) throws {
        for tagID in tagIDs {
            let exists = try TagRecord
                .filter(TagRecord.Columns.id == tagID.uuidString.lowercased())
                .fetchCount(database) > 0
            guard exists else {
                throw VocabularyRepositoryError.tagNotFound(tagID)
            }
        }
    }

    private static func primarySenseID(cardID: UUID, in database: Database) throws -> UUID {
        guard let id = try VocabularySenseRecord
            .filter(
                VocabularySenseRecord.Columns.cardID == cardID.uuidString.lowercased()
                    && VocabularySenseRecord.Columns.isPrimary == true
            )
            .fetchOne(database)
            .flatMap({ UUID(uuidString: $0.id) }) else {
            throw VocabularyRepositoryError.cardNotFound(cardID)
        }
        return id
    }

    private static func mirrorCardContentToPrimarySense(
        _ card: VocabularyCard,
        in database: Database
    ) throws {
        guard let record = try VocabularySenseRecord
            .filter(
                VocabularySenseRecord.Columns.cardID == card.id.uuidString.lowercased()
                    && VocabularySenseRecord.Columns.isPrimary == true
            )
            .fetchOne(database),
              var sense = record.domainModel else {
            throw VocabularyRepositoryError.cardNotFound(card.id)
        }
        sense.translationZH = card.translationZH
        sense.definitionEN = card.definitionEN
        sense.exampleSentence = card.exampleSentence
        sense.memoryInsight = card.memoryInsight
        sense.memoryInsightFeedback = card.memoryInsightFeedback
        sense.updatedAt = card.updatedAt
        try VocabularySenseRecord(sense: sense).update(database)
    }

    private static func replaceTagLinks(
        cardID: UUID,
        tagIDs: Set<UUID>,
        at date: Date,
        in database: Database
    ) throws {
        try VocabularyCardTagRecord
            .filter(Column("card_id") == cardID.uuidString.lowercased())
            .deleteAll(database)

        for tagID in tagIDs {
            let record = VocabularyCardTagRecord(
                cardID: cardID.uuidString.lowercased(),
                tagID: tagID.uuidString.lowercased(),
                createdAtMS: DateStorage.milliseconds(date)
            )
            try record.insert(database)
        }
    }
}
