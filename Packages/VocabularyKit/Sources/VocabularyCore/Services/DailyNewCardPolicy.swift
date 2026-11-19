import Foundation

public struct DailyNewCardPolicy: Sendable {
    public init() {}

    public func consumedCount(
        from logs: [ReviewLogEntry],
        on date: Date,
        calendar: Calendar = .current
    ) -> Int {
        Set(
            logs.lazy
                .filter { log in
                    calendar.isDate(log.reviewedAt, inSameDayAs: date)
                        && log.previousState.reps == 0
                }
                .map { $0.senseID ?? $0.cardID }
        ).count
    }

    public func remainingCount(
        dailyLimit: Int,
        logs: [ReviewLogEntry],
        on date: Date,
        calendar: Calendar = .current
    ) -> Int {
        max(0, dailyLimit - consumedCount(from: logs, on: date, calendar: calendar))
    }
}
