import Foundation
import Observation
import VocabularyAI
import VocabularyCore

@MainActor
@Observable
final class AISettingsViewModel {
    var apiKeyInput = ""
    var hasStoredKey = false
    private(set) var isTesting = false
    var statusMessage: String?
    var errorMessage: String?

    private let apiKeyStore: any APIKeyStore
    private let aiProvider: any AIProvider

    init(apiKeyStore: any APIKeyStore, aiProvider: any AIProvider) {
        self.apiKeyStore = apiKeyStore
        self.aiProvider = aiProvider
    }

    func load() {
        do {
            hasStoredKey = try apiKeyStore.read() != nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() {
        statusMessage = nil
        errorMessage = nil
        do {
            try apiKeyStore.save(apiKeyInput)
            apiKeyInput = ""
            hasStoredKey = true
            statusMessage = "Gemini API Key 已安全保存到 macOS Keychain。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete() {
        statusMessage = nil
        errorMessage = nil
        do {
            try apiKeyStore.delete()
            apiKeyInput = ""
            hasStoredKey = false
            statusMessage = "已从 Keychain 删除 API Key。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func testConnection() async {
        guard hasStoredKey, !isTesting else { return }
        isTesting = true
        statusMessage = nil
        errorMessage = nil
        do {
            _ = try await aiProvider.generateVocabularyCard(
                request: VocabularyGenerationRequest(term: "example")
            )
            statusMessage = "Gemini 连接成功，API Key 可以正常生成词卡。"
        } catch {
            errorMessage = "连接测试失败：\(error.localizedDescription)"
        }
        isTesting = false
    }
}
