import Foundation
import Testing
@testable import VocabularyCore

@Suite("Review reminder planner")
struct ReviewReminderPlannerTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    @Test("Disabled reminders produce no requests")
    func disabled() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let settings = AppSettings(
            dailyNewCardLimit: 20,
            reviewRemindersEnabled: false,
            updatedAt: now
        )
        #expect(ReviewReminderPlanner().plan(
            settings: settings,
            reviewStates: [],
            now: now,
            calendar: calendar
        ).isEmpty)
    }

    @Test("Only-when-due starts notifying when a learned card becomes due")
    func onlyWhenDue() throws {
        let now = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 24, hour: 8)
        ))
        let tomorrowAtEight = try #require(calendar.date(
            byAdding: .day,
            value: 1,
            to: now
        ))
        let settings = AppSettings(
            dailyNewCardLimit: 20,
            reviewRemindersEnabled: true,
            reminderHour: 9,
            reminderMinute: 0,
            notifyOnlyWhenDue: true,
            updatedAt: now
        )
        let state = ReviewState(
            id: UUID(),
            cardID: UUID(),
            dueAt: tomorrowAtEight,
            reps: 1,
            fsrsState: .review,
            updatedAt: now
        )

        let plan = ReviewReminderPlanner().plan(
            settings: settings,
            reviewStates: [state],
            now: now,
            calendar: calendar,
            horizonDays: 3
        )

        #expect(plan.count == 2)
        #expect(plan.allSatisfy { $0.dueCount == 1 })
        #expect(calendar.component(.hour, from: plan[0].fireDate) == 9)
    }

    @Test("Daily reminders include days with no due cards when requested")
    func everyDay() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let settings = AppSettings(
            dailyNewCardLimit: 20,
            reviewRemindersEnabled: true,
            reminderHour: 23,
            reminderMinute: 30,
            notifyOnlyWhenDue: false,
            updatedAt: now
        )
        let plan = ReviewReminderPlanner().plan(
            settings: settings,
            reviewStates: [],
            now: now,
            calendar: calendar,
            horizonDays: 3
        )
        #expect(plan.count == 3)
        #expect(plan.allSatisfy { $0.dueCount == 0 })
    }
}
