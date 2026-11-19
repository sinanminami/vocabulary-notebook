import Foundation
import Observation
import VocabularyCore

@MainActor
@Observable
final class VocabularySnapshotModel {
    private(set) var cards: [VocabularyCard] = []
    private(set) var statesByCardID: [UUID: ReviewState] = [:]
    private(set) var reviewLogs: [ReviewLogEntry] = []
    private(set) var sensesByCardID: [UUID: [VocabularySense]] = [:]
    private(set) var senseStatesBySenseID: [UUID: ReviewState] = [:]
    private(set) var encounters: [VocabularyEncounter] = []
    private(set) var tags: [Tag] = []
    private(set) var tagIDsByCardID: [UUID: Set<UUID>] = [:]
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let vocabularyRepository: any VocabularyRepository
    private let reviewStateRepository: any ReviewStateRepository
    private let reviewSessionRepository: (any ReviewSessionRepository)?
    private let vocabularySenseRepository: (any VocabularySenseRepository)?
    private let senseReviewRepository: (any SenseReviewRepository)?
    private let tagRepository: (any TagRepository)?
    private let masteryPolicy = MasteryPolicy()

    init(
        vocabularyRepository: any VocabularyRepository,
        reviewStateRepository: any ReviewStateRepository,
        reviewSessionRepository: (any ReviewSessionRepository)? = nil,
        vocabularySenseRepository: (any VocabularySenseRepository)? = nil,
        senseReviewRepository: (any SenseReviewRepository)? = nil,
        tagRepository: (any TagRepository)? = nil
    ) {
        self.vocabularyRepository = vocabularyRepository
        self.reviewStateRepository = reviewStateRepository
        self.reviewSessionRepository = reviewSessionRepository
        self.vocabularySenseRepository = vocabularySenseRepository
        self.senseReviewRepository = senseReviewRepository
        self.tagRepository = tagRepository
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let cards = vocabularyRepository.fetchAll()
            async let states = reviewStateRepository.fetchAll()
            async let logs = loadReviewLogs()
            async let senses = loadSenses()
            async let senseStates = loadSenseStates()
            async let tags = loadTags()
            async let assignments = loadTagAssignments()
            async let encounters = vocabularyRepository.fetchAllEncounters()
            let (
                loadedCards,
                loadedStates,
                loadedLogs,
                loadedSenses,
                loadedSenseStates,
                loadedTags,
                loadedAssignments,
                loadedEncounters
            ) = try await (
                cards,
                states,
                logs,
                senses,
                senseStates,
                tags,
                assignments,
                encounters
            )
            self.cards = loadedCards
            statesByCardID = Dictionary(uniqueKeysWithValues: loadedStates.map { ($0.cardID, $0) })
            reviewLogs = loadedLogs
            sensesByCardID = Dictionary(grouping: loadedSenses, by: \.cardID)
                .mapValues { $0.sorted { $0.sortOrder < $1.sortOrder } }
            senseStatesBySenseID = Dictionary(
                uniqueKeysWithValues: loadedSenseStates.compactMap { state in
                    state.senseID.map { ($0, state) }
                }
            )
            self.tags = loadedTags
            tagIDsByCardID = loadedAssignments
            self.encounters = loadedEncounters
        } catch {
            errorMessage = "无法读取词库：\(error.localizedDescription)"
        }
        isLoading = false
    }

    private func loadReviewLogs() async throws -> [ReviewLogEntry] {
        if let senseReviewRepository {
            return try await senseReviewRepository.fetchReviewLogs(senseID: nil, since: nil)
        }
        guard let reviewSessionRepository else { return [] }
        return try await reviewSessionRepository.fetchReviewLogs(since: nil)
    }

    private func loadSenses() async throws -> [VocabularySense] {
        try await vocabularySenseRepository?.fetchAll() ?? []
    }

    private func loadSenseStates() async throws -> [ReviewState] {
        try await senseReviewRepository?.fetchAllStates() ?? []
    }

    private func loadTags() async throws -> [Tag] {
        guard let tagRepository else { return [] }
        return try await tagRepository.fetchAll()
    }

    private func loadTagAssignments() async throws -> [UUID: Set<UUID>] {
        guard let tagRepository else { return [:] }
        return try await tagRepository.fetchTagIDsByCardID()
    }

    func state(for card: VocabularyCard) -> ReviewState? {
        statesByCardID[card.id]
    }

    func senses(for card: VocabularyCard) -> [VocabularySense] {
        sensesByCardID[card.id] ?? []
    }

    func state(for sense: VocabularySense) -> ReviewState? {
        senseStatesBySenseID[sense.id]
    }

    func mastery(for sense: VocabularySense) -> MasteryLevel {
        state(for: sense).map(masteryPolicy.level(for:)) ?? .new
    }

    var reviewStates: [ReviewState] {
        Array(statesByCardID.values)
    }

    var senses: [VocabularySense] {
        sensesByCardID.values.flatMap { $0 }
    }

    var senseReviewStates: [ReviewState] {
        Array(senseStatesBySenseID.values)
    }

    func encounters(for sense: VocabularySense) -> [VocabularyEncounter] {
        encounters.filter { $0.senseID == sense.id }
    }

    func mastery(for card: VocabularyCard) -> MasteryLevel {
        let senseLevels = senses(for: card).map(mastery(for:))
        guard !senseLevels.isEmpty else {
            return state(for: card).map(masteryPolicy.level(for:)) ?? .new
        }
        return senseLevels.min(by: { masteryRank($0) < masteryRank($1) }) ?? .new
    }

    func tags(for card: VocabularyCard) -> [Tag] {
        let tagIDs = tagIDsByCardID[card.id] ?? []
        return tags.filter { tagIDs.contains($0.id) }
    }

    func lastReviewedAt(for card: VocabularyCard) -> Date? {
        let senseDates = senses(for: card).compactMap { state(for: $0)?.lastReviewedAt }
        return senseDates.max() ?? state(for: card)?.lastReviewedAt
    }

    func dueReviewCards(at date: Date = Date()) -> [VocabularyCard] {
        if vocabularySenseRepository != nil, senseReviewRepository != nil {
            let dueCardIDs = Set(dueReviewSenses(at: date).map(\.cardID))
            return cards.filter { dueCardIDs.contains($0.id) }
        }
        return cards.filter { card in
            guard let state = state(for: card) else { return false }
            return state.fsrsState != .new && state.dueAt <= date
        }
    }

    func newCards() -> [VocabularyCard] {
        if vocabularySenseRepository != nil, senseReviewRepository != nil {
            let newCardIDs = Set(newSenses().map(\.cardID))
            return cards.filter { newCardIDs.contains($0.id) }
        }
        return cards.filter { card in
            guard let state = state(for: card) else { return true }
            return state.fsrsState == .new || state.reps == 0
        }
    }

    func dueReviewSenses(at date: Date = Date()) -> [VocabularySense] {
        sensesByCardID.values.flatMap { $0 }.filter { sense in
            guard let state = state(for: sense) else { return false }
            return state.fsrsState != .new && state.reps > 0 && state.dueAt <= date
        }
    }

    func newSenses() -> [VocabularySense] {
        sensesByCardID.values.flatMap { $0 }.filter { sense in
            guard let state = state(for: sense) else { return true }
            return state.fsrsState == .new || state.reps == 0
        }
    }

    private func masteryRank(_ level: MasteryLevel) -> Int {
        switch level {
        case .new: 0
        case .learning: 1
        case .familiar: 2
        case .mastered: 3
        }
    }

}

extension MasteryLevel {
    var displayName: String {
        switch self {
        case .new: "待学习"
        case .learning: "学习中"
        case .familiar: "熟悉"
        case .mastered: "已掌握"
        }
    }
}
