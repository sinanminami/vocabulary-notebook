import Foundation
import Observation
import VocabularyCore

@MainActor
@Observable
final class ReviewSessionModel {
    private(set) var queue: [SenseReviewQueueItem] = []
    private(set) var currentIndex = 0
    private(set) var previews: [ReviewRating: ReviewRatingPreview] = [:]
    private(set) var isLoading = true
    private(set) var isSubmitting = false
    private(set) var isAnswerShown = false
    private(set) var isHintShown = false
    private(set) var errorMessage: String?
    private(set) var dailyNewCardLimit = AppSettings.defaultDailyNewCardLimit
    private(set) var newCardsIncluded = 0
    private(set) var initialMeaningCount = 0
    private(set) var reviewAttempts = 0
    private(set) var currentPresentationToken = UUID()
    private(set) var requeuedSenseIDs: Set<UUID> = []
    var sessionMode: ReviewSessionMode = .adaptive

    private let repository: any SenseReviewRepository
    private let appSettingsRepository: any AppSettingsRepository
    private let vocabularyRepository: any VocabularyRepository
    private let dailyNewCardPolicy = DailyNewCardPolicy()
    private let queueRandomizer = ReviewQueueRandomizer()
    private let diagnosticsPlanner = LearningDiagnosticsPlanner()
    private let requeuePolicy = ReviewRequeuePolicy()
    private var allReviewLogs: [ReviewLogEntry] = []
    private var encountersBySenseID: [UUID: [VocabularyEncounter]] = [:]

    init(
        repository: any SenseReviewRepository,
        appSettingsRepository: any AppSettingsRepository,
        vocabularyRepository: any VocabularyRepository
    ) {
        self.repository = repository
        self.appSettingsRepository = appSettingsRepository
        self.vocabularyRepository = vocabularyRepository
    }

    var currentItem: SenseReviewQueueItem? {
        guard queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    var isComplete: Bool {
        !isLoading && currentItem == nil
    }

    var currentPrompt: AdaptiveReviewPrompt {
        switch sessionMode {
        case .termToMeaning:
            return .recognition
        case .meaningToTerm:
            return .spelling
        case .adaptive:
            guard let item = currentItem else { return .recognition }
            return diagnosticsPlanner.adaptivePrompt(for: learningRecord(for: item), now: Date())
        }
    }

    var currentReviewMode: ReviewMode {
        switch sessionMode {
        case .termToMeaning: .termToMeaning
        case .meaningToTerm: .meaningToTerm
        case .adaptive: currentPrompt.reviewMode
        }
    }

    var currentClozeSentence: String? {
        guard let item = currentItem else { return nil }
        return diagnosticsPlanner.clozeSentence(
            term: item.card.term,
            example: item.sense.exampleSentence
        )
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let now = Date()
            let startOfDay = Calendar.current.startOfDay(for: now)
            async let settings = appSettingsRepository.fetch()
            async let logs = repository.fetchReviewLogs(senseID: nil, since: nil)
            async let encounters = vocabularyRepository.fetchAllEncounters()
            let (loadedSettings, loadedLogs, loadedEncounters) = try await (settings, logs, encounters)
            allReviewLogs = loadedLogs
            encountersBySenseID = Dictionary(grouping: loadedEncounters, by: \.senseID)
            let todayLogs = loadedLogs.filter { $0.reviewedAt >= startOfDay && $0.reviewedAt <= now }
            dailyNewCardLimit = loadedSettings.dailyNewCardLimit
            let remainingNewCards = dailyNewCardPolicy.remainingCount(
                dailyLimit: loadedSettings.dailyNewCardLimit,
                logs: todayLogs,
                on: now
            )
            let fetchedQueue = try await repository.fetchQueue(at: now, newLimit: remainingNewCards)
            queue = queueRandomizer.randomized(fetchedQueue)
            initialMeaningCount = fetchedQueue.count
            reviewAttempts = 0
            newCardsIncluded = queue.filter { $0.state.reps == 0 }.count
            currentIndex = 0
            currentPresentationToken = UUID()
            requeuedSenseIDs = []
            isHintShown = false
            try await loadPreviews()
        } catch {
            errorMessage = "无法开始复习：\(error.localizedDescription)"
        }
        isLoading = false
    }

    func showAnswer() {
        isAnswerShown = true
    }

    func showHint() {
        guard currentItem?.sense.memoryInsight != nil else { return }
        isHintShown = true
    }

    func replaceCurrentCard(with updatedCard: VocabularyCard) {
        guard queue.indices.contains(currentIndex) else { return }
        let currentItem = queue[currentIndex]
        queue[currentIndex] = SenseReviewQueueItem(
            card: updatedCard,
            sense: currentItem.sense,
            state: currentItem.state
        )
    }

    func rate(_ rating: ReviewRating) async {
        guard let item = currentItem, isAnswerShown, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            let log = try await repository.recordReview(
                senseID: item.sense.id,
                rating: rating,
                mode: currentReviewMode,
                at: Date()
            )
            allReviewLogs.insert(log, at: 0)
            reviewAttempts += 1
            if requeuePolicy.shouldRequeue(after: log) {
                queue.append(
                    SenseReviewQueueItem(
                        card: item.card,
                        sense: item.sense,
                        state: log.newState
                    )
                )
                requeuedSenseIDs.insert(item.sense.id)
            } else {
                requeuedSenseIDs.remove(item.sense.id)
            }
            currentIndex += 1
            currentPresentationToken = UUID()
            isAnswerShown = false
            isHintShown = false
            try await loadPreviews()
        } catch {
            errorMessage = "保存复习结果失败：\(error.localizedDescription)"
        }
        isSubmitting = false
    }

    var isCurrentItemRequeued: Bool {
        guard let currentItem else { return false }
        return requeuedSenseIDs.contains(currentItem.sense.id)
    }

    private func loadPreviews() async throws {
        previews = [:]
        guard let item = currentItem else { return }
        let values = try await repository.previews(senseID: item.sense.id, at: Date())
        previews = Dictionary(uniqueKeysWithValues: values.map { ($0.rating, $0) })
    }

    private func learningRecord(for item: SenseReviewQueueItem) -> SenseLearningRecord {
        SenseLearningRecord(
            card: item.card,
            sense: item.sense,
            state: item.state,
            encounters: encountersBySenseID[item.sense.id, default: []],
            reviewLogs: allReviewLogs
        )
    }
}
