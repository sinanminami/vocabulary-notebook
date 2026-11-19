import Foundation
import Observation
import VocabularyCore

@MainActor
@Observable
final class AddWordViewModel {
    enum Phase: Equatable {
        case entry
        case generating
        case editing
        case duplicate
        case saving
    }

    enum DuplicateSenseChoice: Hashable {
        case existing(UUID)
        case newSense
    }

    var phase: Phase = .entry
    var term = ""
    var context = ""
    var languageCode: LanguageCode = .english
    var pronunciationIPA = ""
    var translationZH = ""
    var definitionEN = ""
    var exampleSentence = ""
    var memoryInsight: MemoryInsight?
    var availableTags: [Tag] = []
    var selectedTagIDs: Set<UUID> = []
    var duplicateCard: VocabularyCard?
    var duplicateReviewState: ReviewState?
    var duplicateSenses: [VocabularySense] = []
    var duplicateSenseChoice: DuplicateSenseChoice?
    var duplicateSenseRecommendation: EncounterSenseMatchResult?
    var isMatchingDuplicateSense = false
    var duplicateSenseMatchNotice: String?
    var errorMessage: String?
    var didFinish = false

    let sourceApplication: String?

    private let vocabularyRepository: any VocabularyRepository
    private let vocabularySenseRepository: (any VocabularySenseRepository)?
    private let reviewStateRepository: any ReviewStateRepository
    private let tagRepository: any TagRepository
    private let aiProvider: any AIProvider
    private let normalizer = TermNormalizer()
    private let masteryPolicy = MasteryPolicy()
    private var hasAttemptedAutomaticGeneration = false
    private var duplicateCandidate: VocabularyGenerationResult?
    private var duplicateCandidateContext: String?

    init(
        vocabularyRepository: any VocabularyRepository,
        vocabularySenseRepository: (any VocabularySenseRepository)? = nil,
        reviewStateRepository: any ReviewStateRepository,
        tagRepository: any TagRepository,
        aiProvider: any AIProvider,
        initialTerm: String = "",
        sourceApplication: String? = nil
    ) {
        self.vocabularyRepository = vocabularyRepository
        self.vocabularySenseRepository = vocabularySenseRepository
        self.reviewStateRepository = reviewStateRepository
        self.tagRepository = tagRepository
        self.aiProvider = aiProvider
        term = initialTerm
        self.sourceApplication = sourceApplication?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var isFormValid: Bool {
        !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !translationZH.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !definitionEN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (memoryInsight.map { (try? $0.validated()) != nil } ?? true)
    }

    var duplicateMastery: MasteryLevel {
        duplicateReviewState.map(masteryPolicy.level(for:)) ?? .new
    }

    var proposedNewSenseTranslation: String {
        duplicateCandidate?.translationZH ?? translationZH
    }

    var proposedNewSenseDefinition: String {
        duplicateCandidate?.definitionEN ?? definitionEN
    }

    var duplicateActionTitle: String {
        duplicateSenseChoice == .newSense ? "Create Meaning & Save" : "Save Encounter"
    }

    var canSaveDuplicateEncounter: Bool {
        duplicateSenseChoice != nil && !isMatchingDuplicateSense
    }

    func loadTags() async {
        guard availableTags.isEmpty else { return }
        do {
            availableTags = try await tagRepository.fetchAll()
        } catch {
            errorMessage = "无法读取标签：\(error.localizedDescription)"
        }
    }

    func prepare(automaticallyGenerate: Bool) async {
        await loadTags()

        guard automaticallyGenerate,
              !hasAttemptedAutomaticGeneration,
              !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        hasAttemptedAutomaticGeneration = true
        await generate()
    }

    func generate() async {
        guard phase != .generating, phase != .saving else { return }
        errorMessage = nil
        phase = .generating

        do {
            let displayTerm = try normalizer.displayTerm(term)
            term = displayTerm

            let generated = try await aiProvider.generateVocabularyCard(
                request: VocabularyGenerationRequest(
                    term: displayTerm,
                    context: context.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                )
            )
            let normalizedGeneratedTerm = try normalizer.normalize(generated.term)
            if let existing = try await vocabularyRepository
                .fetchCards(normalizedTerm: normalizedGeneratedTerm)
                .first(where: { $0.languageCode == generated.languageCode }) {
                try await presentDuplicate(existing, generated: generated)
                return
            }
            apply(generated)
            phase = .editing
        } catch is CancellationError {
            phase = .entry
        } catch {
            phase = .entry
            errorMessage = userMessage(for: error)
        }
    }

    func save() async {
        guard isFormValid, phase == .editing else { return }
        errorMessage = nil
        phase = .saving

        do {
            _ = try await vocabularyRepository.create(
                NewVocabularyCard(
                    term: term,
                    languageCode: languageCode,
                    pronunciationIPA: pronunciationIPA.trimmingCharacters(in: .whitespacesAndNewlines),
                    translationZH: translationZH.trimmingCharacters(in: .whitespacesAndNewlines),
                    definitionEN: definitionEN.trimmingCharacters(in: .whitespacesAndNewlines),
                    exampleSentence: exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines),
                    memoryInsight: memoryInsight,
                    encounterContext: context.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    encounterSourceApplication: sourceApplication,
                    tagIDs: selectedTagIDs
                ),
                at: Date()
            )
            didFinish = true
        } catch let VocabularyRepositoryError.duplicate(existingCardID) {
            do {
                guard let existing = try await vocabularyRepository.fetchCard(id: existingCardID) else {
                    throw VocabularyRepositoryError.cardNotFound(existingCardID)
                }
                try await presentDuplicate(existing, generated: currentCandidate())
            } catch {
                phase = .editing
                errorMessage = userMessage(for: error)
            }
        } catch {
            phase = .editing
            errorMessage = userMessage(for: error)
        }
    }

    func addEncounter() async {
        guard let duplicateCard, phase == .duplicate else { return }
        errorMessage = nil
        phase = .saving
        do {
            let now = Date()
            let cleanContext = context.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            switch duplicateSenseChoice {
            case let .existing(senseID):
                _ = try await vocabularyRepository.addEncounter(
                    id: duplicateCard.id,
                    senseID: senseID,
                    context: cleanContext,
                    sourceApplication: sourceApplication,
                    at: now
                )
            case .newSense:
                guard let vocabularySenseRepository else {
                    throw AIProviderError.invalidResponse
                }
                let candidate = duplicateCandidate ?? currentCandidate()
                let sense = try await vocabularySenseRepository.create(
                    cardID: duplicateCard.id,
                    input: NewVocabularySense(
                        translationZH: candidate.translationZH,
                        definitionEN: candidate.definitionEN,
                        exampleSentence: candidate.exampleSentence,
                        memoryInsight: candidate.memoryInsight
                    ),
                    at: now
                )
                _ = try await vocabularyRepository.addEncounter(
                    id: duplicateCard.id,
                    senseID: sense.id,
                    context: cleanContext,
                    sourceApplication: sourceApplication,
                    at: now
                )
            case nil:
                _ = try await vocabularyRepository.addEncounter(
                    id: duplicateCard.id,
                    context: cleanContext,
                    sourceApplication: sourceApplication,
                    at: now
                )
            }
            didFinish = true
        } catch {
            phase = .duplicate
            errorMessage = userMessage(for: error)
        }
    }

    func matchDuplicateSense() async {
        guard phase == .duplicate, !isMatchingDuplicateSense else { return }
        let cleanContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanContext.isEmpty, !duplicateSenses.isEmpty else {
            duplicateSenseMatchNotice = "粘贴含有这个词的原句后，AI 才能对照词义。"
            return
        }

        isMatchingDuplicateSense = true
        duplicateSenseMatchNotice = nil
        defer { isMatchingDuplicateSense = false }
        do {
            let generated: VocabularyGenerationResult
            if let duplicateCandidate, duplicateCandidateContext == cleanContext {
                generated = duplicateCandidate
            } else {
                generated = try await aiProvider.generateVocabularyCard(
                    request: VocabularyGenerationRequest(term: term, context: cleanContext)
                )
                duplicateCandidate = generated
                duplicateCandidateContext = cleanContext
            }
            let recommendation = try await aiProvider.matchEncounterSense(
                request: EncounterSenseMatchRequest(
                    term: generated.term,
                    languageCode: generated.languageCode,
                    context: cleanContext,
                    generatedTranslationZH: generated.translationZH,
                    generatedDefinitionEN: generated.definitionEN,
                    existingSenses: duplicateSenses.map {
                        EncounterSenseCandidate(
                            id: $0.id,
                            translationZH: $0.translationZH,
                            definitionEN: $0.definitionEN,
                            exampleSentence: $0.exampleSentence
                        )
                    }
                )
            )
            duplicateSenseRecommendation = recommendation
            duplicateSenseChoice = recommendation.decision == .newSense
                ? .newSense
                : recommendation.matchingSenseID.map { .existing($0) }
        } catch is CancellationError {
            return
        } catch {
            duplicateSenseMatchNotice = "暂时无法判断词义，已保留当前选择，请确认后保存。"
        }
    }

    func duplicateContextDidChange() {
        guard phase == .duplicate, !isMatchingDuplicateSense else { return }
        duplicateSenseRecommendation = nil
        duplicateSenseMatchNotice = context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "没有原句，已保留当前词义选择。"
            : "原句已变化，可以用 AI 重新匹配，也可以直接手动选择。"
    }

    func toggleTag(_ tag: Tag) {
        if selectedTagIDs.contains(tag.id) {
            selectedTagIDs.remove(tag.id)
        } else {
            selectedTagIDs.insert(tag.id)
        }
    }

    private func apply(_ result: VocabularyGenerationResult) {
        term = result.term
        languageCode = result.languageCode
        pronunciationIPA = result.pronunciationIPA
        translationZH = result.translationZH
        definitionEN = result.definitionEN
        exampleSentence = result.exampleSentence
        memoryInsight = result.memoryInsight

        let suggestions = Set(result.suggestedTags.map(Self.normalizedTagName))
        selectedTagIDs = Set(
            availableTags
                .filter { suggestions.contains(Self.normalizedTagName($0.name)) }
                .map(\.id)
        )
    }

    private func presentDuplicate(
        _ card: VocabularyCard,
        generated: VocabularyGenerationResult?
    ) async throws {
        duplicateCard = card
        duplicateCandidate = generated
        duplicateCandidateContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        duplicateReviewState = try await reviewStateRepository.fetchState(cardID: card.id)
        duplicateSenses = try await vocabularySenseRepository?.fetchSenses(cardID: card.id) ?? []
        let defaultSense = duplicateSenses.first(where: \.isPrimary) ?? duplicateSenses.first
        duplicateSenseChoice = defaultSense.map { .existing($0.id) }
        duplicateSenseRecommendation = nil
        duplicateSenseMatchNotice = nil
        phase = .duplicate

        let cleanContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard generated != nil,
              !cleanContext.isEmpty,
              !duplicateSenses.isEmpty else {
            if cleanContext.isEmpty {
                duplicateSenseMatchNotice = "没有原句，已默认选择主词义；你仍可以手动改选。"
            }
            return
        }

        await matchDuplicateSense()
    }

    private func currentCandidate() -> VocabularyGenerationResult {
        VocabularyGenerationResult(
            term: term,
            languageCode: languageCode,
            pronunciationIPA: pronunciationIPA,
            translationZH: translationZH,
            definitionEN: definitionEN,
            exampleSentence: exampleSentence,
            memoryInsight: memoryInsight ?? MemoryInsight(
                strategy: .directAssociation,
                titleZH: "语义联想",
                cueZH: "把这个含义和当前语境直接联系起来。",
                mnemonic: exampleSentence
            ),
            suggestedTags: ["Other"]
        )
    }

    private static func normalizedTagName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    private func userMessage(for error: Error) -> String {
        if let validationError = error as? TermValidationError {
            switch validationError {
            case .empty:
                return "请输入单词或短语。"
            case let .tooLong(maximum):
                return "词条不能超过 \(maximum) 个字符。"
            }
        }
        if let providerError = error as? AIProviderError {
            return providerError.localizedDescription
        }
        return "操作失败：\(error.localizedDescription)"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
