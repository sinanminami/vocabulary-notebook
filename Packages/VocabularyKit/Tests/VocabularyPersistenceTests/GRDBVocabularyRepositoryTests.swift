import Foundation
import Testing
import VocabularyCore
@testable import VocabularyPersistence

@Suite("GRDB vocabulary repository", .serialized)
struct GRDBVocabularyRepositoryTests {
    @Test("Creates a card and its initial review state atomically")
    func createCard() async throws {
        let context = try Context()
        let now = Date(timeIntervalSince1970: 1_700_000_000.123)
        let tag = try #require(await context.tags.fetchAll().first)

        let card = try await context.cards.create(
            input(term: "  Normalization ", tagIDs: [tag.id]),
            at: now
        )

        #expect(card.term == "Normalization")
        #expect(card.normalizedTerm == "normalization")
        #expect(card.encounterCount == 1)
        #expect(try await context.cards.fetchCard(id: card.id) == card)
        let encounters = try await context.cards.fetchEncounters(cardID: card.id)
        #expect(encounters.count == 1)
        #expect(encounters.first?.encounteredAt == now)

        let senses = try await context.senses.fetchSenses(cardID: card.id)
        let primarySense = try #require(senses.first)
        #expect(senses.count == 1)
        #expect(primarySense.isPrimary)
        #expect(primarySense.sortOrder == 0)
        #expect(primarySense.translationZH == card.translationZH)
        #expect(encounters.first?.senseID == primarySense.id)

        let reviewState = try #require(await context.reviews.fetchState(cardID: card.id))
        #expect(reviewState.cardID == card.id)
        #expect(reviewState.fsrsState == .new)
        #expect(reviewState.reps == 0)
        #expect(reviewState.dueAt == now)
        let senseState = try #require(await context.senseReviews.fetchState(senseID: primarySense.id))
        #expect(senseState == reviewState.scoped(to: primarySense.id))
    }

    @Test("Rejects a normalized duplicate in the same language")
    func duplicateDetection() async throws {
        let context = try Context()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = try await context.cards.create(input(term: "State‑of‑the‑art"), at: now)

        do {
            _ = try await context.cards.create(input(term: " state-of-the-art "), at: now)
            Issue.record("Expected a duplicate error")
        } catch {
            #expect(error as? VocabularyRepositoryError == .duplicate(existingCardID: existing.id))
        }
    }

    @Test("Allows the same normalized spelling in different languages")
    func languageScopedUniqueness() async throws {
        let context = try Context()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await context.cards.create(input(term: "no", language: .english), at: now)
        let japanese = try await context.cards.create(input(term: "NO", language: .japanese), at: now)
        #expect(japanese.languageCode == .japanese)
    }

    @Test("Adds an encounter without touching the review schedule")
    func addEncounter() async throws {
        let context = try Context()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let encounteredAt = createdAt.addingTimeInterval(86_400)
        let card = try await context.cards.create(input(term: "trajectory"), at: createdAt)
        let stateBefore = try #require(await context.reviews.fetchState(cardID: card.id))

        let updated = try await context.cards.addEncounter(
            id: card.id,
            context: "I followed the word's trajectory through the report.",
            sourceApplication: "Quick Add",
            at: encounteredAt
        )
        let stateAfter = try #require(await context.reviews.fetchState(cardID: card.id))

        #expect(updated.encounterCount == 2)
        #expect(updated.lastEncounteredAt == encounteredAt)
        #expect(stateAfter == stateBefore)
        let encounters = try await context.cards.fetchEncounters(cardID: card.id)
        let allEncounters = try await context.cards.fetchAllEncounters()
        #expect(encounters.count == 2)
        #expect(allEncounters.count == 2)
        #expect(encounters.first?.context == "I followed the word's trajectory through the report.")
        #expect(encounters.first?.sourceApplication == "Quick Add")
    }

    @Test("Updates editable card fields")
    func updateCard() async throws {
        let context = try Context()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = createdAt.addingTimeInterval(10)
        let card = try await context.cards.create(input(term: "explicit"), at: createdAt)
        let changes = VocabularyCardChanges(
            term: "Explicit",
            languageCode: .english,
            translationZH: "明确的；显式的",
            definitionEN: "stated clearly and directly",
            exampleSentence: "The model makes the assumption explicit."
        )

        let updated = try await context.cards.update(id: card.id, changes: changes, at: updatedAt)
        #expect(updated.term == "Explicit")
        #expect(updated.normalizedTerm == "explicit")
        #expect(updated.translationZH == "明确的；显式的")
        #expect(updated.createdAt == createdAt)
        #expect(updated.updatedAt == updatedAt)
        let primarySense = try #require(await context.senses.fetchSenses(cardID: card.id).first)
        #expect(primarySense.translationZH == updated.translationZH)
        #expect(primarySense.definitionEN == updated.definitionEN)
        #expect(primarySense.exampleSentence == updated.exampleSentence)
    }

    @Test("Creates a secondary sense with an independent review schedule")
    func secondarySenseLifecycle() async throws {
        let context = try Context()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let card = try await context.cards.create(input(term: "draft"), at: now)
        let cardStateBefore = try #require(await context.reviews.fetchState(cardID: card.id))

        let secondary = try await context.senses.create(
            cardID: card.id,
            input: NewVocabularySense(
                translationZH: "草稿；起草",
                definitionEN: "to prepare an initial version",
                exampleSentence: "She drafted the proposal."
            ),
            at: now.addingTimeInterval(10)
        )
        #expect(!secondary.isPrimary)
        #expect(secondary.sortOrder == 1)
        let initialSenseState = try #require(await context.senseReviews.fetchState(senseID: secondary.id))
        #expect(initialSenseState.reps == 0)

        let cardAfterEncounter = try await context.cards.addEncounter(
            id: card.id,
            senseID: secondary.id,
            context: "She drafted the proposal.",
            sourceApplication: "Preview",
            at: now.addingTimeInterval(20)
        )
        let secondaryEncounters = try await context.cards.fetchEncounters(senseID: secondary.id)
        #expect(cardAfterEncounter.encounterCount == 2)
        #expect(secondaryEncounters.count == 1)
        #expect(secondaryEncounters.first?.senseID == secondary.id)

        let log = try await context.senseReviews.recordReview(
            senseID: secondary.id,
            rating: .good,
            mode: .termToMeaning,
            at: now.addingTimeInterval(10)
        )
        #expect(log.senseID == secondary.id)
        #expect(log.newState.reps == 1)
        #expect(try await context.reviews.fetchState(cardID: card.id) == cardStateBefore)
        #expect(try await context.reviews.fetchReviewLogs(since: nil).isEmpty)
        #expect(try await context.senseReviews.fetchReviewLogs(senseID: secondary.id, since: nil).count == 1)

        try await context.senses.delete(id: secondary.id)
        #expect(try await context.senses.fetchSense(id: secondary.id) == nil)
        #expect(try await context.senseReviews.fetchState(senseID: secondary.id) == nil)
    }

    @Test("Protects the primary sense from direct deletion")
    func protectsPrimarySense() async throws {
        let context = try Context()
        let card = try await context.cards.create(
            input(term: "anchor"),
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let primary = try #require(await context.senses.fetchSenses(cardID: card.id).first)

        await #expect(throws: VocabularySenseRepositoryError.primarySenseProtected(primary.id)) {
            try await context.senses.delete(id: primary.id)
        }
    }

    @Test("Persists memory insights, feedback, and alternate strategies")
    func memoryInsightLifecycle() async throws {
        let context = try Context()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let initialInsight = MemoryInsight(
            strategy: .morphology,
            titleZH: "构词与语义桥梁",
            breakdown: "consider + -able",
            cueZH: "大到值得认真考虑，因此表示相当大的。",
            mnemonic: "A considerable problem is big enough to consider.",
            contrastNoteZH: "不要和 considerate（体贴的）混淆。"
        )
        let created = try await context.cards.create(
            input(term: "considerable", memoryInsight: initialInsight),
            at: now
        )

        #expect(created.memoryInsight == initialInsight)
        #expect(try await context.cards.fetchCard(id: created.id)?.memoryInsight == initialInsight)

        let helpful = try await context.cards.setMemoryInsightFeedback(
            id: created.id,
            feedback: .helpful,
            at: now.addingTimeInterval(1)
        )
        #expect(helpful.memoryInsightFeedback == .helpful)

        let alternate = MemoryInsight(
            strategy: .contrast,
            titleZH: "易混辨析",
            cueZH: "用 considerable 表示规模可观。",
            mnemonic: "Considerable means notably large.",
            contrastNoteZH: "considerate 表示体贴的。"
        )
        let replaced = try await context.cards.setMemoryInsight(
            id: created.id,
            insight: alternate,
            at: now.addingTimeInterval(2)
        )
        #expect(replaced.memoryInsight == alternate)
        #expect(replaced.memoryInsightFeedback == nil)
    }

    @Test("Persists and supplements IPA pronunciation")
    func pronunciationLifecycle() async throws {
        let context = try Context()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let created = try await context.cards.create(
            input(term: "considerable", pronunciationIPA: "/kənˈsɪdərəbəl/"),
            at: now
        )
        #expect(created.pronunciationIPA == "/kənˈsɪdərəbəl/")

        let updated = try await context.cards.setPronunciationIPA(
            id: created.id,
            pronunciationIPA: "  /kənˈsɪdrəbəl/  ",
            at: now.addingTimeInterval(1)
        )
        #expect(updated.pronunciationIPA == "/kənˈsɪdrəbəl/")
        #expect(try await context.cards.fetchCard(id: created.id)?.pronunciationIPA == "/kənˈsɪdrəbəl/")
    }

    @Test("Deleting a card cascades to its review state")
    func deleteCard() async throws {
        let context = try Context()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let card = try await context.cards.create(input(term: "meticulously"), at: now)

        try await context.cards.delete(id: card.id)

        #expect(try await context.cards.fetchCard(id: card.id) == nil)
        #expect(try await context.reviews.fetchState(cardID: card.id) == nil)
    }

    @Test("Seeds the ordered default tag set")
    func defaultTags() async throws {
        let context = try Context()
        let tags = try await context.tags.fetchAll()

        #expect(tags.count == 12)
        #expect(tags.first?.name == "Academic / Paper")
        #expect(tags.last?.name == "Other")
        let allTagsAreSystemTags = tags.allSatisfy { $0.isSystem }
        #expect(allTagsAreSystemTags)
    }

    @Test("Reads tag assignments after create and update")
    func tagAssignments() async throws {
        let context = try Context()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tags = try await context.tags.fetchAll()
        let firstTag = try #require(tags.first)
        let secondTag = try #require(tags.dropFirst().first)
        let card = try await context.cards.create(
            input(term: "segment", tagIDs: [firstTag.id]),
            at: now
        )

        var assignments = try await context.tags.fetchTagIDsByCardID()
        #expect(assignments[card.id] == [firstTag.id])

        _ = try await context.cards.update(
            id: card.id,
            changes: VocabularyCardChanges(
                term: card.term,
                languageCode: card.languageCode,
                translationZH: card.translationZH,
                definitionEN: card.definitionEN,
                exampleSentence: card.exampleSentence,
                tagIDs: [secondTag.id]
            ),
            at: now.addingTimeInterval(60)
        )

        assignments = try await context.tags.fetchTagIDsByCardID()
        #expect(assignments[card.id] == [secondTag.id])
    }

    @Test("Lists cards newest first with all review states")
    func listCardsAndStates() async throws {
        let context = try Context()
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let later = earlier.addingTimeInterval(60)
        let first = try await context.cards.create(input(term: "first"), at: earlier)
        let second = try await context.cards.create(input(term: "second"), at: later)

        let cards = try await context.cards.fetchAll()
        let states = try await context.reviews.fetchAll()

        #expect(cards.map(\.id) == [second.id, first.id])
        #expect(Set(states.map(\.cardID)) == [first.id, second.id])
    }

    @Test("Creates, renames, and deletes a custom tag")
    func customTagLifecycle() async throws {
        let context = try Context()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tag = try await context.tags.create(name: "  Research   Notes ", at: now)
        #expect(tag.name == "Research Notes")
        #expect(!tag.isSystem)

        let renamed = try await context.tags.rename(
            id: tag.id,
            name: "Reading List",
            at: now.addingTimeInterval(10)
        )
        #expect(renamed.name == "Reading List")

        try await context.tags.delete(id: tag.id)
        #expect(try await context.tags.fetchAll().contains(where: { $0.id == tag.id }) == false)
    }

    @Test("Protects system tags and normalized custom tag uniqueness")
    func tagProtection() async throws {
        let context = try Context()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let systemTag = try #require(await context.tags.fetchAll().first)
        _ = try await context.tags.create(name: "Research Notes", at: now)

        await #expect(throws: TagRepositoryError.systemTagProtected) {
            try await context.tags.delete(id: systemTag.id)
        }
        await #expect(throws: TagRepositoryError.duplicateName) {
            try await context.tags.create(name: " research  notes ", at: now)
        }
    }

    private func input(
        term: String,
        language: LanguageCode = .english,
        pronunciationIPA: String = "",
        memoryInsight: MemoryInsight? = nil,
        tagIDs: Set<UUID> = []
    ) -> NewVocabularyCard {
        NewVocabularyCard(
            term: term,
            languageCode: language,
            pronunciationIPA: pronunciationIPA,
            translationZH: "测试释义",
            definitionEN: "a concise definition",
            exampleSentence: "The analyst used the term in a report.",
            memoryInsight: memoryInsight,
            tagIDs: tagIDs
        )
    }

    private struct Context {
        let cards: GRDBVocabularyRepository
        let reviews: GRDBReviewStateRepository
        let senses: GRDBVocabularySenseRepository
        let senseReviews: GRDBSenseReviewRepository
        let tags: GRDBTagRepository

        init() throws {
            let database = try AppDatabase.inMemory()
            cards = GRDBVocabularyRepository(database: database)
            reviews = GRDBReviewStateRepository(database: database)
            senses = GRDBVocabularySenseRepository(database: database)
            senseReviews = GRDBSenseReviewRepository(database: database)
            tags = GRDBTagRepository(database: database)
        }
    }
}
