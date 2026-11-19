import Foundation
import Testing
import VocabularyCore
@testable import VocabularyPersistence

@Suite("App settings repository", .serialized)
struct AppSettingsRepositoryTests {
    @Test("Seeds and persists the daily new-card limit")
    func persistsLimit() async throws {
        let repository = GRDBAppSettingsRepository(database: try AppDatabase.inMemory())
        let initial = try await repository.fetch()
        #expect(initial.dailyNewCardLimit == 20)
        #expect(initial.reviewRemindersEnabled == false)
        #expect(initial.reminderHour == 9)
        #expect(initial.reminderMinute == 0)
        #expect(initial.notifyOnlyWhenDue)

        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updated = try await repository.setDailyNewCardLimit(30, at: updatedAt)
        #expect(updated.dailyNewCardLimit == 30)
        #expect(updated.updatedAt == updatedAt)
        #expect(try await repository.fetch() == updated)
    }

    @Test("Persists review reminder preferences without changing the new-card limit")
    func persistsReminder() async throws {
        let repository = GRDBAppSettingsRepository(database: try AppDatabase.inMemory())
        let updated = try await repository.setReviewReminder(
            enabled: true,
            hour: 18,
            minute: 30,
            onlyWhenDue: false,
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(updated.dailyNewCardLimit == 20)
        #expect(updated.reviewRemindersEnabled)
        #expect(updated.reminderHour == 18)
        #expect(updated.reminderMinute == 30)
        #expect(updated.notifyOnlyWhenDue == false)
    }

    @Test("Rejects limits outside the supported range")
    func rejectsInvalidLimit() async throws {
        let repository = GRDBAppSettingsRepository(database: try AppDatabase.inMemory())
        do {
            _ = try await repository.setDailyNewCardLimit(101, at: Date())
            Issue.record("Expected invalid limit error")
        } catch {
            #expect(error as? AppSettingsRepositoryError == .invalidDailyNewCardLimit)
        }
    }
}
