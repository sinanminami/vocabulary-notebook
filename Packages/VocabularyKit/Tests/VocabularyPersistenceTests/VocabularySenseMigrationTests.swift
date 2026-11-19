import Foundation
import GRDB
import Testing
import VocabularyCore
@testable import VocabularyPersistence

@Suite("Vocabulary sense migration", .serialized)
struct VocabularySenseMigrationTests {
    @Test("v9 maps each legacy card, encounter, state, and log to one primary sense")
    func migratesLegacyDataWithoutInventingEncounters() throws {
        let queue = try DatabaseQueue()
        let migrator = DatabaseMigrations.migrator
        try migrator.migrate(queue, upTo: "v7.addPronunciationIPA")

        let cardID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let stateID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
        let logID = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
        let createdAtMS: Int64 = 1_700_000_000_123
        let reviewedAt = Date(timeIntervalSince1970: 1_700_086_400)
        let previousState = ReviewState(
            id: stateID,
            cardID: cardID,
            dueAt: DateStorage.date(createdAtMS),
            updatedAt: DateStorage.date(createdAtMS)
        )
        var newState = previousState
        newState.reps = 3
        newState.stability = 4.5
        newState.dueAt = reviewedAt.addingTimeInterval(86_400)
        newState.lastReviewedAt = reviewedAt
        newState.updatedAt = reviewedAt
        let encoder = JSONEncoder()
        let previousJSON = String(decoding: try encoder.encode(previousState), as: UTF8.self)
        let newJSON = String(decoding: try encoder.encode(newState), as: UTF8.self)

        try queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO vocabulary_cards (
                    id, term, normalized_term, language_code, pronunciation_ipa,
                    translation_zh, definition_en, example_sentence,
                    memory_insight_json, memory_insight_feedback,
                    encounter_count, created_at_ms, updated_at_ms, last_encountered_at_ms
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?, ?, ?)
                """,
                arguments: [
                    cardID.uuidString.lowercased(), "draft", "draft", "en", "/dræft/",
                    "草稿", "an initial version", "This is the first draft.",
                    4, createdAtMS, createdAtMS + 2_000, createdAtMS + 1_000
                ]
            )
            try database.execute(
                sql: """
                INSERT INTO review_states (
                    id, card_id, due_at_ms, stability, difficulty, elapsed_days,
                    scheduled_days, learning_step, reps, lapses, fsrs_state,
                    last_reviewed_at_ms, scheduler_version, updated_at_ms
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    stateID.uuidString.lowercased(), cardID.uuidString.lowercased(),
                    DateStorage.milliseconds(newState.dueAt), newState.stability, 5.0, 1.0,
                    1.0, 0, newState.reps, 0, "review",
                    DateStorage.milliseconds(reviewedAt), "fsrs-6", DateStorage.milliseconds(reviewedAt)
                ]
            )
            try database.execute(
                sql: """
                INSERT INTO review_logs (
                    id, card_id, reviewed_at_ms, rating, review_mode,
                    previous_state_json, new_state_json,
                    scheduled_interval_days, scheduler_version
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    logID.uuidString.lowercased(), cardID.uuidString.lowercased(),
                    DateStorage.milliseconds(reviewedAt), "good", "termToMeaning",
                    previousJSON, newJSON, 1.0, "fsrs-6"
                ]
            )
        }

        try migrator.migrate(queue, upTo: "v8.createVocabularyEncounters")
        try migrator.migrate(queue)

        try queue.read { database in
            #expect(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM vocabulary_senses") == 1)
            #expect(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM vocabulary_encounters") == 1)
            #expect(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM sense_review_states") == 1)
            #expect(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM sense_review_logs") == 1)
            #expect(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM review_states") == 1)
            #expect(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM review_logs") == 1)

            let sense = try #require(try VocabularySenseRecord.fetchOne(database))
            #expect(sense.cardID == cardID.uuidString.lowercased())
            #expect(sense.isPrimary)
            #expect(sense.sortOrder == 0)
            #expect(sense.translationZH == "草稿")

            let encounter = try #require(try VocabularyEncounterRecord.fetchOne(database))
            #expect(encounter.cardID == sense.cardID)
            #expect(encounter.senseID == sense.id)
            #expect(encounter.encounteredAtMS == createdAtMS)

            let senseState = try #require(try SenseReviewStateRecord.fetchOne(database))
            #expect(senseState.id == stateID.uuidString.lowercased())
            #expect(senseState.senseID == sense.id)
            #expect(senseState.reps == 3)
            #expect(senseState.stability == 4.5)

            let senseLog = try #require(try SenseReviewLogRecord.fetchOne(database))
            #expect(senseLog.id == logID.uuidString.lowercased())
            #expect(senseLog.senseID == sense.id)

            let foreignKeyViolationCount = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM pragma_foreign_key_check"
            )
            #expect(foreignKeyViolationCount == 0)
        }
    }

    @Test("A copied live library migrates without changing legacy counts")
    func migratesCopiedLiveLibraryWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["VOCABULARY_MIGRATION_FIXTURE_PATH"] else {
            return
        }
        let before = try legacySnapshot(path: path)
        #expect(!before.hasSenseTables)

        let migratedDatabase = try AppDatabase(path: path)
        try migratedDatabase.queue.read { database in
            let cardCount = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM vocabulary_cards")
            let reviewStateCount = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM review_states")
            let reviewLogCount = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM review_logs")
            let encounterCount = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM vocabulary_encounters")
            let senseCount = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM vocabulary_senses")
            let senseStateCount = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM sense_review_states")
            let senseLogCount = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM sense_review_logs")
            let unassignedEncounterCount = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM vocabulary_encounters WHERE sense_id IS NULL"
            )
            let foreignKeyViolationCount = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM pragma_foreign_key_check"
            )
            #expect(cardCount == before.cardCount)
            #expect(reviewStateCount == before.reviewStateCount)
            #expect(reviewLogCount == before.reviewLogCount)
            #expect(encounterCount == before.encounterCount)
            #expect(senseCount == before.cardCount)
            #expect(senseStateCount == before.reviewStateCount)
            #expect(senseLogCount == before.reviewLogCount)
            #expect(unassignedEncounterCount == 0)
            #expect(foreignKeyViolationCount == 0)
        }
    }

    private func legacySnapshot(path: String) throws -> LegacySnapshot {
        let queue = try DatabaseQueue(path: path)
        return try queue.read { database in
            LegacySnapshot(
                cardCount: try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM vocabulary_cards") ?? 0,
                reviewStateCount: try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM review_states") ?? 0,
                reviewLogCount: try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM review_logs") ?? 0,
                encounterCount: try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM vocabulary_encounters") ?? 0,
                hasSenseTables: try database.tableExists("vocabulary_senses")
            )
        }
    }

    private struct LegacySnapshot {
        let cardCount: Int
        let reviewStateCount: Int
        let reviewLogCount: Int
        let encounterCount: Int
        let hasSenseTables: Bool
    }
}
