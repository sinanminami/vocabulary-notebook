import Foundation

public struct VocabularyCard: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var term: String
    public var normalizedTerm: String
    public var languageCode: LanguageCode
    public var pronunciationIPA: String
    public var translationZH: String
    public var definitionEN: String
    public var exampleSentence: String
    public var memoryInsight: MemoryInsight?
    public var memoryInsightFeedback: MemoryInsightFeedback?
    public var encounterCount: Int
    public let createdAt: Date
    public var updatedAt: Date
    public var lastEncounteredAt: Date

    public init(
        id: UUID,
        term: String,
        normalizedTerm: String,
        languageCode: LanguageCode,
        pronunciationIPA: String = "",
        translationZH: String,
        definitionEN: String,
        exampleSentence: String,
        memoryInsight: MemoryInsight? = nil,
        memoryInsightFeedback: MemoryInsightFeedback? = nil,
        encounterCount: Int,
        createdAt: Date,
        updatedAt: Date,
        lastEncounteredAt: Date
    ) {
        self.id = id
        self.term = term
        self.normalizedTerm = normalizedTerm
        self.languageCode = languageCode
        self.pronunciationIPA = pronunciationIPA
        self.translationZH = translationZH
        self.definitionEN = definitionEN
        self.exampleSentence = exampleSentence
        self.memoryInsight = memoryInsight
        self.memoryInsightFeedback = memoryInsightFeedback
        self.encounterCount = encounterCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastEncounteredAt = lastEncounteredAt
    }
}

public struct NewVocabularyCard: Equatable, Sendable {
    public var term: String
    public var languageCode: LanguageCode
    public var pronunciationIPA: String
    public var translationZH: String
    public var definitionEN: String
    public var exampleSentence: String
    public var memoryInsight: MemoryInsight?
    /// The user-selected source sentence, kept locally as the first encounter.
    public var encounterContext: String?
    public var encounterSourceApplication: String?
    public var tagIDs: Set<UUID>

    public init(
        term: String,
        languageCode: LanguageCode,
        pronunciationIPA: String = "",
        translationZH: String,
        definitionEN: String,
        exampleSentence: String,
        memoryInsight: MemoryInsight? = nil,
        encounterContext: String? = nil,
        encounterSourceApplication: String? = nil,
        tagIDs: Set<UUID> = []
    ) {
        self.term = term
        self.languageCode = languageCode
        self.pronunciationIPA = pronunciationIPA
        self.translationZH = translationZH
        self.definitionEN = definitionEN
        self.exampleSentence = exampleSentence
        self.memoryInsight = memoryInsight
        self.encounterContext = encounterContext
        self.encounterSourceApplication = encounterSourceApplication
        self.tagIDs = tagIDs
    }
}

public struct VocabularyCardChanges: Equatable, Sendable {
    public var term: String
    public var languageCode: LanguageCode
    public var pronunciationIPA: String
    public var translationZH: String
    public var definitionEN: String
    public var exampleSentence: String
    public var memoryInsight: MemoryInsight?
    public var tagIDs: Set<UUID>

    public init(
        term: String,
        languageCode: LanguageCode,
        pronunciationIPA: String = "",
        translationZH: String,
        definitionEN: String,
        exampleSentence: String,
        memoryInsight: MemoryInsight? = nil,
        tagIDs: Set<UUID> = []
    ) {
        self.term = term
        self.languageCode = languageCode
        self.pronunciationIPA = pronunciationIPA
        self.translationZH = translationZH
        self.definitionEN = definitionEN
        self.exampleSentence = exampleSentence
        self.memoryInsight = memoryInsight
        self.tagIDs = tagIDs
    }
}
