import Foundation
import GRDB
import VocabularyCore

public final class GRDBAppSettingsRepository: AppSettingsRepository, @unchecked Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func fetch() async throws -> AppSettings {
        try await database.queue.read { database in
            guard let record = try AppSettingsRecord.fetchOne(
                database,
                key: AppSettingsRecord.singletonID
            ) else {
                throw AppSettingsRepositoryError.settingsNotFound
            }
            return record.domainModel
        }
    }

    public func setDailyNewCardLimit(_ limit: Int, at date: Date) async throws -> AppSettings {
        guard AppSettings.dailyNewCardLimitRange.contains(limit) else {
            throw AppSettingsRepositoryError.invalidDailyNewCardLimit
        }
        return try await database.queue.write { database in
            guard var record = try AppSettingsRecord.fetchOne(
                database,
                key: AppSettingsRecord.singletonID
            ) else {
                throw AppSettingsRepositoryError.settingsNotFound
            }
            record.dailyNewCardLimit = limit
            record.updatedAtMS = DateStorage.milliseconds(date)
            try record.update(database)
            return record.domainModel
        }
    }

    public func setReviewReminder(
        enabled: Bool,
        hour: Int,
        minute: Int,
        onlyWhenDue: Bool,
        at date: Date
    ) async throws -> AppSettings {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else {
            throw AppSettingsRepositoryError.invalidReminderTime
        }
        return try await database.queue.write { database in
            guard var record = try AppSettingsRecord.fetchOne(
                database,
                key: AppSettingsRecord.singletonID
            ) else {
                throw AppSettingsRepositoryError.settingsNotFound
            }
            record.reviewRemindersEnabled = enabled
            record.reminderHour = hour
            record.reminderMinute = minute
            record.notifyOnlyWhenDue = onlyWhenDue
            record.updatedAtMS = DateStorage.milliseconds(date)
            try record.update(database)
            return record.domainModel
        }
    }

    public func setReviewPreferences(
        dailyNewCardLimit: Int,
        remindersEnabled: Bool,
        reminderHour: Int,
        reminderMinute: Int,
        onlyWhenDue: Bool,
        at date: Date
    ) async throws -> AppSettings {
        guard AppSettings.dailyNewCardLimitRange.contains(dailyNewCardLimit) else {
            throw AppSettingsRepositoryError.invalidDailyNewCardLimit
        }
        guard (0..<24).contains(reminderHour), (0..<60).contains(reminderMinute) else {
            throw AppSettingsRepositoryError.invalidReminderTime
        }
        return try await database.queue.write { database in
            guard var record = try AppSettingsRecord.fetchOne(
                database,
                key: AppSettingsRecord.singletonID
            ) else {
                throw AppSettingsRepositoryError.settingsNotFound
            }
            record.dailyNewCardLimit = dailyNewCardLimit
            record.reviewRemindersEnabled = remindersEnabled
            record.reminderHour = reminderHour
            record.reminderMinute = reminderMinute
            record.notifyOnlyWhenDue = onlyWhenDue
            record.updatedAtMS = DateStorage.milliseconds(date)
            try record.update(database)
            return record.domainModel
        }
    }
}
