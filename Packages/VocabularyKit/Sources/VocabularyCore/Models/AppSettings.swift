import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public static let defaultDailyNewCardLimit = 20
    public static let dailyNewCardLimitRange = 0...100

    public var dailyNewCardLimit: Int
    public var reviewRemindersEnabled: Bool
    public var reminderHour: Int
    public var reminderMinute: Int
    public var notifyOnlyWhenDue: Bool
    public var updatedAt: Date

    public init(
        dailyNewCardLimit: Int,
        reviewRemindersEnabled: Bool = false,
        reminderHour: Int = 9,
        reminderMinute: Int = 0,
        notifyOnlyWhenDue: Bool = true,
        updatedAt: Date
    ) {
        self.dailyNewCardLimit = dailyNewCardLimit
        self.reviewRemindersEnabled = reviewRemindersEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.notifyOnlyWhenDue = notifyOnlyWhenDue
        self.updatedAt = updatedAt
    }
}

public enum AppSettingsRepositoryError: Error, Equatable, Sendable {
    case settingsNotFound
    case invalidDailyNewCardLimit
    case invalidReminderTime
}

extension AppSettingsRepositoryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .settingsNotFound:
            "找不到本地复习设置。"
        case .invalidDailyNewCardLimit:
            "每日新词义额度必须在 0 到 100 之间。"
        case .invalidReminderTime:
            "提醒时间无效。"
        }
    }
}
