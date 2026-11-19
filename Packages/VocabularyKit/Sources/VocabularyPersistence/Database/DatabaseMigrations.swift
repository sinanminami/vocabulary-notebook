import Foundation
import GRDB
import VocabularyCore

enum DatabaseMigrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1.createCoreSchema") { database in
            try database.create(table: "vocabulary_cards") { table in
                table.column("id", .text).primaryKey()
                table.column("term", .text).notNull()
                table.column("normalized_term", .text).notNull()
                table.column("language_code", .text).notNull()
                table.column("translation_zh", .text).notNull()
                table.column("definition_en", .text).notNull()
                table.column("example_sentence", .text).notNull()
                table.column("encounter_count", .integer).notNull().defaults(to: 1)
                table.column("created_at_ms", .integer).notNull()
                table.column("updated_at_ms", .integer).notNull()
                table.column("last_encountered_at_ms", .integer).notNull()
                table.uniqueKey(["language_code", "normalized_term"])
            }

            try database.create(
                index: "idx_vocabulary_cards_normalized_term",
                on: "vocabulary_cards",
                columns: ["normalized_term"]
            )
            try database.create(
                index: "idx_vocabulary_cards_created_at",
                on: "vocabulary_cards",
                columns: ["created_at_ms"]
            )
            try database.create(
                index: "idx_vocabulary_cards_last_encountered",
                on: "vocabulary_cards",
                columns: ["last_encountered_at_ms"]
            )

            try database.create(table: "review_states") { table in
                table.column("id", .text).primaryKey()
                table.column("card_id", .text)
                    .notNull()
                    .unique()
                    .references("vocabulary_cards", onDelete: .cascade)
                table.column("due_at_ms", .integer).notNull()
                table.column("stability", .double).notNull().defaults(to: 0)
                table.column("difficulty", .double).notNull().defaults(to: 0)
                table.column("elapsed_days", .double).notNull().defaults(to: 0)
                table.column("scheduled_days", .double).notNull().defaults(to: 0)
                table.column("learning_step", .integer).notNull().defaults(to: 0)
                table.column("reps", .integer).notNull().defaults(to: 0)
                table.column("lapses", .integer).notNull().defaults(to: 0)
                table.column("fsrs_state", .text).notNull()
                table.column("last_reviewed_at_ms", .integer)
                table.column("scheduler_version", .text).notNull()
                table.column("updated_at_ms", .integer).notNull()
            }
            try database.create(
                index: "idx_review_states_due",
                on: "review_states",
                columns: ["due_at_ms", "fsrs_state"]
            )

            try database.create(table: "review_logs") { table in
                table.column("id", .text).primaryKey()
                table.column("card_id", .text)
                    .notNull()
                    .references("vocabulary_cards", onDelete: .cascade)
                table.column("reviewed_at_ms", .integer).notNull()
                table.column("rating", .text).notNull()
                table.column("review_mode", .text).notNull()
                table.column("previous_state_json", .text).notNull()
                table.column("new_state_json", .text).notNull()
                table.column("scheduled_interval_days", .double).notNull()
                table.column("scheduler_version", .text).notNull()
            }
            try database.create(
                index: "idx_review_logs_card_reviewed",
                on: "review_logs",
                columns: ["card_id", "reviewed_at_ms"]
            )
            try database.create(
                index: "idx_review_logs_reviewed",
                on: "review_logs",
                columns: ["reviewed_at_ms"]
            )

            try database.create(table: "tags") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("normalized_name", .text).notNull().unique()
                table.column("is_system", .boolean).notNull().defaults(to: false)
                table.column("sort_order", .integer).notNull().defaults(to: 0)
                table.column("created_at_ms", .integer).notNull()
                table.column("updated_at_ms", .integer).notNull()
            }

            try database.create(table: "vocabulary_card_tags") { table in
                table.column("card_id", .text)
                    .notNull()
                    .references("vocabulary_cards", onDelete: .cascade)
                table.column("tag_id", .text)
                    .notNull()
                    .references("tags", onDelete: .cascade)
                table.column("created_at_ms", .integer).notNull()
                table.primaryKey(["card_id", "tag_id"])
            }
            try database.create(
                index: "idx_vocabulary_card_tags_tag",
                on: "vocabulary_card_tags",
                columns: ["tag_id", "card_id"]
            )
        }

        migrator.registerMigration("v2.seedDefaultTags") { database in
            let names = [
                "Academic / Paper",
                "Data Analysis",
                "Statistics",
                "Machine Learning",
                "Product / Business",
                "Reporting / Presentation",
                "Work Communication",
                "Casual Conversation",
                "Daily Life",
                "Travel",
                "Technology",
                "Other"
            ]
            let now = DateStorage.milliseconds(Date())
            let normalizer = TermNormalizer()

            for (index, name) in names.enumerated() {
                let id = String(format: "00000000-0000-4000-8000-%012d", index + 1)
                let record = TagRecord(
                    id: id,
                    name: name,
                    normalizedName: try normalizer.normalize(name),
                    isSystem: true,
                    sortOrder: index,
                    createdAtMS: now,
                    updatedAtMS: now
                )
                try record.insert(database)
            }
        }

        migrator.registerMigration("v3.useFSRS6ForUnreviewedCards") { database in
            try database.execute(
                sql: """
                UPDATE review_states
                SET scheduler_version = 'fsrs-6'
                WHERE reps = 0
                """
            )
        }

        migrator.registerMigration("v4.createAppSettings") { database in
            try database.create(table: "app_settings") { table in
                table.column("id", .integer).primaryKey()
                table.column("daily_new_card_limit", .integer).notNull()
                table.column("updated_at_ms", .integer).notNull()
            }
            try database.execute(
                sql: """
                INSERT INTO app_settings (id, daily_new_card_limit, updated_at_ms)
                VALUES (?, ?, ?)
                """,
                arguments: [
                    AppSettingsRecord.singletonID,
                    AppSettings.defaultDailyNewCardLimit,
                    DateStorage.milliseconds(Date())
                ]
            )
        }

        migrator.registerMigration("v5.addReviewReminderSettings") { database in
            try database.alter(table: "app_settings") { table in
                table.add(column: "review_reminders_enabled", .boolean)
                    .notNull()
                    .defaults(to: false)
                table.add(column: "reminder_hour", .integer)
                    .notNull()
                    .defaults(to: 9)
                table.add(column: "reminder_minute", .integer)
                    .notNull()
                    .defaults(to: 0)
                table.add(column: "notify_only_when_due", .boolean)
                    .notNull()
                    .defaults(to: true)
            }
        }

        migrator.registerMigration("v6.addMemoryInsights") { database in
            try database.alter(table: "vocabulary_cards") { table in
                table.add(column: "memory_insight_json", .text)
                table.add(column: "memory_insight_feedback", .text)
            }
        }

        migrator.registerMigration("v7.addPronunciationIPA") { database in
            try database.alter(table: "vocabulary_cards") { table in
                table.add(column: "pronunciation_ipa", .text)
                    .notNull()
                    .defaults(to: "")
            }
        }

        migrator.registerMigration("v8.createVocabularyEncounters") { database in
            try database.create(table: "vocabulary_encounters") { table in
                table.column("id", .text).primaryKey()
                table.column("card_id", .text).notNull().references("vocabulary_cards", onDelete: .cascade)
                table.column("context", .text)
                table.column("source_application", .text)
                table.column("encountered_at_ms", .integer).notNull()
            }
            try database.create(index: "idx_vocabulary_encounters_card_date", on: "vocabulary_encounters", columns: ["card_id", "encountered_at_ms"])
            try database.execute(sql: "INSERT INTO vocabulary_encounters (id, card_id, encountered_at_ms) SELECT lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))), 2) || '-8' || substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6))), id, created_at_ms FROM vocabulary_cards")
        }

        migrator.registerMigration("v9.createVocabularySensesAndSenseReviews") { database in
            try database.create(table: "vocabulary_senses") { table in
                table.column("id", .text).primaryKey()
                table.column("card_id", .text)
                    .notNull()
                    .references("vocabulary_cards", onDelete: .cascade)
                table.column("sort_order", .integer).notNull()
                table.column("is_primary", .boolean).notNull().defaults(to: false)
                table.column("translation_zh", .text).notNull()
                table.column("definition_en", .text).notNull()
                table.column("example_sentence", .text).notNull()
                table.column("memory_insight_json", .text)
                table.column("memory_insight_feedback", .text)
                table.column("created_at_ms", .integer).notNull()
                table.column("updated_at_ms", .integer).notNull()
                table.uniqueKey(["card_id", "sort_order"])
            }
            try database.create(
                index: "idx_vocabulary_senses_card_order",
                on: "vocabulary_senses",
                columns: ["card_id", "sort_order"]
            )
            try database.execute(
                sql: """
                CREATE UNIQUE INDEX idx_vocabulary_senses_one_primary
                ON vocabulary_senses(card_id)
                WHERE is_primary = 1
                """
            )
            try database.execute(
                sql: """
                INSERT INTO vocabulary_senses (
                    id, card_id, sort_order, is_primary,
                    translation_zh, definition_en, example_sentence,
                    memory_insight_json, memory_insight_feedback,
                    created_at_ms, updated_at_ms
                )
                SELECT
                    lower(hex(randomblob(4))) || '-' ||
                    lower(hex(randomblob(2))) || '-4' ||
                    substr(lower(hex(randomblob(2))), 2) || '-8' ||
                    substr(lower(hex(randomblob(2))), 2) || '-' ||
                    lower(hex(randomblob(6))),
                    id, 0, 1,
                    translation_zh, definition_en, example_sentence,
                    memory_insight_json, memory_insight_feedback,
                    created_at_ms, updated_at_ms
                FROM vocabulary_cards
                """
            )

            // Rebuild encounters so every historical and future encounter belongs
            // to exactly one sense. v8 created one honest "first collected" row
            // per legacy card instead of fabricating rows from encounter_count.
            try database.execute(sql: "ALTER TABLE vocabulary_encounters RENAME TO vocabulary_encounters_v8")
            try database.create(table: "vocabulary_encounters") { table in
                table.column("id", .text).primaryKey()
                table.column("card_id", .text)
                    .notNull()
                    .references("vocabulary_cards", onDelete: .cascade)
                table.column("sense_id", .text)
                    .notNull()
                    .references("vocabulary_senses", onDelete: .cascade)
                table.column("context", .text)
                table.column("source_application", .text)
                table.column("encountered_at_ms", .integer).notNull()
            }
            try database.execute(
                sql: """
                INSERT INTO vocabulary_encounters (
                    id, card_id, sense_id, context, source_application, encountered_at_ms
                )
                SELECT e.id, e.card_id, s.id, e.context, e.source_application, e.encountered_at_ms
                FROM vocabulary_encounters_v8 e
                JOIN vocabulary_senses s
                  ON s.card_id = e.card_id AND s.is_primary = 1
                """
            )
            try database.drop(table: "vocabulary_encounters_v8")
            try database.create(
                index: "idx_vocabulary_encounters_card_date",
                on: "vocabulary_encounters",
                columns: ["card_id", "encountered_at_ms"]
            )
            try database.create(
                index: "idx_vocabulary_encounters_sense_date",
                on: "vocabulary_encounters",
                columns: ["sense_id", "encountered_at_ms"]
            )

            try database.create(table: "sense_review_states") { table in
                table.column("id", .text).primaryKey()
                table.column("card_id", .text)
                    .notNull()
                    .references("vocabulary_cards", onDelete: .cascade)
                table.column("sense_id", .text)
                    .notNull()
                    .unique()
                    .references("vocabulary_senses", onDelete: .cascade)
                table.column("due_at_ms", .integer).notNull()
                table.column("stability", .double).notNull().defaults(to: 0)
                table.column("difficulty", .double).notNull().defaults(to: 0)
                table.column("elapsed_days", .double).notNull().defaults(to: 0)
                table.column("scheduled_days", .double).notNull().defaults(to: 0)
                table.column("learning_step", .integer).notNull().defaults(to: 0)
                table.column("reps", .integer).notNull().defaults(to: 0)
                table.column("lapses", .integer).notNull().defaults(to: 0)
                table.column("fsrs_state", .text).notNull()
                table.column("last_reviewed_at_ms", .integer)
                table.column("scheduler_version", .text).notNull()
                table.column("updated_at_ms", .integer).notNull()
            }
            try database.create(
                index: "idx_sense_review_states_due",
                on: "sense_review_states",
                columns: ["due_at_ms", "fsrs_state"]
            )
            try database.execute(
                sql: """
                INSERT INTO sense_review_states (
                    id, card_id, sense_id, due_at_ms, stability, difficulty,
                    elapsed_days, scheduled_days, learning_step, reps, lapses,
                    fsrs_state, last_reviewed_at_ms, scheduler_version, updated_at_ms
                )
                SELECT
                    r.id, r.card_id, s.id, r.due_at_ms, r.stability, r.difficulty,
                    r.elapsed_days, r.scheduled_days, r.learning_step, r.reps, r.lapses,
                    r.fsrs_state, r.last_reviewed_at_ms, r.scheduler_version, r.updated_at_ms
                FROM review_states r
                JOIN vocabulary_senses s
                  ON s.card_id = r.card_id AND s.is_primary = 1
                """
            )

            try database.create(table: "sense_review_logs") { table in
                table.column("id", .text).primaryKey()
                table.column("card_id", .text)
                    .notNull()
                    .references("vocabulary_cards", onDelete: .cascade)
                table.column("sense_id", .text)
                    .notNull()
                    .references("vocabulary_senses", onDelete: .cascade)
                table.column("reviewed_at_ms", .integer).notNull()
                table.column("rating", .text).notNull()
                table.column("review_mode", .text).notNull()
                table.column("previous_state_json", .text).notNull()
                table.column("new_state_json", .text).notNull()
                table.column("scheduled_interval_days", .double).notNull()
                table.column("scheduler_version", .text).notNull()
            }
            try database.create(
                index: "idx_sense_review_logs_sense_reviewed",
                on: "sense_review_logs",
                columns: ["sense_id", "reviewed_at_ms"]
            )
            try database.create(
                index: "idx_sense_review_logs_reviewed",
                on: "sense_review_logs",
                columns: ["reviewed_at_ms"]
            )
            try database.execute(
                sql: """
                INSERT INTO sense_review_logs (
                    id, card_id, sense_id, reviewed_at_ms, rating, review_mode,
                    previous_state_json, new_state_json,
                    scheduled_interval_days, scheduler_version
                )
                SELECT
                    l.id, l.card_id, s.id, l.reviewed_at_ms, l.rating, l.review_mode,
                    l.previous_state_json, l.new_state_json,
                    l.scheduled_interval_days, l.scheduler_version
                FROM review_logs l
                JOIN vocabulary_senses s
                  ON s.card_id = l.card_id AND s.is_primary = 1
                """
            )
        }

        return migrator
    }
}
