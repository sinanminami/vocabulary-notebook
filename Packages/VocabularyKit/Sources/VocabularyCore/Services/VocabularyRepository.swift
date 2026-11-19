import Foundation

public enum VocabularyRepositoryError: Error, Equatable, Sendable {
    case duplicate(existingCardID: UUID)
    case cardNotFound(UUID)
    case tagNotFound(UUID)
    case invalidPronunciation
}

extension VocabularyRepositoryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .duplicate: "同一语言中已经存在这个词条。"
        case .cardNotFound: "没有找到这个词条。"
        case .tagNotFound: "没有找到所选标签。"
        case .invalidPronunciation: "音标不能为空或过长。"
        }
    }
}

public enum ReviewSessionRepositoryError: Error, Equatable, Sendable {
    case reviewStateNotFound(UUID)
}

public enum VocabularySenseRepositoryError: Error, Equatable, Sendable {
    case cardNotFound(UUID)
    case senseNotFound(UUID)
    case primarySenseProtected(UUID)
}

extension VocabularySenseRepositoryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .cardNotFound: "没有找到这个词条。"
        case .senseNotFound: "没有找到这个词义。"
        case .primarySenseProtected: "主词义不能直接删除。"
        }
    }
}

public enum SenseReviewRepositoryError: Error, Equatable, Sendable {
    case reviewStateNotFound(UUID)
}

public enum TagRepositoryError: Error, Equatable, Sendable {
    case invalidName
    case duplicateName
    case tagNotFound(UUID)
    case systemTagProtected
}

extension TagRepositoryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidName: "请输入有效的标签名称。"
        case .duplicateName: "已经存在同名标签。"
        case .tagNotFound: "没有找到这个标签。"
        case .systemTagProtected: "默认系统标签不能修改或删除。"
        }
    }
}

public protocol VocabularyRepository: Sendable {
    func create(_ input: NewVocabularyCard, at date: Date) async throws -> VocabularyCard
    func fetchCard(id: UUID) async throws -> VocabularyCard?
    func fetchAll() async throws -> [VocabularyCard]
    func fetchCards(normalizedTerm: String) async throws -> [VocabularyCard]
    func update(id: UUID, changes: VocabularyCardChanges, at date: Date) async throws -> VocabularyCard
    func setMemoryInsight(
        id: UUID,
        insight: MemoryInsight,
        at date: Date
    ) async throws -> VocabularyCard
    func setMemoryInsightFeedback(
        id: UUID,
        feedback: MemoryInsightFeedback?,
        at date: Date
    ) async throws -> VocabularyCard
    func setPronunciationIPA(
        id: UUID,
        pronunciationIPA: String,
        at date: Date
    ) async throws -> VocabularyCard
    func fetchEncounters(cardID: UUID) async throws -> [VocabularyEncounter]
    func fetchEncounters(senseID: UUID) async throws -> [VocabularyEncounter]
    func fetchAllEncounters() async throws -> [VocabularyEncounter]
    func addEncounter(
        id: UUID,
        context: String?,
        sourceApplication: String?,
        at date: Date
    ) async throws -> VocabularyCard
    func addEncounter(
        id: UUID,
        senseID: UUID,
        context: String?,
        sourceApplication: String?,
        at date: Date
    ) async throws -> VocabularyCard
    func addEncounter(id: UUID, at date: Date) async throws -> VocabularyCard
    func delete(id: UUID) async throws
}

public protocol VocabularySenseRepository: Sendable {
    func fetchSense(id: UUID) async throws -> VocabularySense?
    func fetchSenses(cardID: UUID) async throws -> [VocabularySense]
    func fetchAll() async throws -> [VocabularySense]
    func create(
        cardID: UUID,
        input: NewVocabularySense,
        at date: Date
    ) async throws -> VocabularySense
    func update(
        id: UUID,
        changes: VocabularySenseChanges,
        at date: Date
    ) async throws -> VocabularySense
    func setMemoryInsightFeedback(
        id: UUID,
        feedback: MemoryInsightFeedback?,
        at date: Date
    ) async throws -> VocabularySense
    func delete(id: UUID) async throws
}

public protocol SenseReviewRepository: Sendable {
    func fetchState(senseID: UUID) async throws -> ReviewState?
    func fetchAllStates() async throws -> [ReviewState]
    func fetchQueue(at date: Date, newLimit: Int) async throws -> [SenseReviewQueueItem]
    func previews(senseID: UUID, at date: Date) async throws -> [ReviewRatingPreview]
    func recordReview(
        senseID: UUID,
        rating: ReviewRating,
        mode: ReviewMode,
        at date: Date
    ) async throws -> ReviewLogEntry
    func fetchReviewLogs(senseID: UUID?, since date: Date?) async throws -> [ReviewLogEntry]
}

public protocol ReviewStateRepository: Sendable {
    func fetchState(cardID: UUID) async throws -> ReviewState?
    func fetchAll() async throws -> [ReviewState]
}

public protocol ReviewSessionRepository: Sendable {
    func fetchQueue(at date: Date, newLimit: Int) async throws -> [ReviewQueueItem]
    func previews(cardID: UUID, at date: Date) async throws -> [ReviewRatingPreview]
    func recordReview(
        cardID: UUID,
        rating: ReviewRating,
        mode: ReviewMode,
        at date: Date
    ) async throws -> ReviewLogEntry
    func fetchReviewLogs(since date: Date?) async throws -> [ReviewLogEntry]
}

public protocol TagRepository: Sendable {
    func fetchAll() async throws -> [Tag]
    func fetchTagIDsByCardID() async throws -> [UUID: Set<UUID>]
    func create(name: String, at date: Date) async throws -> Tag
    func rename(id: UUID, name: String, at date: Date) async throws -> Tag
    func delete(id: UUID) async throws
}

public protocol AppSettingsRepository: Sendable {
    func fetch() async throws -> AppSettings
    func setDailyNewCardLimit(_ limit: Int, at date: Date) async throws -> AppSettings
    func setReviewReminder(
        enabled: Bool,
        hour: Int,
        minute: Int,
        onlyWhenDue: Bool,
        at date: Date
    ) async throws -> AppSettings
    func setReviewPreferences(
        dailyNewCardLimit: Int,
        remindersEnabled: Bool,
        reminderHour: Int,
        reminderMinute: Int,
        onlyWhenDue: Bool,
        at date: Date
    ) async throws -> AppSettings
}
