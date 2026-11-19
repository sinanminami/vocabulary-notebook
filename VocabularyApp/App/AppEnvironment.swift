import Foundation
import Observation
import VocabularyAI
import VocabularyCore
import VocabularyPersistence

@MainActor
@Observable
final class AppEnvironment {
    let database: AppDatabase?
    let vocabularyRepository: (any VocabularyRepository)?
    let vocabularySenseRepository: (any VocabularySenseRepository)?
    let reviewStateRepository: (any ReviewStateRepository)?
    let reviewSessionRepository: (any ReviewSessionRepository)?
    let senseReviewRepository: (any SenseReviewRepository)?
    let tagRepository: (any TagRepository)?
    let appSettingsRepository: (any AppSettingsRepository)?
    let reminderManager: ReviewReminderManager?
    let aiProvider: any AIProvider
    let apiKeyStore: any APIKeyStore
    private(set) var startupErrorMessage: String?

    private init(
        database: AppDatabase?,
        vocabularyRepository: (any VocabularyRepository)?,
        vocabularySenseRepository: (any VocabularySenseRepository)?,
        reviewStateRepository: (any ReviewStateRepository)?,
        reviewSessionRepository: (any ReviewSessionRepository)?,
        senseReviewRepository: (any SenseReviewRepository)?,
        tagRepository: (any TagRepository)?,
        appSettingsRepository: (any AppSettingsRepository)?,
        reminderManager: ReviewReminderManager?,
        aiProvider: any AIProvider,
        apiKeyStore: any APIKeyStore,
        startupErrorMessage: String?
    ) {
        self.database = database
        self.vocabularyRepository = vocabularyRepository
        self.vocabularySenseRepository = vocabularySenseRepository
        self.reviewStateRepository = reviewStateRepository
        self.reviewSessionRepository = reviewSessionRepository
        self.senseReviewRepository = senseReviewRepository
        self.tagRepository = tagRepository
        self.appSettingsRepository = appSettingsRepository
        self.reminderManager = reminderManager
        self.aiProvider = aiProvider
        self.apiKeyStore = apiKeyStore
        self.startupErrorMessage = startupErrorMessage
    }

    static func live() -> AppEnvironment {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.wordnotebook.VocabularyApp"
        let apiKeyStore = KeychainAPIKeyStore(service: bundleIdentifier)
        let aiProvider = GeminiInteractionsProvider(apiKeyStore: apiKeyStore)
        do {
            let database = try AppDatabase.live(bundleIdentifier: bundleIdentifier)
            let reviewRepository = GRDBReviewStateRepository(database: database)
            let settingsRepository = GRDBAppSettingsRepository(database: database)
            let senseReviewRepository = GRDBSenseReviewRepository(database: database)
            return AppEnvironment(
                database: database,
                vocabularyRepository: GRDBVocabularyRepository(database: database),
                vocabularySenseRepository: GRDBVocabularySenseRepository(database: database),
                reviewStateRepository: reviewRepository,
                reviewSessionRepository: reviewRepository,
                senseReviewRepository: senseReviewRepository,
                tagRepository: GRDBTagRepository(database: database),
                appSettingsRepository: settingsRepository,
                reminderManager: ReviewReminderManager(
                    settingsRepository: settingsRepository,
                    senseReviewRepository: senseReviewRepository
                ),
                aiProvider: aiProvider,
                apiKeyStore: apiKeyStore,
                startupErrorMessage: nil
            )
        } catch {
            return AppEnvironment(
                database: nil,
                vocabularyRepository: nil,
                vocabularySenseRepository: nil,
                reviewStateRepository: nil,
                reviewSessionRepository: nil,
                senseReviewRepository: nil,
                tagRepository: nil,
                appSettingsRepository: nil,
                reminderManager: nil,
                aiProvider: aiProvider,
                apiKeyStore: apiKeyStore,
                startupErrorMessage: "无法打开本地词库：\(error.localizedDescription)"
            )
        }
    }
}
