import Foundation

public struct VocabularyDataHealthReport: Equatable, Sendable {
    public let incompleteCardCount: Int
    public let untaggedCardCount: Int
    public let missingMemoryInsightCount: Int
    public let missingPronunciationCount: Int

    public init(
        incompleteCardCount: Int,
        untaggedCardCount: Int,
        missingMemoryInsightCount: Int,
        missingPronunciationCount: Int
    ) {
        self.incompleteCardCount = incompleteCardCount
        self.untaggedCardCount = untaggedCardCount
        self.missingMemoryInsightCount = missingMemoryInsightCount
        self.missingPronunciationCount = missingPronunciationCount
    }
}

public struct VocabularyExportService: Sendable {
    private let masteryPolicy = MasteryPolicy()

    public init() {}

    public func healthReport(
        cards: [VocabularyCard],
        tagIDsByCardID: [UUID: Set<UUID>]
    ) -> VocabularyDataHealthReport {
        let incomplete = cards.filter {
            $0.translationZH.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.definitionEN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        let untagged = cards.filter { tagIDsByCardID[$0.id, default: []].isEmpty }.count
        let missingMemoryInsight = cards.filter { $0.memoryInsight == nil }.count
        let missingPronunciation = cards.filter {
            $0.pronunciationIPA.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        return VocabularyDataHealthReport(
            incompleteCardCount: incomplete,
            untaggedCardCount: untagged,
            missingMemoryInsightCount: missingMemoryInsight,
            missingPronunciationCount: missingPronunciation
        )
    }

    public func csvData(
        cards: [VocabularyCard],
        tags: [Tag],
        tagIDsByCardID: [UUID: Set<UUID>],
        reviewStates: [ReviewState]
    ) -> Data {
        let tagsByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        let statesByCardID = Dictionary(uniqueKeysWithValues: reviewStates.map { ($0.cardID, $0) })
        let header = [
            "id", "term", "language", "pronunciation_ipa", "translation_zh", "definition_en",
            "example_sentence", "tags", "mastery", "encounter_count",
            "memory_strategy", "memory_title_zh", "memory_breakdown", "memory_cue_zh",
            "memory_mnemonic", "memory_contrast_note_zh", "memory_feedback",
            "created_at", "updated_at", "last_encountered_at", "last_reviewed_at", "next_review_at"
        ]
        var rows = [header]
        rows.append(contentsOf: cards.map { card in
            let state = statesByCardID[card.id]
            let mastery = state.map(masteryPolicy.level(for:)) ?? .new
            let tagNames = tagIDsByCardID[card.id, default: []]
                .compactMap { tagsByID[$0]?.name }
                .sorted()
                .joined(separator: " | ")
            return [
                card.id.uuidString.lowercased(),
                card.term,
                card.languageCode.rawValue,
                card.pronunciationIPA,
                card.translationZH,
                card.definitionEN,
                card.exampleSentence,
                tagNames,
                mastery.rawValue,
                String(card.encounterCount),
                card.memoryInsight?.strategy.rawValue ?? "",
                card.memoryInsight?.titleZH ?? "",
                card.memoryInsight?.breakdown ?? "",
                card.memoryInsight?.cueZH ?? "",
                card.memoryInsight?.mnemonic ?? "",
                card.memoryInsight?.contrastNoteZH ?? "",
                card.memoryInsightFeedback?.rawValue ?? "",
                Self.timestamp(card.createdAt),
                Self.timestamp(card.updatedAt),
                Self.timestamp(card.lastEncounteredAt),
                state?.lastReviewedAt.map(Self.timestamp) ?? "",
                state.map { Self.timestamp($0.dueAt) } ?? ""
            ]
        })
        let csv = rows
            .map { $0.map(Self.escape).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
        return Data(csv.utf8)
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"")
                || value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
