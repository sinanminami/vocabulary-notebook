import AppKit
import SwiftUI
import VocabularyCore

private enum AppSection: String, CaseIterable, Identifiable {
    case today
    case library
    case statistics
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .library: "Library"
        case .statistics: "Statistics"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .today: "calendar"
        case .library: "books.vertical"
        case .statistics: "chart.bar"
        case .settings: "gearshape"
        }
    }

    var tint: Color {
        switch self {
        case .today: AppTheme.accent
        case .library: AppTheme.violet
        case .statistics: AppTheme.orange
        case .settings: AppTheme.cyan
        }
    }
}

private struct AddWordRequest: Identifiable {
    let id = UUID()
    let initialTerm: String
    let notice: String?
    let automaticallyGenerate: Bool
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selection: AppSection? = .today
    @State private var addWordRequest: AddWordRequest?
    @State private var dataRevision = 0
    @State private var reviewStartRequest = 0

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                sidebarBrand
                    .padding(.horizontal, 15)
                    .padding(.top, 17)
                    .padding(.bottom, 15)

                Divider().overlay(AppTheme.divider)
                    .padding(.horizontal, 14)

                VStack(spacing: 5) {
                    ForEach(AppSection.allCases) { section in
                        sidebarButton(section)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.top, 15)

                Spacer(minLength: 20)

                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("LOCAL FIRST")
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                        Text("Private on this Mac")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.warmSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(AppTheme.graphite)
                .padding(12)
                .background(AppTheme.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 0.7)
                }
                .padding(12)
            }
            .background(AppTheme.sidebar)
            .navigationSplitViewColumnWidth(min: 245, ideal: 260)
        } detail: {
            if let errorMessage = environment.startupErrorMessage {
                ContentUnavailableView(
                    "无法启动词库",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(errorMessage)
                )
            } else {
                content(for: selection ?? .today)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(AppTheme.accent)
        .accentColor(AppTheme.accent)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addWordRequest = AddWordRequest(
                        initialTerm: "",
                        notice: nil,
                        automaticallyGenerate: false
                    )
                } label: {
                    Label("Add Word", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!canAddWord)
                .help("Add a word or phrase")
            }
        }
        .sheet(item: $addWordRequest, onDismiss: {
            dataRevision += 1
        }) { request in
            if let vocabularyRepository = environment.vocabularyRepository,
               let reviewStateRepository = environment.reviewStateRepository,
               let tagRepository = environment.tagRepository {
                AddWordView(
                    vocabularyRepository: vocabularyRepository,
                    vocabularySenseRepository: environment.vocabularySenseRepository,
                    reviewStateRepository: reviewStateRepository,
                    tagRepository: tagRepository,
                    aiProvider: environment.aiProvider,
                    initialTerm: request.initialTerm,
                    quickAddNotice: request.notice,
                    automaticallyGenerate: request.automaticallyGenerate
                )
                .id(request.id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vocabularyDataChanged)) { _ in
            dataRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsRequested)) { _ in
            consumePendingSettingsRequest()
        }
        .onReceive(NotificationCenter.default.publisher(for: .reviewReminderOpened)) { _ in
            consumePendingReviewOpen()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await environment.reminderManager?.refreshScheduleIfAuthorized() }
        }
        .task(id: dataRevision) {
            await environment.reminderManager?.refreshScheduleIfAuthorized()
        }
        .task {
            QuickAddPanelController.shared.configure(environment: environment)
            consumePendingReviewOpen()
            consumePendingSettingsRequest()
        }
    }

    private var canAddWord: Bool {
        environment.vocabularyRepository != nil
            && environment.reviewStateRepository != nil
            && environment.tagRepository != nil
    }

    private var sidebarBrand: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("Word Notebook")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.graphite)
                    .lineLimit(1)
                Text("Capture · Remember")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.warmSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func sidebarButton(_ section: AppSection) -> some View {
        let isSelected = selection == section
        return Button {
            withAnimation(.easeOut(duration: 0.16)) {
                selection = section
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? section.tint : AppTheme.warmSecondary)
                    .frame(width: 31, height: 31)
                    .background(
                        isSelected ? section.tint.opacity(0.15) : AppTheme.field.opacity(0.72),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                Text(section.title)
                    .font(.system(size: 15, weight: isSelected ? .bold : .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? AppTheme.graphite : AppTheme.warmSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? AppTheme.surfaceRaised : Color.clear)
                    .overlay(alignment: .leading) {
                        if isSelected {
                            Capsule()
                                .fill(section.tint)
                                .frame(width: 3, height: 20)
                                .padding(.leading, 1)
                        }
                    }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 0.7)
                        }
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func consumePendingReviewOpen() {
        guard ReviewReminderNavigation.shared.consumeReviewOpen() else { return }
        selection = .today
        reviewStartRequest += 1
    }

    private func consumePendingSettingsRequest() {
        guard AppNavigationRequest.shared.consumeSettingsRequest() else { return }
        selection = .settings
    }

    @ViewBuilder
    private func content(for section: AppSection) -> some View {
        switch section {
        case .today:
            dataView { vocabularyRepository, reviewStateRepository, reviewSessionRepository in
                if let appSettingsRepository = environment.appSettingsRepository,
                   let vocabularySenseRepository = environment.vocabularySenseRepository,
                   let senseReviewRepository = environment.senseReviewRepository {
                    TodayView(
                        vocabularyRepository: vocabularyRepository,
                        reviewStateRepository: reviewStateRepository,
                        reviewSessionRepository: reviewSessionRepository,
                        vocabularySenseRepository: vocabularySenseRepository,
                        senseReviewRepository: senseReviewRepository,
                        appSettingsRepository: appSettingsRepository,
                        aiProvider: environment.aiProvider,
                        reviewStartRequest: reviewStartRequest,
                        refreshToken: dataRevision,
                        onReviewStartRequestHandled: { reviewStartRequest = 0 },
                        onReviewCompleted: { dataRevision += 1 }
                    )
                } else {
                    placeholder(
                        title: "复习设置暂不可用",
                        subtitle: "本地设置数据尚未准备好。",
                        symbol: "gearshape"
                    )
                }
            }
        case .library:
            dataView { vocabularyRepository, reviewStateRepository, _ in
                if let tagRepository = environment.tagRepository,
                   let vocabularySenseRepository = environment.vocabularySenseRepository,
                   let senseReviewRepository = environment.senseReviewRepository {
                    LibraryView(
                        vocabularyRepository: vocabularyRepository,
                        vocabularySenseRepository: vocabularySenseRepository,
                        reviewStateRepository: reviewStateRepository,
                        senseReviewRepository: senseReviewRepository,
                        tagRepository: tagRepository,
                        aiProvider: environment.aiProvider,
                        refreshToken: dataRevision,
                        onDataChanged: { dataRevision += 1 }
                    )
                } else {
                    placeholder(
                        title: "标签暂不可用",
                        subtitle: "本地标签数据尚未准备好。",
                        symbol: "tag.slash"
                    )
                }
            }
        case .statistics:
            if let vocabularyRepository = environment.vocabularyRepository,
               let reviewStateRepository = environment.reviewStateRepository,
               let reviewSessionRepository = environment.reviewSessionRepository,
               let vocabularySenseRepository = environment.vocabularySenseRepository,
               let senseReviewRepository = environment.senseReviewRepository {
                StatisticsView(
                    vocabularyRepository: vocabularyRepository,
                    reviewStateRepository: reviewStateRepository,
                    reviewSessionRepository: reviewSessionRepository,
                    vocabularySenseRepository: vocabularySenseRepository,
                    senseReviewRepository: senseReviewRepository,
                    refreshToken: dataRevision
                )
            } else {
                placeholder(
                    title: "统计暂不可用",
                    subtitle: "本地词义数据尚未准备好。",
                    symbol: "chart.bar.xaxis"
                )
            }
        case .settings:
            if let appSettingsRepository = environment.appSettingsRepository,
               let reminderManager = environment.reminderManager,
               let tagRepository = environment.tagRepository,
               let vocabularyRepository = environment.vocabularyRepository,
               let reviewStateRepository = environment.reviewStateRepository {
                SettingsView(
                    apiKeyStore: environment.apiKeyStore,
                    aiProvider: environment.aiProvider,
                    vocabularyRepository: vocabularyRepository,
                    reviewStateRepository: reviewStateRepository,
                    appSettingsRepository: appSettingsRepository,
                    tagRepository: tagRepository,
                    reminderManager: reminderManager,
                    onReviewSettingsChanged: { dataRevision += 1 }
                )
            } else {
                placeholder(
                    title: "设置暂不可用",
                    subtitle: "本地设置数据尚未准备好。",
                    symbol: "gearshape"
                )
            }
        }
    }

    @ViewBuilder
    private func dataView<Content: View>(
        @ViewBuilder content: (
            any VocabularyRepository,
            any ReviewStateRepository,
            any ReviewSessionRepository
        ) -> Content
    ) -> some View {
        if let vocabularyRepository = environment.vocabularyRepository,
           let reviewStateRepository = environment.reviewStateRepository,
           let reviewSessionRepository = environment.reviewSessionRepository {
            content(vocabularyRepository, reviewStateRepository, reviewSessionRepository)
        } else {
            placeholder(
                title: "数据暂不可用",
                subtitle: "本地数据库尚未准备好。",
                symbol: "externaldrive.badge.exclamationmark"
            )
        }
    }

    private func placeholder(title: String, subtitle: String, symbol: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: symbol,
            description: Text(subtitle)
        )
        .navigationTitle(title)
        .appPageBackground()
    }
}
