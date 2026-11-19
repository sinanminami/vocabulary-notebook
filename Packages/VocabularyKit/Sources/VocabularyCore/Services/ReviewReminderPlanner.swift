import Foundation

public struct ReviewReminderPlanItem: Equatable, Sendable {
    public let fireDate: Date
    public let dueCount: Int

    public init(fireDate: Date, dueCount: Int) {
        self.fireDate = fireDate
        self.dueCount = dueCount
    }
}

public struct ReviewReminderPlanner: Sendable {
    public init() {}

    public func plan(
        settings: AppSettings,
        reviewStates: [ReviewState],
        now: Date,
        calendar: Calendar = .current,
        horizonDays: Int = 14
    ) -> [ReviewReminderPlanItem] {
        guard settings.reviewRemindersEnabled, horizonDays > 0 else { return [] }

        return (0..<horizonDays).compactMap { dayOffset in
            guard let day = calendar.date(
                byAdding: .day,
                value: dayOffset,
                to: calendar.startOfDay(for: now)
            ),
                  let fireDate = calendar.date(
                    bySettingHour: settings.reminderHour,
                    minute: settings.reminderMinute,
                    second: 0,
                    of: day
                  ),
                  fireDate > now else {
                return nil
            }

            let dueCount = reviewStates.filter {
                $0.reps > 0 && $0.fsrsState != .new && $0.dueAt <= fireDate
            }.count
            guard !settings.notifyOnlyWhenDue || dueCount > 0 else { return nil }
            return ReviewReminderPlanItem(fireDate: fireDate, dueCount: dueCount)
        }
    }
}
