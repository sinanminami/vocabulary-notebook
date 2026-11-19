import AppKit
import Foundation
import UserNotifications
import VocabularyCore

extension Notification.Name {
    static let reviewReminderOpened = Notification.Name("VocabularyApp.reviewReminderOpened")
}

enum ReviewReminderNotification {
    static let identifierPrefix = "VocabularyApp.review-reminder."
    static let destinationKey = "destination"
    static let todayDestination = "today-review"
}

@MainActor
final class ReviewReminderNavigation {
    static let shared = ReviewReminderNavigation()

    private var hasPendingReviewOpen = false

    private init() {}

    func requestReviewOpen() {
        hasPendingReviewOpen = true
        NotificationCenter.default.post(name: .reviewReminderOpened, object: nil)
    }

    func consumeReviewOpen() -> Bool {
        guard hasPendingReviewOpen else { return false }
        hasPendingReviewOpen = false
        return true
    }
}

enum ReminderAuthorizationState: Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case unknown

    var allowsNotifications: Bool {
        self == .authorized || self == .provisional
    }

    var displayName: String {
        switch self {
        case .notDetermined: "尚未请求"
        case .denied: "未授权"
        case .authorized: "已授权"
        case .provisional: "临时授权"
        case .unknown: "未知"
        }
    }
}

@MainActor
final class ReviewReminderManager {
    private let center: UNUserNotificationCenter
    private let settingsRepository: any AppSettingsRepository
    private let senseReviewRepository: any SenseReviewRepository
    private let planner = ReviewReminderPlanner()

    init(
        settingsRepository: any AppSettingsRepository,
        senseReviewRepository: any SenseReviewRepository,
        center: UNUserNotificationCenter = .current()
    ) {
        self.settingsRepository = settingsRepository
        self.senseReviewRepository = senseReviewRepository
        self.center = center
    }

    func authorizationState() async -> ReminderAuthorizationState {
        let settings = await center.notificationSettings()
        return switch settings.authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        case .provisional, .ephemeral: .provisional
        @unknown default: .unknown
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func refreshScheduleIfAuthorized() async {
        do {
            try await refreshSchedule()
        } catch {
            // Scheduling is best-effort outside Settings. The Settings screen
            // surfaces actionable permission and scheduling errors to the user.
        }
    }

    func refreshSchedule() async throws {
        let settings = try await settingsRepository.fetch()
        guard settings.reviewRemindersEnabled else {
            await removeScheduledReminders()
            return
        }
        guard await authorizationState().allowsNotifications else {
            await removeScheduledReminders()
            return
        }

        let states = try await senseReviewRepository.fetchAllStates()
        let plan = planner.plan(
            settings: settings,
            reviewStates: states,
            now: Date()
        )
        await removeScheduledReminders()

        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = "该复习单词了"
            content.body = item.dueCount > 0
                ? "今天有 \(item.dueCount) 个到期词义，花几分钟巩固一下。"
                : "打开单词记录本，完成今天的复习。"
            content.sound = .default
            content.userInfo = [
                ReviewReminderNotification.destinationKey:
                    ReviewReminderNotification.todayDestination
            ]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: item.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )
            let identifier = ReviewReminderNotification.identifierPrefix
                + Self.identifierDate(item.fireDate)
            try await center.add(
                UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: trigger
                )
            )
        }
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.notifications"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func removeScheduledReminders() async {
        let requests = await center.pendingNotificationRequests()
        let identifiers = requests
            .map(\.identifier)
            .filter { $0.hasPrefix(ReviewReminderNotification.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private static func identifierDate(_ date: Date) -> String {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        return String(
            format: "%04d-%02d-%02d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        )
    }
}
