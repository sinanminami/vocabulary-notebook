import Foundation
import VocabularyCore

public final class GeminiInteractionsProvider: AIProvider, @unchecked Sendable {
    public static let defaultModel = "gemini-3.5-flash-lite"

    private let apiKeyStore: any APIKeyStore
    private let httpClient: any HTTPClient
    private let model: String
    private let endpoint: URL
    private let requestBuilder: GeminiRequestBuilder
    private let responseDecoder: GeminiResponseDecoder
    private let retryDelays: [Duration]

    public init(
        apiKeyStore: any APIKeyStore,
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        model: String = GeminiInteractionsProvider.defaultModel,
        endpoint: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!,
        retryDelays: [Duration] = [.milliseconds(400), .milliseconds(1_200)]
    ) {
        self.apiKeyStore = apiKeyStore
        self.httpClient = httpClient
        self.model = model
        self.endpoint = endpoint
        self.retryDelays = retryDelays
        requestBuilder = GeminiRequestBuilder()
        responseDecoder = GeminiResponseDecoder()
    }

    public func generateVocabularyCard(
        request: VocabularyGenerationRequest
    ) async throws -> VocabularyGenerationResult {
        let term: String
        do {
            term = try TermNormalizer().displayTerm(request.term)
        } catch {
            throw AIProviderError.invalidInput
        }

        let body = try requestBuilder.body(
            model: model,
            request: VocabularyGenerationRequest(term: term, context: request.context)
        )
        let data = try await performRequest(body: body)
        return try responseDecoder.decode(data).validated()
    }

    public func generateMemoryInsight(
        request: MemoryInsightGenerationRequest
    ) async throws -> MemoryInsight {
        let term: String
        do {
            term = try TermNormalizer().displayTerm(request.term)
        } catch {
            throw AIProviderError.invalidInput
        }
        let cleanRequest = MemoryInsightGenerationRequest(
            term: term,
            languageCode: request.languageCode,
            translationZH: request.translationZH,
            definitionEN: request.definitionEN,
            exampleSentence: request.exampleSentence,
            excludedStrategy: request.excludedStrategy
        )
        let body = try GeminiMemoryInsightRequestBuilder().body(
            model: model,
            request: cleanRequest
        )
        let data = try await performRequest(body: body)
        return try responseDecoder.decodeMemoryInsight(data).validated()
    }

    public func generatePronunciationIPA(
        request: PronunciationGenerationRequest
    ) async throws -> String {
        let term: String
        do {
            term = try TermNormalizer().displayTerm(request.term)
        } catch {
            throw AIProviderError.invalidInput
        }
        let body = try GeminiPronunciationRequestBuilder().body(
            model: model,
            request: PronunciationGenerationRequest(
                term: term,
                languageCode: request.languageCode
            )
        )
        let data = try await performRequest(body: body)
        return try responseDecoder.decodePronunciationIPA(data)
    }

    public func matchEncounterSense(
        request: EncounterSenseMatchRequest
    ) async throws -> EncounterSenseMatchResult {
        guard !request.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.existingSenses.isEmpty else {
            throw AIProviderError.invalidInput
        }
        let body = try GeminiEncounterSenseRequestBuilder().body(model: model, request: request)
        let data = try await performRequest(body: body)
        return try responseDecoder.decodeEncounterSenseMatch(
            data,
            availableSenseIDs: Set(request.existingSenses.map(\.id))
        )
    }

    private func performRequest(body: Data) async throws -> Data {
        guard let storedKey = try apiKeyStore.read() else {
            throw AIProviderError.missingAPIKey
        }
        let apiKey = storedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw AIProviderError.missingAPIKey
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 30
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = body

        for attempt in 0...retryDelays.count {
            let response: HTTPClientResponse
            do {
                response = try await httpClient.send(urlRequest)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if attempt < retryDelays.count {
                    try await Task.sleep(for: retryDelays[attempt])
                    continue
                }
                throw AIProviderError.network(error.localizedDescription)
            }

            if Self.isTransient(statusCode: response.statusCode),
               attempt < retryDelays.count {
                try await Task.sleep(for: retryDelays[attempt])
                continue
            }

            let errorMessage = responseDecoder.decodeErrorMessage(response.data)
            switch response.statusCode {
            case 200..<300:
                return response.data
            case 401, 403:
                throw AIProviderError.invalidAPIKey
            case 400 where errorMessage?.localizedCaseInsensitiveContains("api key") == true:
                throw AIProviderError.invalidAPIKey
            case 429:
                throw AIProviderError.rateLimited
            default:
                throw AIProviderError.server(
                    statusCode: response.statusCode,
                    message: errorMessage
                )
            }
        }

        throw AIProviderError.invalidResponse
    }

    private static func isTransient(statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
    }
}

struct GeminiRequestBuilder: Sendable {
    private static let defaultTags = [
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

    func body(model: String, request: VocabularyGenerationRequest) throws -> Data {
        let context = request.context?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let contextLine = context.flatMap { $0.isEmpty ? nil : $0 }
            .map { "\nContext for the example sentence only: \($0)" } ?? ""

        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "term": [
                    "type": "string",
                    "description": "The clean display form of the supplied word or phrase."
                ],
                "language": [
                    "type": "string",
                    "description": "A lowercase BCP-47 language code, usually en or ja."
                ],
                "pronunciation_ipa": [
                    "type": "string",
                    "description": "A standard IPA pronunciation including forward slashes, using the most common dictionary form."
                ],
                "translation_zh": [
                    "type": "string",
                    "description": "A concise, natural Simplified Chinese translation."
                ],
                "definition_en": [
                    "type": "string",
                    "description": "A simple, natural English definition."
                ],
                "example_sentence": [
                    "type": "string",
                    "description": "One natural example sentence."
                ],
                "memory_insight": Self.memoryInsightSchema,
                "suggested_tags": [
                    "type": "array",
                    "items": ["type": "string", "enum": Self.defaultTags],
                    "minItems": 1,
                    "maxItems": 3
                ]
            ],
            "required": [
                "term",
                "language",
                "pronunciation_ipa",
                "translation_zh",
                "definition_en",
                "example_sentence",
                "memory_insight",
                "suggested_tags"
            ]
        ]

        let prompt = """
        Generate one concise vocabulary learning card. Detect the term's language. Write a natural \
        Simplified Chinese translation, a standard IPA pronunciation in forward slashes, a simple \
        English definition, and one example suited to data \
        analysis, academic, statistics, machine learning, product analysis, or work contexts when \
        natural. Recommend 1 to 3 tags only. Also choose exactly one best memory strategy and create \
        a short memory insight in Simplified Chinese, with an English mnemonic/example when useful.

        Reliability rules for the memory insight:
        - Never force a prefix/root/suffix analysis when the modern structure is not transparent.
        - Never invent a root, word history, literal origin, or etymology.
        - Use morphology only when the segmentation and meaning connection are reliable.
        - Prefer word-family contrast, a semantic bridge, context, sound/spelling, imagery, or a \
          direct association when those are more useful.
        - Do not present uncertain historical etymology as fact.
        - The cue_zh should avoid repeating the target term so it can work as a recall hint.
        - Keep each field compact. Use an empty string for breakdown or contrast_note_zh when irrelevant.

        Term or phrase: \(request.term)\(contextLine)
        """

        let payload: [String: Any] = [
            "model": model,
            "store": false,
            "input": prompt,
            "response_format": [
                "type": "text",
                "mime_type": "application/json",
                "schema": schema
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    static var memoryInsightSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "strategy": [
                    "type": "string",
                    "enum": MemoryStrategy.allCases.map(\.rawValue)
                ],
                "title_zh": [
                    "type": "string",
                    "description": "A compact Chinese title, at most 30 characters."
                ],
                "breakdown": [
                    "type": "string",
                    "description": "A reliable compact decomposition such as consider + -able, or an empty string."
                ],
                "cue_zh": [
                    "type": "string",
                    "description": "One concise Simplified Chinese explanation of the memory logic."
                ],
                "mnemonic": [
                    "type": "string",
                    "description": "One short memorable sentence or association; use English when natural."
                ],
                "contrast_note_zh": [
                    "type": "string",
                    "description": "One useful confusable or word-family contrast in Chinese, or an empty string."
                ]
            ],
            "required": [
                "strategy", "title_zh", "breakdown", "cue_zh", "mnemonic", "contrast_note_zh"
            ]
        ]
    }
}

struct GeminiPronunciationRequestBuilder: Sendable {
    func body(model: String, request: PronunciationGenerationRequest) throws -> Data {
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "pronunciation_ipa": [
                    "type": "string",
                    "description": "The most common dictionary pronunciation in IPA, including forward slashes."
                ]
            ],
            "required": ["pronunciation_ipa"]
        ]
        let prompt = """
        Return only the standard IPA pronunciation for this word or short phrase. Use the most common \
        dictionary pronunciation for language \(request.languageCode.rawValue). Include forward slashes. \
        Do not use respelling, explanatory prose, or multiple regional variants unless the term has no \
        single standard form.

        Term: \(request.term)
        """
        let payload: [String: Any] = [
            "model": model,
            "store": false,
            "input": prompt,
            "response_format": [
                "type": "text",
                "mime_type": "application/json",
                "schema": schema
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
}

struct GeminiMemoryInsightRequestBuilder: Sendable {
    func body(model: String, request: MemoryInsightGenerationRequest) throws -> Data {
        let excluded = request.excludedStrategy.map {
            "Do not use the previous strategy '\($0.rawValue)'; choose a genuinely different useful approach."
        } ?? "Choose the single most useful strategy."
        let prompt = """
        Create one compact memory insight for this vocabulary card.

        Term: \(request.term)
        Language: \(request.languageCode.rawValue)
        Chinese meaning: \(request.translationZH)
        English definition: \(request.definitionEN)
        Example: \(request.exampleSentence)

        \(excluded)
        Write the learning logic in Simplified Chinese and keep the mnemonic/example in the term's \
        language when natural. Never force morphological decomposition. Never invent roots, literal \
        origins, or etymology. Use morphology only when the modern segmentation and meaning link are \
        reliable. If unsure, choose word-family contrast, semantic bridge, context, sound/spelling, \
        imagery, or direct association. The cue_zh should avoid repeating the target term so it can \
        work as a recall hint. Use an empty string for irrelevant optional fields.
        """
        let payload: [String: Any] = [
            "model": model,
            "store": false,
            "input": prompt,
            "response_format": [
                "type": "text",
                "mime_type": "application/json",
                "schema": GeminiRequestBuilder.memoryInsightSchema
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
}

struct GeminiEncounterSenseRequestBuilder: Sendable {
    func body(model: String, request: EncounterSenseMatchRequest) throws -> Data {
        let identifiers = request.existingSenses.map { $0.id.uuidString.lowercased() }
        guard !identifiers.isEmpty else { throw AIProviderError.invalidInput }

        let senses = request.existingSenses.map { sense in
            """
            ID: \(sense.id.uuidString.lowercased())
            Chinese meaning: \(sense.translationZH)
            English definition: \(sense.definitionEN)
            Example: \(sense.exampleSentence)
            """
        }.joined(separator: "\n\n")
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "decision": [
                    "type": "string",
                    "enum": EncounterSenseDecision.allCases.map(\.rawValue)
                ],
                "matching_sense_id": [
                    "type": "string",
                    "enum": identifiers + [""]
                ],
                "reason_zh": [
                    "type": "string",
                    "description": "One short, cautious Simplified Chinese explanation, at most 80 Chinese characters."
                ]
            ],
            "required": ["decision", "matching_sense_id", "reason_zh"]
        ]
        let prompt = """
        Decide whether the highlighted encounter uses one of the saved meanings or probably introduces \
        a genuinely different meaning. Compare semantics, not wording. Prefer an existing meaning when \
        the distinction is only grammar, inflection, register, or a contextual nuance. Choose new_sense \
        only when the meaning itself is materially different. Never invent etymology or unsupported meaning.

        Term: \(request.term)
        Language: \(request.languageCode.rawValue)
        Encounter context: \(request.context)
        Newly generated Chinese meaning: \(request.generatedTranslationZH)
        Newly generated English definition: \(request.generatedDefinitionEN)

        Saved meanings:
        \(senses)

        If decision is existing, return exactly one saved ID. If decision is new_sense, return an empty \
        matching_sense_id. The result is only a recommendation; the user will confirm it.
        """
        let payload: [String: Any] = [
            "model": model,
            "store": false,
            "input": prompt,
            "response_format": [
                "type": "text",
                "mime_type": "application/json",
                "schema": schema
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
}

struct GeminiResponseDecoder: Sendable {
    func decode(_ data: Data) throws -> VocabularyGenerationResult {
        let jsonData = try extractJSONData(data)
        do {
            return try JSONDecoder().decode(VocabularyGenerationResult.self, from: jsonData)
        } catch {
            throw AIProviderError.schemaValidationFailed
        }
    }

    func decodeMemoryInsight(_ data: Data) throws -> MemoryInsight {
        let jsonData = try extractJSONData(data)
        do {
            return try JSONDecoder().decode(MemoryInsight.self, from: jsonData)
        } catch {
            throw AIProviderError.schemaValidationFailed
        }
    }

    func decodePronunciationIPA(_ data: Data) throws -> String {
        let jsonData = try extractJSONData(data)
        do {
            let output = try JSONDecoder().decode(PronunciationOutput.self, from: jsonData)
            let value = output.pronunciationIPA.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 120 else {
                throw AIProviderError.schemaValidationFailed
            }
            return value
        } catch let error as AIProviderError {
            throw error
        } catch {
            throw AIProviderError.schemaValidationFailed
        }
    }

    func decodeEncounterSenseMatch(
        _ data: Data,
        availableSenseIDs: Set<UUID>
    ) throws -> EncounterSenseMatchResult {
        let jsonData = try extractJSONData(data)
        do {
            let output = try JSONDecoder().decode(EncounterSenseMatchOutput.self, from: jsonData)
            let matchingID = output.matchingSenseID.isEmpty
                ? nil
                : UUID(uuidString: output.matchingSenseID)
            return try EncounterSenseMatchResult(
                decision: output.decision,
                matchingSenseID: matchingID,
                reasonZH: output.reasonZH
            ).validated(availableSenseIDs: availableSenseIDs)
        } catch let error as AIProviderError {
            throw error
        } catch {
            throw AIProviderError.schemaValidationFailed
        }
    }

    private func extractJSONData(_ data: Data) throws -> Data {
        let envelope: ResponseEnvelope
        do {
            envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        } catch {
            throw AIProviderError.invalidResponse
        }

        guard envelope.status == nil || envelope.status == "completed",
              let text = envelope.steps
                .filter({ $0.type == "model_output" })
                .compactMap(\.content)
                .flatMap({ $0 })
                .first(where: { $0.type == "text" })?
                .text,
              let jsonData = text.data(using: .utf8) else {
            throw AIProviderError.invalidResponse
        }

        return jsonData
    }

    func decodeErrorMessage(_ data: Data) -> String? {
        try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error.message
    }

    private struct ResponseEnvelope: Decodable {
        let status: String?
        let steps: [Step]
    }

    private struct Step: Decodable {
        let type: String
        let content: [ContentItem]?
    }

    private struct ContentItem: Decodable {
        let type: String
        let text: String?
    }

    private struct ErrorEnvelope: Decodable {
        let error: ErrorBody
    }

    private struct PronunciationOutput: Decodable {
        let pronunciationIPA: String

        enum CodingKeys: String, CodingKey {
            case pronunciationIPA = "pronunciation_ipa"
        }
    }

    private struct EncounterSenseMatchOutput: Decodable {
        let decision: EncounterSenseDecision
        let matchingSenseID: String
        let reasonZH: String

        enum CodingKeys: String, CodingKey {
            case decision
            case matchingSenseID = "matching_sense_id"
            case reasonZH = "reason_zh"
        }
    }

    private struct ErrorBody: Decodable {
        let message: String
    }
}
