import Foundation
import Observation
import VocabularyCore

@MainActor
@Observable
final class EditWordViewModel {
    let cardID: UUID
    var term: String
    var languageCode: LanguageCode
    var pronunciationIPA: String
    var translationZH: String
    var definitionEN: String
    var exampleSentence: String
    var memoryInsight: MemoryInsight?
    let availableTags: [Tag]
    var selectedTagIDs: Set<UUID>
    private(set) var isSaving = false
    private(set) var isGenerating = false
    private(set) var didFinish = false
    var errorMessage: String?

    private let vocabularyRepository: any VocabularyRepository
    private let aiProvider: any AIProvider

    init(
        card: VocabularyCard,
        availableTags: [Tag],
        selectedTagIDs: Set<UUID>,
        vocabularyRepository: any VocabularyRepository,
        aiProvider: any AIProvider
    ) {
        cardID = card.id
        term = card.term
        languageCode = card.languageCode
        pronunciationIPA = card.pronunciationIPA
        translationZH = card.translationZH
        definitionEN = card.definitionEN
        exampleSentence = card.exampleSentence
        memoryInsight = card.memoryInsight
        self.availableTags = availableTags
        self.selectedTagIDs = selectedTagIDs
        self.vocabularyRepository = vocabularyRepository
        self.aiProvider = aiProvider
    }

    var isFormValid: Bool {
        !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !translationZH.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !definitionEN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (memoryInsight.map { (try? $0.validated()) != nil } ?? true)
    }

    func toggleTag(_ tag: Tag) {
        if selectedTagIDs.contains(tag.id) {
            selectedTagIDs.remove(tag.id)
        } else {
            selectedTagIDs.insert(tag.id)
        }
    }

    func save() async {
        guard isFormValid, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        do {
            _ = try await vocabularyRepository.update(
                id: cardID,
                changes: VocabularyCardChanges(
                    term: term,
                    languageCode: languageCode,
                    pronunciationIPA: pronunciationIPA.trimmingCharacters(in: .whitespacesAndNewlines),
                    translationZH: translationZH.trimmingCharacters(in: .whitespacesAndNewlines),
                    definitionEN: definitionEN.trimmingCharacters(in: .whitespacesAndNewlines),
                    exampleSentence: exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines),
                    memoryInsight: memoryInsight,
                    tagIDs: selectedTagIDs
                ),
                at: Date()
            )
            didFinish = true
        } catch let VocabularyRepositoryError.duplicate(existingCardID) {
            errorMessage = "同一语言中已有这个词条（\(existingCardID.uuidString.prefix(8))…）。"
        } catch {
            errorMessage = "无法保存修改：\(error.localizedDescription)"
        }
        isSaving = false
    }

    func regenerate() async {
        guard !isSaving, !isGenerating,
              !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isGenerating = true
        errorMessage = nil
        do {
            let result = try await aiProvider.generateVocabularyCard(
                request: VocabularyGenerationRequest(term: term)
            )
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
        } catch {
            errorMessage = "AI 重新生成失败：\(error.localizedDescription)"
        }
        isGenerating = false
    }

    private static func normalizedTagName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
}
