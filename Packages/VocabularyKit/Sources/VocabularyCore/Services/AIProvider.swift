import Foundation

public struct VocabularyGenerationRequest: Equatable, Sendable {
    public var term: String
    public var context: String?

    public init(term: String, context: String? = nil) {
        self.term = term
        self.context = context
    }
}

public struct VocabularyGenerationResult: Codable, Equatable, Sendable {
    public var term: String
    public var languageCode: LanguageCode
    public var pronunciationIPA: String
    public var translationZH: String
    public var definitionEN: String
    public var exampleSentence: String
    public var memoryInsight: MemoryInsight
    public var suggestedTags: [String]

    public init(
        term: String,
        languageCode: LanguageCode,
        pronunciationIPA: String,
        translationZH: String,
        definitionEN: String,
        exampleSentence: String,
        memoryInsight: MemoryInsight,
        suggestedTags: [String]
    ) {
        self.term = term
        self.languageCode = languageCode
        self.pronunciationIPA = pronunciationIPA
        self.translationZH = translationZH
        self.definitionEN = definitionEN
        self.exampleSentence = exampleSentence
        self.memoryInsight = memoryInsight
        self.suggestedTags = suggestedTags
    }

    enum CodingKeys: String, CodingKey {
        case term
        case languageCode = "language"
        case pronunciationIPA = "pronunciation_ipa"
        case translationZH = "translation_zh"
        case definitionEN = "definition_en"
        case exampleSentence = "example_sentence"
        case memoryInsight = "memory_insight"
        case suggestedTags = "suggested_tags"
    }

    public func validated() throws -> VocabularyGenerationResult {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPronunciation = pronunciationIPA.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTranslation = translationZH.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDefinition = definitionEN.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExample = exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let validatedMemoryInsight = try memoryInsight.validated()
        let uniqueTags = suggestedTags.reduce(into: [String]()) { result, tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !result.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
                return
            }
            result.append(trimmed)
        }

        guard !trimmedTerm.isEmpty,
              !languageCode.rawValue.isEmpty,
              languageCode != .undetermined,
              !trimmedPronunciation.isEmpty,
              trimmedPronunciation.count <= 120,
              !trimmedTranslation.isEmpty,
              !trimmedDefinition.isEmpty,
              !trimmedExample.isEmpty,
              (1...3).contains(uniqueTags.count) else {
            throw AIProviderError.schemaValidationFailed
        }

        return VocabularyGenerationResult(
            term: trimmedTerm,
            languageCode: languageCode,
            pronunciationIPA: trimmedPronunciation,
            translationZH: trimmedTranslation,
            definitionEN: trimmedDefinition,
            exampleSentence: trimmedExample,
            memoryInsight: validatedMemoryInsight,
            suggestedTags: uniqueTags
        )
    }
}

public struct PronunciationGenerationRequest: Equatable, Sendable {
    public var term: String
    public var languageCode: LanguageCode

    public init(term: String, languageCode: LanguageCode) {
        self.term = term
        self.languageCode = languageCode
    }
}

public struct MemoryInsightGenerationRequest: Equatable, Sendable {
    public var term: String
    public var languageCode: LanguageCode
    public var translationZH: String
    public var definitionEN: String
    public var exampleSentence: String
    public var excludedStrategy: MemoryStrategy?

    public init(
        term: String,
        languageCode: LanguageCode,
        translationZH: String,
        definitionEN: String,
        exampleSentence: String,
        excludedStrategy: MemoryStrategy? = nil
    ) {
        self.term = term
        self.languageCode = languageCode
        self.translationZH = translationZH
        self.definitionEN = definitionEN
        self.exampleSentence = exampleSentence
        self.excludedStrategy = excludedStrategy
    }
}

public struct EncounterSenseCandidate: Equatable, Sendable {
    public let id: UUID
    public var translationZH: String
    public var definitionEN: String
    public var exampleSentence: String

    public init(
        id: UUID,
        translationZH: String,
        definitionEN: String,
        exampleSentence: String
    ) {
        self.id = id
        self.translationZH = translationZH
        self.definitionEN = definitionEN
        self.exampleSentence = exampleSentence
    }
}

public struct EncounterSenseMatchRequest: Equatable, Sendable {
    public var term: String
    public var languageCode: LanguageCode
    public var context: String
    public var generatedTranslationZH: String
    public var generatedDefinitionEN: String
    public var existingSenses: [EncounterSenseCandidate]

    public init(
        term: String,
        languageCode: LanguageCode,
        context: String,
        generatedTranslationZH: String,
        generatedDefinitionEN: String,
        existingSenses: [EncounterSenseCandidate]
    ) {
        self.term = term
        self.languageCode = languageCode
        self.context = context
        self.generatedTranslationZH = generatedTranslationZH
        self.generatedDefinitionEN = generatedDefinitionEN
        self.existingSenses = existingSenses
    }
}

public enum EncounterSenseDecision: String, Codable, CaseIterable, Equatable, Sendable {
    case existing
    case newSense = "new_sense"
}

public struct EncounterSenseMatchResult: Codable, Equatable, Sendable {
    public var decision: EncounterSenseDecision
    public var matchingSenseID: UUID?
    public var reasonZH: String

    public init(
        decision: EncounterSenseDecision,
        matchingSenseID: UUID?,
        reasonZH: String
    ) {
        self.decision = decision
        self.matchingSenseID = matchingSenseID
        self.reasonZH = reasonZH
    }

    enum CodingKeys: String, CodingKey {
        case decision
        case matchingSenseID = "matching_sense_id"
        case reasonZH = "reason_zh"
    }

    public func validated(availableSenseIDs: Set<UUID>) throws -> EncounterSenseMatchResult {
        let reason = reasonZH.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty, reason.count <= 160 else {
            throw AIProviderError.schemaValidationFailed
        }
        switch decision {
        case .existing:
            guard let matchingSenseID, availableSenseIDs.contains(matchingSenseID) else {
                throw AIProviderError.schemaValidationFailed
            }
            return EncounterSenseMatchResult(
                decision: .existing,
                matchingSenseID: matchingSenseID,
                reasonZH: reason
            )
        case .newSense:
            return EncounterSenseMatchResult(
                decision: .newSense,
                matchingSenseID: nil,
                reasonZH: reason
            )
        }
    }
}

public enum AIProviderError: Error, Equatable, Sendable {
    case missingAPIKey
    case invalidAPIKey
    case rateLimited
    case invalidInput
    case network(String)
    case invalidResponse
    case schemaValidationFailed
    case server(statusCode: Int, message: String?)
}

extension AIProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "尚未配置 AI API Key。"
        case .invalidAPIKey:
            "AI API Key 无效。"
        case .rateLimited:
            "AI 请求过于频繁或额度不足。"
        case .invalidInput:
            "请输入有效的单词或短语。"
        case let .network(message):
            "网络请求失败：\(message)"
        case .invalidResponse:
            "AI 返回了无法识别的响应。"
        case .schemaValidationFailed:
            "AI 返回的词卡字段不完整。"
        case let .server(statusCode, message):
            message.map { "AI 服务错误（\(statusCode)）：\($0)" }
                ?? "AI 服务错误（\(statusCode)）。"
        }
    }
}

public protocol AIProvider: Sendable {
    func generateVocabularyCard(
        request: VocabularyGenerationRequest
    ) async throws -> VocabularyGenerationResult

    func generateMemoryInsight(
        request: MemoryInsightGenerationRequest
    ) async throws -> MemoryInsight

    func generatePronunciationIPA(
        request: PronunciationGenerationRequest
    ) async throws -> String

    func matchEncounterSense(
        request: EncounterSenseMatchRequest
    ) async throws -> EncounterSenseMatchResult
}

public extension AIProvider {
    func matchEncounterSense(
        request: EncounterSenseMatchRequest
    ) async throws -> EncounterSenseMatchResult {
        throw AIProviderError.invalidResponse
    }
}
