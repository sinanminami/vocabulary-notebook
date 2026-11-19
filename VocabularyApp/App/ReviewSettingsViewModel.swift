import Foundation
import Observation
import VocabularyCore

@MainActor
@Observable
final class ReviewSettingsViewModel {
    var dailyNewCardLimit = AppSettings.defaultDailyNewCardLimit
    var reviewRemindersEnabled = false
    var reminderTime = Calendar.current.date(
        bySettingHour: 9,
        minute: 0,
        second: 0,
        of: Date()
    ) ?? Date()
    var notifyOnlyWhenDue = true
    private(set) var savedDailyNewCardLimit = AppSettings.defaultDailyNewCardLimit
    private(set) var savedReviewRemindersEnabled = false
    private(set) var savedReminderHour = 9
    private(set) var savedReminderMinute = 0
    private(set) var savedNotifyOnlyWhenDue = true
    private(set) var authorizationState: ReminderAuthorizationState = .notDetermined
    private(set) var isLoading = false
    private(set) var isSaving = false
    var statusMessage: String?
    var errorMessage: String?

    private let repository: any AppSettingsRepository
    private let reminderManager: ReviewReminderManager

    init(
        repository: any AppSettingsRepository,
        reminderManager: ReviewReminderManager
    ) {
        self.repository = repository
        self.reminderManager = reminderManager
    }

    var hasChanges: Bool {
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        return dailyNewCardLimit != savedDailyNewCardLimit
            || reviewRemindersEnabled != savedReviewRemindersEnabled
            || components.hour != savedReminderHour
            || components.minute != savedReminderMinute
            || notifyOnlyWhenDue != savedNotifyOnlyWhenDue
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let settings = try await repository.fetch()
            dailyNewCardLimit = settings.dailyNewCardLimit
            savedDailyNewCardLimit = settings.dailyNewCardLimit
            reviewRemindersEnabled = settings.reviewRemindersEnabled
            savedReviewRemindersEnabled = settings.reviewRemindersEnabled
            savedReminderHour = settings.reminderHour
            savedReminderMinute = settings.reminderMinute
            reminderTime = Calendar.current.date(
                bySettingHour: settings.reminderHour,
                minute: settings.reminderMinute,
                second: 0,
                of: Date()
            ) ?? reminderTime
            notifyOnlyWhenDue = settings.notifyOnlyWhenDue
            savedNotifyOnlyWhenDue = settings.notifyOnlyWhenDue
            authorizationState = await reminderManager.authorizationState()
        } catch {
            errorMessage = "无法读取复习设置：\(error.localizedDescription)"
        }
        isLoading = false
    }

    func save() async -> Bool {
        guard hasChanges, !isSaving else { return false }
        isSaving = true
        statusMessage = nil
        errorMessage = nil
        do {
            if reviewRemindersEnabled {
                authorizationState = await reminderManager.authorizationState()
                if authorizationState == .notDetermined {
                    let granted = try await reminderManager.requestAuthorization()
                    authorizationState = await reminderManager.authorizationState()
                    guard granted else {
                        errorMessage = "未获得通知权限，复习提醒尚未启用。"
                        isSaving = false
                        return false
                    }
                }
                guard authorizationState.allowsNotifications else {
                    errorMessage = "通知权限未开启，请先在系统设置中允许单词记录本发送通知。"
                    isSaving = false
                    return false
                }
            }

            let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
            let hour = components.hour ?? 9
            let minute = components.minute ?? 0
            let settings = try await repository.setReviewPreferences(
                dailyNewCardLimit: dailyNewCardLimit,
                remindersEnabled: reviewRemindersEnabled,
                reminderHour: hour,
                reminderMinute: minute,
                onlyWhenDue: notifyOnlyWhenDue,
                at: Date()
            )
            dailyNewCardLimit = settings.dailyNewCardLimit
            savedDailyNewCardLimit = settings.dailyNewCardLimit
            reviewRemindersEnabled = settings.reviewRemindersEnabled
            savedReviewRemindersEnabled = settings.reviewRemindersEnabled
            savedReminderHour = settings.reminderHour
            savedReminderMinute = settings.reminderMinute
            notifyOnlyWhenDue = settings.notifyOnlyWhenDue
            savedNotifyOnlyWhenDue = settings.notifyOnlyWhenDue
            do {
                try await reminderManager.refreshSchedule()
                statusMessage = settings.reviewRemindersEnabled
                    ? "复习设置已更新，提醒已重新安排。"
                    : "复习设置已更新。"
            } catch {
                errorMessage = "设置已保存，但无法安排提醒：\(error.localizedDescription)"
            }
            isSaving = false
            return true
        } catch {
            errorMessage = "无法保存复习设置：\(error.localizedDescription)"
            isSaving = false
            return false
        }
    }

    func refreshAuthorization() async {
        authorizationState = await reminderManager.authorizationState()
    }

    func openNotificationSettings() {
        reminderManager.openSystemSettings()
    }
}
