import Foundation

public struct VocabularySense: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let cardID: UUID
    public var sortOrder: Int
    public var isPrimary: Bool
    public var translationZH: String
    public var definitionEN: String
    public var exampleSentence: String
    public var memoryInsight: MemoryInsight?
    public var memoryInsightFeedback: MemoryInsightFeedback?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        cardID: UUID,
        sortOrder: Int,
        isPrimary: Bool,
        translationZH: String,
        definitionEN: String,
        exampleSentence: String,
        memoryInsight: MemoryInsight? = nil,
        memoryInsightFeedback: MemoryInsightFeedback? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.cardID = cardID
        self.sortOrder = sortOrder
        self.isPrimary = isPrimary
        self.translationZH = translationZH
        self.definitionEN = definitionEN
        self.exampleSentence = exampleSentence
        self.memoryInsight = memoryInsight
        self.memoryInsightFeedback = memoryInsightFeedback
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct NewVocabularySense: Equatable, Sendable {
    public var translationZH: String
    public var definitionEN: String
    public var exampleSentence: String
    public var memoryInsight: MemoryInsight?

    public init(
        translationZH: String,
        definitionEN: String,
        exampleSentence: String,
        memoryInsight: MemoryInsight? = nil
    ) {
        self.translationZH = translationZH
        self.definitionEN = definitionEN
        self.exampleSentence = exampleSentence
        self.memoryInsight = memoryInsight
    }
}

public struct VocabularySenseChanges: Equatable, Sendable {
    public var translationZH: String
    public var definitionEN: String
    public var exampleSentence: String
    public var memoryInsight: MemoryInsight?

    public init(
        translationZH: String,
        definitionEN: String,
        exampleSentence: String,
        memoryInsight: MemoryInsight? = nil
    ) {
        self.translationZH = translationZH
        self.definitionEN = definitionEN
        self.exampleSentence = exampleSentence
        self.memoryInsight = memoryInsight
    }
}
