import Foundation

public struct DailyReviewActivity: Identifiable, Equatable, Sendable {
    public var id: Date { day }
    public let day: Date
    public let reviewCount: Int
    public let successfulRecallCount: Int

    public init(day: Date, reviewCount: Int, successfulRecallCount: Int) {
        self.day = day
        self.reviewCount = reviewCount
        self.successfulRecallCount = successfulRecallCount
    }
}

public struct VocabularyStatistics: Equatable, Sendable {
    public let totalWords: Int
    public let totalMeanings: Int
    public let masteryCounts: [MasteryLevel: Int]
    public let dueToday: Int
    public let thisWeekAdded: Int
    public let thisWeekReviewed: Int
    public let retentionSuccessPercent: Int?
    public let retentionSampleCount: Int
    public let dailyReviewActivity: [DailyReviewActivity]

    public init(
        totalWords: Int,
        totalMeanings: Int? = nil,
        masteryCounts: [MasteryLevel: Int],
        dueToday: Int,
        thisWeekAdded: Int,
        thisWeekReviewed: Int,
        retentionSuccessPercent: Int?,
        retentionSampleCount: Int,
        dailyReviewActivity: [DailyReviewActivity]
    ) {
        self.totalWords = totalWords
        self.totalMeanings = totalMeanings ?? totalWords
        self.masteryCounts = masteryCounts
        self.dueToday = dueToday
        self.thisWeekAdded = thisWeekAdded
        self.thisWeekReviewed = thisWeekReviewed
        self.retentionSuccessPercent = retentionSuccessPercent
        self.retentionSampleCount = retentionSampleCount
        self.dailyReviewActivity = dailyReviewActivity
    }

    public func count(_ level: MasteryLevel) -> Int {
        masteryCounts[level, default: 0]
    }
}

public struct StatisticsCalculator: Sendable {
    private let masteryPolicy: MasteryPolicy

    public init(masteryPolicy: MasteryPolicy = MasteryPolicy()) {
        self.masteryPolicy = masteryPolicy
    }

    /// Retention is the non-Again rate for reviews of cards that had already
    /// been introduced before that review. First-ever reviews are excluded.
    public func calculate(
        cards: [VocabularyCard],
        reviewStates: [ReviewState],
        reviewLogs: [ReviewLogEntry],
        now: Date,
        calendar: Calendar = .current,
        retentionDays: Int = 30,
        activityDays: Int = 30
    ) -> VocabularyStatistics {
        let statesByCardID = Dictionary(
            uniqueKeysWithValues: reviewStates.map { ($0.cardID, $0) }
        )
        var masteryCounts = Dictionary(
            uniqueKeysWithValues: MasteryLevel.allCases.map { ($0, 0) }
        )
        for card in cards {
            let level = statesByCardID[card.id].map(masteryPolicy.level(for:)) ?? .new
            masteryCounts[level, default: 0] += 1
        }

        let dueToday = reviewStates.filter {
            $0.reps > 0 && $0.fsrsState != .new && $0.dueAt <= now
        }.count
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
            ?? calendar.startOfDay(for: now)
        let thisWeekAdded = cards.filter {
            $0.createdAt >= weekStart && $0.createdAt <= now
        }.count
        let thisWeekReviewed = reviewLogs.filter {
            $0.reviewedAt >= weekStart && $0.reviewedAt <= now
        }.count

        let retentionStart = calendar.date(
            byAdding: .day,
            value: -max(0, retentionDays - 1),
            to: calendar.startOfDay(for: now)
        ) ?? .distantPast
        let retentionLogs = reviewLogs.filter {
            $0.reviewedAt >= retentionStart
                && $0.reviewedAt <= now
                && $0.previousState.reps > 0
                && $0.previousState.fsrsState != .new
        }
        let successfulRetention = retentionLogs.filter { $0.rating != .again }.count
        let retentionPercent = retentionLogs.isEmpty
            ? nil
            : Int((Double(successfulRetention) / Double(retentionLogs.count) * 100).rounded())

        let activityStart = calendar.date(
            byAdding: .day,
            value: -max(0, activityDays - 1),
            to: calendar.startOfDay(for: now)
        ) ?? calendar.startOfDay(for: now)
        let relevantActivityLogs = reviewLogs.filter {
            $0.reviewedAt >= activityStart && $0.reviewedAt <= now
        }
        let groupedLogs = Dictionary(grouping: relevantActivityLogs) {
            calendar.startOfDay(for: $0.reviewedAt)
        }
        let dailyActivity: [DailyReviewActivity] = (0..<max(0, activityDays)).compactMap { offset -> DailyReviewActivity? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: activityStart),
                  day <= now else { return nil }
            let logs = groupedLogs[day, default: []]
            return DailyReviewActivity(
                day: day,
                reviewCount: logs.count,
                successfulRecallCount: logs.filter { $0.rating != .again }.count
            )
        }

        return VocabularyStatistics(
            totalWords: cards.count,
            masteryCounts: masteryCounts,
            dueToday: dueToday,
            thisWeekAdded: thisWeekAdded,
            thisWeekReviewed: thisWeekReviewed,
            retentionSuccessPercent: retentionPercent,
            retentionSampleCount: retentionLogs.count,
            dailyReviewActivity: dailyActivity
        )
    }

    public func calculate(
        cards: [VocabularyCard],
        senses: [VocabularySense],
        reviewStates: [ReviewState],
        reviewLogs: [ReviewLogEntry],
        now: Date,
        calendar: Calendar = .current,
        activityDays: Int = 30
    ) -> VocabularyStatistics {
        let statesBySenseID = Dictionary(
            uniqueKeysWithValues: reviewStates.compactMap { state in
                state.senseID.map { ($0, state) }
            }
        )
        var masteryCounts = Dictionary(
            uniqueKeysWithValues: MasteryLevel.allCases.map { ($0, 0) }
        )
        for sense in senses {
            let level = statesBySenseID[sense.id].map(masteryPolicy.level(for:)) ?? .new
            masteryCounts[level, default: 0] += 1
        }

        let dueToday = reviewStates.filter {
            $0.senseID != nil && $0.reps > 0 && $0.fsrsState != .new && $0.dueAt <= now
        }.count
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
            ?? calendar.startOfDay(for: now)
        let thisWeekAdded = senses.filter {
            $0.createdAt >= weekStart && $0.createdAt <= now
        }.count
        let thisWeekReviewed = reviewLogs.filter {
            $0.reviewedAt >= weekStart && $0.reviewedAt <= now
        }.count

        let activityStart = calendar.date(
            byAdding: .day,
            value: -max(0, activityDays - 1),
            to: calendar.startOfDay(for: now)
        ) ?? calendar.startOfDay(for: now)
        let relevantActivityLogs = reviewLogs.filter {
            $0.reviewedAt >= activityStart && $0.reviewedAt <= now
        }
        let groupedLogs = Dictionary(grouping: relevantActivityLogs) {
            calendar.startOfDay(for: $0.reviewedAt)
        }
        let dailyActivity: [DailyReviewActivity] = (0..<max(0, activityDays)).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: activityStart),
                  day <= now else { return nil }
            let logs = groupedLogs[day, default: []]
            return DailyReviewActivity(
                day: day,
                reviewCount: logs.count,
                successfulRecallCount: logs.filter { $0.rating != .again }.count
            )
        }

        return VocabularyStatistics(
            totalWords: cards.count,
            totalMeanings: senses.count,
            masteryCounts: masteryCounts,
            dueToday: dueToday,
            thisWeekAdded: thisWeekAdded,
            thisWeekReviewed: thisWeekReviewed,
            retentionSuccessPercent: nil,
            retentionSampleCount: 0,
            dailyReviewActivity: dailyActivity
        )
    }
}
