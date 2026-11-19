import Foundation
import Testing
import VocabularyCore
@testable import VocabularyAI

@Suite("Gemini vocabulary generation")
struct GeminiInteractionsProviderTests {
    @Test("Decodes a structured vocabulary card")
    func decodesStructuredCard() async throws {
        let generatedJSON = #"{"term":"meticulously","language":"en","pronunciation_ipa":"/məˈtɪkjələsli/","translation_zh":"一丝不苟地；非常仔细地","definition_en":"in a very careful and detailed way","example_sentence":"The researchers meticulously evaluated every stage of the experiment.","memory_insight":{"strategy":"context","title_zh":"动作画面","breakdown":"","cue_zh":"想象研究者逐项检查每个细节。","mnemonic":"Check every detail meticulously.","contrast_note_zh":""},"suggested_tags":["Academic / Paper"]}"#
        let responseJSON = #"{"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":\#(jsonStringLiteral(generatedJSON))}]}]}"#
        let provider = GeminiInteractionsProvider(
            apiKeyStore: FixedAPIKeyStore(value: "gemini-test-key"),
            httpClient: FixedHTTPClient(data: Data(responseJSON.utf8), statusCode: 200)
        )

        let result = try await provider.generateVocabularyCard(
            request: VocabularyGenerationRequest(term: " meticulously ")
        )

        #expect(result.term == "meticulously")
        #expect(result.languageCode == .english)
        #expect(result.pronunciationIPA == "/məˈtɪkjələsli/")
        #expect(result.translationZH == "一丝不苟地；非常仔细地")
        #expect(result.memoryInsight.strategy == .context)
        #expect(result.memoryInsight.breakdown == nil)
        #expect(result.suggestedTags == ["Academic / Paper"])
    }

    @Test("Builds a Gemini structured-output request without storage")
    func buildsStructuredRequest() throws {
        let data = try GeminiRequestBuilder().body(
            model: "test-model",
            request: VocabularyGenerationRequest(
                term: "normalization",
                context: "Features have different scales."
            )
        )
        let payload = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let format = try #require(payload["response_format"] as? [String: Any])
        let schema = try #require(format["schema"] as? [String: Any])
        let input = try #require(payload["input"] as? String)

        #expect(payload["model"] as? String == "test-model")
        #expect(payload["store"] as? Bool == false)
        #expect(format["type"] as? String == "text")
        #expect(format["mime_type"] as? String == "application/json")
        #expect(schema["additionalProperties"] as? Bool == false)
        #expect(input.contains("Features have different scales."))
        #expect(input.contains("Never invent a root"))
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect(properties["memory_insight"] != nil)
        #expect(properties["pronunciation_ipa"] != nil)
    }

    @Test("Authenticates with the Gemini header without Authorization")
    func usesGeminiAuthenticationHeader() async throws {
        let generatedJSON = #"{"term":"trajectory","language":"en","pronunciation_ipa":"/trəˈdʒektəri/","translation_zh":"轨迹","definition_en":"the path followed by something","example_sentence":"The metric followed a rising trajectory.","memory_insight":{"strategy":"imagery","title_zh":"轨迹画面","breakdown":"","cue_zh":"想象图表上向上延伸的一条线。","mnemonic":"Picture its rising trajectory.","contrast_note_zh":""},"suggested_tags":["Data Analysis"]}"#
        let responseJSON = #"{"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":\#(jsonStringLiteral(generatedJSON))}]}]}"#
        let httpClient = CapturingHTTPClient(
            data: Data(responseJSON.utf8),
            statusCode: 200
        )
        let provider = GeminiInteractionsProvider(
            apiKeyStore: FixedAPIKeyStore(value: "gemini-test-key"),
            httpClient: httpClient
        )

        _ = try await provider.generateVocabularyCard(
            request: VocabularyGenerationRequest(term: "trajectory")
        )
        let request = try #require(await httpClient.capturedRequest())

        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "gemini-test-key")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/interactions")
    }

    @Test("Rejects schema-valid JSON with incomplete product fields")
    func validatesProductFields() throws {
        let incomplete = VocabularyGenerationResult(
            term: "trajectory",
            languageCode: .english,
            pronunciationIPA: "/trəˈdʒektəri/",
            translationZH: "轨迹",
            definitionEN: "a path followed by something",
            exampleSentence: "The metric followed a rising trajectory.",
            memoryInsight: MemoryInsight(
                strategy: .context,
                titleZH: "语境记忆",
                cueZH: "把单词放回原句中理解。",
                mnemonic: "Follow the trajectory."
            ),
            suggestedTags: []
        )

        #expect(throws: AIProviderError.schemaValidationFailed) {
            try incomplete.validated()
        }
    }

    @Test("Reports a missing Keychain credential before network access")
    func missingAPIKey() async throws {
        let provider = GeminiInteractionsProvider(
            apiKeyStore: FixedAPIKeyStore(value: nil),
            httpClient: FixedHTTPClient(data: Data(), statusCode: 500)
        )

        do {
            _ = try await provider.generateVocabularyCard(
                request: VocabularyGenerationRequest(term: "trajectory")
            )
            Issue.record("Expected a missing API key error")
        } catch {
            #expect(error as? AIProviderError == .missingAPIKey)
        }
    }

    @Test("Maps authentication and rate limit responses")
    func mapsHTTPFailures() async throws {
        let cases: [(Int, Data, AIProviderError)] = [
            (403, Data(), .invalidAPIKey),
            (429, Data(), .rateLimited),
            (
                400,
                Data(#"{"error":{"message":"API key not valid. Please pass a valid API key."}}"#.utf8),
                .invalidAPIKey
            )
        ]

        for (statusCode, data, expectedError) in cases {
            let provider = GeminiInteractionsProvider(
                apiKeyStore: FixedAPIKeyStore(value: "gemini-test-key"),
                httpClient: FixedHTTPClient(data: data, statusCode: statusCode),
                retryDelays: []
            )
            do {
                _ = try await provider.generateVocabularyCard(
                    request: VocabularyGenerationRequest(term: "trajectory")
                )
                Issue.record("Expected HTTP status mapping")
            } catch {
                #expect(error as? AIProviderError == expectedError)
            }
        }
    }

    @Test("Retries transient failures and then succeeds")
    func retriesTransientFailures() async throws {
        let generatedJSON = #"{"term":"example","language":"en","pronunciation_ipa":"/ɪɡˈzæmpəl/","translation_zh":"例子","definition_en":"something that shows what a thing is like","example_sentence":"This example explains the method clearly.","memory_insight":{"strategy":"direct_association","title_zh":"直接联想","breakdown":"","cue_zh":"把它和展示方法的具体事物联系起来。","mnemonic":"This example makes it clear.","contrast_note_zh":""},"suggested_tags":["Academic / Paper"]}"#
        let responseJSON = #"{"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":\#(jsonStringLiteral(generatedJSON))}]}]}"#
        let client = SequencedHTTPClient(steps: [
            .failure,
            .response(statusCode: 503, data: Data()),
            .response(statusCode: 200, data: Data(responseJSON.utf8))
        ])
        let provider = GeminiInteractionsProvider(
            apiKeyStore: FixedAPIKeyStore(value: "gemini-test-key"),
            httpClient: client,
            retryDelays: [.zero, .zero]
        )

        let result = try await provider.generateVocabularyCard(
            request: VocabularyGenerationRequest(term: "example")
        )

        #expect(result.term == "example")
        #expect(await client.requestCount() == 3)
    }

    @Test("Generates a different reliable memory strategy on request")
    func generatesAlternateMemoryInsight() async throws {
        let generatedJSON = #"{"strategy":"contrast","title_zh":"易混辨析","breakdown":"","cue_zh":"considerable 表示大到值得注意。","mnemonic":"A considerable problem is big enough to consider.","contrast_note_zh":"不要和 considerate（体贴的）混淆。"}"#
        let responseJSON = #"{"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":\#(jsonStringLiteral(generatedJSON))}]}]}"#
        let client = CapturingHTTPClient(
            data: Data(responseJSON.utf8),
            statusCode: 200
        )
        let provider = GeminiInteractionsProvider(
            apiKeyStore: FixedAPIKeyStore(value: "gemini-test-key"),
            httpClient: client
        )

        let insight = try await provider.generateMemoryInsight(
            request: MemoryInsightGenerationRequest(
                term: "considerable",
                languageCode: .english,
                translationZH: "相当大的；可观的",
                definitionEN: "large enough to deserve attention",
                exampleSentence: "The project requires considerable investment.",
                excludedStrategy: .morphology
            )
        )

        #expect(insight.strategy == .contrast)
        #expect(insight.contrastNoteZH?.contains("considerate") == true)
        let request = try #require(await client.capturedRequest())
        let body = try #require(request.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let prompt = try #require(payload["input"] as? String)
        #expect(prompt.contains("Do not use the previous strategy 'morphology'"))
        #expect(prompt.contains("Never invent roots"))
    }

    @Test("Generates a standalone IPA pronunciation for an existing card")
    func generatesStandalonePronunciation() async throws {
        let generatedJSON = #"{"pronunciation_ipa":"/kənˈsɪdərəbəl/"}"#
        let responseJSON = #"{"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":\#(jsonStringLiteral(generatedJSON))}]}]}"#
        let provider = GeminiInteractionsProvider(
            apiKeyStore: FixedAPIKeyStore(value: "gemini-test-key"),
            httpClient: FixedHTTPClient(data: Data(responseJSON.utf8), statusCode: 200)
        )

        let pronunciation = try await provider.generatePronunciationIPA(
            request: PronunciationGenerationRequest(
                term: "considerable",
                languageCode: .english
            )
        )

        #expect(pronunciation == "/kənˈsɪdərəbəl/")
    }

    @Test("Matches a repeated encounter to an existing saved meaning")
    func matchesExistingEncounterSense() async throws {
        let senseID = UUID(uuidString: "27f62f9e-074b-42aa-89e0-1f2b3f6ce5f3")!
        let generatedJSON = #"{"decision":"existing","matching_sense_id":"27f62f9e-074b-42aa-89e0-1f2b3f6ce5f3","reason_zh":"原句仍表示数量大到值得注意。"}"#
        let responseJSON = #"{"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":\#(jsonStringLiteral(generatedJSON))}]}]}"#
        let client = CapturingHTTPClient(data: Data(responseJSON.utf8), statusCode: 200)
        let provider = GeminiInteractionsProvider(
            apiKeyStore: FixedAPIKeyStore(value: "gemini-test-key"),
            httpClient: client
        )

        let result = try await provider.matchEncounterSense(
            request: EncounterSenseMatchRequest(
                term: "considerable",
                languageCode: .english,
                context: "The change produced a considerable improvement.",
                generatedTranslationZH: "相当大的",
                generatedDefinitionEN: "large enough to be noticeable",
                existingSenses: [
                    EncounterSenseCandidate(
                        id: senseID,
                        translationZH: "相当大的；可观的",
                        definitionEN: "large enough to deserve attention",
                        exampleSentence: "The project requires considerable investment."
                    )
                ]
            )
        )

        #expect(result.decision == .existing)
        #expect(result.matchingSenseID == senseID)
        let request = try #require(await client.capturedRequest())
        let body = try #require(request.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["store"] as? Bool == false)
        #expect((payload["input"] as? String)?.contains("only a recommendation") == true)
    }

    @Test("Rejects an existing-sense answer with an unknown ID")
    func rejectsUnknownEncounterSense() async throws {
        let savedSenseID = UUID(uuidString: "27f62f9e-074b-42aa-89e0-1f2b3f6ce5f3")!
        let generatedJSON = #"{"decision":"existing","matching_sense_id":"59f680c7-5365-4748-8c5b-60eb506421f8","reason_zh":"这是已有词义。"}"#
        let responseJSON = #"{"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":\#(jsonStringLiteral(generatedJSON))}]}]}"#
        let provider = GeminiInteractionsProvider(
            apiKeyStore: FixedAPIKeyStore(value: "gemini-test-key"),
            httpClient: FixedHTTPClient(data: Data(responseJSON.utf8), statusCode: 200)
        )

        do {
            _ = try await provider.matchEncounterSense(
                request: EncounterSenseMatchRequest(
                    term: "scale",
                    languageCode: .english,
                    context: "The fish has a silver scale.",
                    generatedTranslationZH: "鳞片",
                    generatedDefinitionEN: "one of the small plates covering a fish",
                    existingSenses: [
                        EncounterSenseCandidate(
                            id: savedSenseID,
                            translationZH: "规模",
                            definitionEN: "the size or extent of something",
                            exampleSentence: "The system operates at scale."
                        )
                    ]
                )
            )
            Issue.record("Expected an unknown sense ID to fail validation")
        } catch {
            #expect(error as? AIProviderError == .schemaValidationFailed)
        }
    }

    private func jsonStringLiteral(_ value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [value])
        let arrayLiteral = String(decoding: data, as: UTF8.self)
        return String(arrayLiteral.dropFirst().dropLast())
    }
}

private struct FixedAPIKeyStore: APIKeyStore {
    let value: String?

    func read() throws -> String? { value }
    func save(_ apiKey: String) throws {}
    func delete() throws {}
}

private struct FixedHTTPClient: HTTPClient {
    let response: HTTPClientResponse

    init(data: Data, statusCode: Int) {
        response = HTTPClientResponse(data: data, statusCode: statusCode)
    }

    func send(_ request: URLRequest) async throws -> HTTPClientResponse {
        response
    }
}

private actor CapturingHTTPClient: HTTPClient {
    private let response: HTTPClientResponse
    private var request: URLRequest?

    init(data: Data, statusCode: Int) {
        response = HTTPClientResponse(data: data, statusCode: statusCode)
    }

    func send(_ request: URLRequest) async throws -> HTTPClientResponse {
        self.request = request
        return response
    }

    func capturedRequest() -> URLRequest? {
        request
    }
}

private actor SequencedHTTPClient: HTTPClient {
    enum Step: Sendable {
        case failure
        case response(statusCode: Int, data: Data)
    }

    private var steps: [Step]
    private var count = 0

    init(steps: [Step]) {
        self.steps = steps
    }

    func send(_ request: URLRequest) async throws -> HTTPClientResponse {
        count += 1
        guard !steps.isEmpty else { throw TestTransportError.failed }
        switch steps.removeFirst() {
        case .failure:
            throw TestTransportError.failed
        case let .response(statusCode, data):
            return HTTPClientResponse(data: data, statusCode: statusCode)
        }
    }

    func requestCount() -> Int { count }
}

private enum TestTransportError: Error {
    case failed
}
