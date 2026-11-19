import Foundation
import GRDB
import VocabularyCore

struct AppSettingsRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "app_settings"
    static let singletonID = 1

    var id: Int
    var dailyNewCardLimit: Int
    var reviewRemindersEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int
    var notifyOnlyWhenDue: Bool
    var updatedAtMS: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case dailyNewCardLimit = "daily_new_card_limit"
        case reviewRemindersEnabled = "review_reminders_enabled"
        case reminderHour = "reminder_hour"
        case reminderMinute = "reminder_minute"
        case notifyOnlyWhenDue = "notify_only_when_due"
        case updatedAtMS = "updated_at_ms"
    }

    var domainModel: AppSettings {
        AppSettings(
            dailyNewCardLimit: dailyNewCardLimit,
            reviewRemindersEnabled: reviewRemindersEnabled,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute,
            notifyOnlyWhenDue: notifyOnlyWhenDue,
            updatedAt: DateStorage.date(updatedAtMS)
        )
    }
}
