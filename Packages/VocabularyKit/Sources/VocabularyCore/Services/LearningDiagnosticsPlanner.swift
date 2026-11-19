import Foundation

public enum LearningDiagnosticSignal: String, Codable, CaseIterable, Sendable {
    case repeatedForgetting
    case sustainedDifficulty
    case overdue
    case narrowContext
    case missingLearningSupport
}

public struct SenseLearningRecord: Sendable {
    public let card: VocabularyCard
    public let sense: VocabularySense
    public let state: ReviewState
    public let encounters: [VocabularyEncounter]
    public let reviewLogs: [ReviewLogEntry]

    public init(
        card: VocabularyCard,
        sense: VocabularySense,
        state: ReviewState,
        encounters: [VocabularyEncounter],
        reviewLogs: [ReviewLogEntry]
    ) {
        self.card = card
        self.sense = sense
        self.state = state
        self.encounters = encounters
        self.reviewLogs = reviewLogs
    }
}

public struct LearningDiagnostic: Identifiable, Equatable, Sendable {
    public var id: UUID { senseID }
    public let cardID: UUID
    public let senseID: UUID
    public let signal: LearningDiagnosticSignal
    public let suggestedPrompt: AdaptiveReviewPrompt
    public let priority: Int

    public init(
        cardID: UUID,
        senseID: UUID,
        signal: LearningDiagnosticSignal,
        suggestedPrompt: AdaptiveReviewPrompt,
        priority: Int
    ) {
        self.cardID = cardID
        self.senseID = senseID
        self.signal = signal
        self.suggestedPrompt = suggestedPrompt
        self.priority = priority
    }
}

public struct LearningDiagnosticsPlanner: Sendable {
    public init() {}

    public func adaptivePrompt(for record: SenseLearningRecord, now: Date) -> AdaptiveReviewPrompt {
        guard record.state.reps >= 2 else { return .recognition }

        let recent = relevantLogs(record).prefix(4)
        let recentFailures = recent.filter { $0.rating == .again }.count
        let hasContrast = record.sense.memoryInsight?.contrastNoteZH?.isEmpty == false
        let canUseContext = clozeRange(term: record.card.term, in: record.sense.exampleSentence) != nil

        if record.state.lapses >= 2 || recentFailures >= 2 {
            if hasContrast { return .contrast }
            if canUseContext { return .contextCloze }
            if canSpell(record.card.term) { return .spelling }
        }

        if record.state.difficulty >= 7, canListen(to: record.card) {
            return .listening
        }

        let contextualEncounters = record.encounters.filter {
            $0.senseID == record.sense.id && $0.context?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        if contextualEncounters.count <= 1, record.state.reps >= 3, canUseContext {
            return .contextCloze
        }

        if record.state.reps >= 5, canSpell(record.card.term) {
            return .spelling
        }
        return .recognition
    }

    public func rankedDiagnostics(
        from records: [SenseLearningRecord],
        now: Date,
        limit: Int = 4
    ) -> [LearningDiagnostic] {
        records.compactMap { diagnostic(for: $0, now: now) }
            .sorted {
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return $0.senseID.uuidString < $1.senseID.uuidString
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    public func clozeSentence(term: String, example: String) -> String? {
        guard let range = clozeRange(term: term, in: example) else { return nil }
        var sentence = example
        sentence.replaceSubrange(range, with: "______")
        return sentence
    }

    private func diagnostic(for record: SenseLearningRecord, now: Date) -> LearningDiagnostic? {
        guard record.state.reps > 0 else { return nil }
        let recent = relevantLogs(record).prefix(4)
        let failures = recent.filter { $0.rating == .again }.count
        let hardOrAgain = recent.filter { $0.rating == .again || $0.rating == .hard }.count
        let prompt = adaptivePrompt(for: record, now: now)

        if record.state.lapses >= 2 || failures >= 2 {
            return make(record, .repeatedForgetting, prompt, 100 + record.state.lapses * 4 + failures)
        }
        if record.state.difficulty >= 7, hardOrAgain >= 2 {
            return make(record, .sustainedDifficulty, prompt, 86 + Int(record.state.difficulty.rounded()))
        }
        let overdueDays = max(0, Calendar.current.dateComponents([.day], from: record.state.dueAt, to: now).day ?? 0)
        if record.state.fsrsState != .new, record.state.dueAt <= now, overdueDays >= 2 {
            return make(record, .overdue, prompt, 72 + min(overdueDays, 20))
        }
        let contextualEncounters = record.encounters.filter {
            $0.senseID == record.sense.id && $0.context?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }.count
        if record.state.reps >= 3, contextualEncounters <= 1 {
            return make(record, .narrowContext, prompt, 58 + min(record.state.reps, 10))
        }
        if record.state.reps >= 2,
           record.sense.memoryInsight == nil || record.card.pronunciationIPA.isEmpty {
            return make(record, .missingLearningSupport, prompt, 42)
        }
        return nil
    }

    private func relevantLogs(_ record: SenseLearningRecord) -> [ReviewLogEntry] {
        record.reviewLogs.filter {
            $0.senseID == record.sense.id || ($0.senseID == nil && record.sense.isPrimary && $0.cardID == record.card.id)
        }
        .sorted { $0.reviewedAt > $1.reviewedAt }
    }

    private func make(
        _ record: SenseLearningRecord,
        _ signal: LearningDiagnosticSignal,
        _ prompt: AdaptiveReviewPrompt,
        _ priority: Int
    ) -> LearningDiagnostic {
        LearningDiagnostic(
            cardID: record.card.id,
            senseID: record.sense.id,
            signal: signal,
            suggestedPrompt: prompt,
            priority: priority
        )
    }

    private func canListen(to card: VocabularyCard) -> Bool {
        [.english, .japanese].contains(card.languageCode) && card.term.split(separator: " ").count <= 4
    }

    private func canSpell(_ term: String) -> Bool {
        let pieces = term.split(whereSeparator: { $0.isWhitespace })
        return pieces.count == 1 && term.count >= 4 && term.count <= 28
    }

    private func clozeRange(term: String, in example: String) -> Range<String.Index>? {
        guard !term.isEmpty, !example.isEmpty else { return nil }
        return example.range(of: term, options: [.caseInsensitive, .diacriticInsensitive])
    }
}
