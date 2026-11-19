import SwiftUI
import VocabularyCore

struct TodayView: View {
    @State private var model: VocabularySnapshotModel
    @State private var isReviewing = false
    @State private var dailyNewCardLimit = AppSettings.defaultDailyNewCardLimit
    @State private var settingsErrorMessage: String?
    @State private var lastHandledReviewStartRequest = 0
    private let senseReviewRepository: any SenseReviewRepository
    private let appSettingsRepository: any AppSettingsRepository
    private let vocabularyRepository: any VocabularyRepository
    private let aiProvider: any AIProvider
    private let dailyNewCardPolicy = DailyNewCardPolicy()
    let reviewStartRequest: Int
    let refreshToken: Int
    let onReviewStartRequestHandled: () -> Void
    let onReviewCompleted: () -> Void

    init(
        vocabularyRepository: any VocabularyRepository,
        reviewStateRepository: any ReviewStateRepository,
        reviewSessionRepository: any ReviewSessionRepository,
        vocabularySenseRepository: any VocabularySenseRepository,
        senseReviewRepository: any SenseReviewRepository,
        appSettingsRepository: any AppSettingsRepository,
        aiProvider: any AIProvider,
        reviewStartRequest: Int,
        refreshToken: Int,
        onReviewStartRequestHandled: @escaping () -> Void,
        onReviewCompleted: @escaping () -> Void
    ) {
        _model = State(
            initialValue: VocabularySnapshotModel(
                vocabularyRepository: vocabularyRepository,
                reviewStateRepository: reviewStateRepository,
                reviewSessionRepository: reviewSessionRepository,
                vocabularySenseRepository: vocabularySenseRepository,
                senseReviewRepository: senseReviewRepository
            )
        )
        self.senseReviewRepository = senseReviewRepository
        self.appSettingsRepository = appSettingsRepository
        self.vocabularyRepository = vocabularyRepository
        self.aiProvider = aiProvider
        self.reviewStartRequest = reviewStartRequest
        self.refreshToken = refreshToken
        self.onReviewStartRequestHandled = onReviewStartRequestHandled
        self.onReviewCompleted = onReviewCompleted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                AppPageHeader(
                    eyebrow: "Today",
                    title: todayTitle,
                    subtitle: "先完成今天该复习的词，再回到阅读。",
                    tint: AppTheme.pink
                )

                if model.isLoading && model.cards.isEmpty {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if let errorMessage = model.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else {
                    summary
                    if let settingsErrorMessage {
                        Label(settingsErrorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    recentlyAdded
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 30)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .appPageBackground()
        .navigationTitle("Today")
        .task(id: refreshToken) { await load() }
        .onChange(of: reviewStartRequest) { _, request in
            handleReviewStartRequest(request)
        }
        .sheet(isPresented: $isReviewing, onDismiss: {
            Task {
                await load()
                onReviewCompleted()
            }
        }) {
            ReviewSessionView(
                repository: senseReviewRepository,
                appSettingsRepository: appSettingsRepository,
                vocabularyRepository: vocabularyRepository,
                aiProvider: aiProvider
            )
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 26) {
                VStack(alignment: .leading, spacing: 13) {
                    AppPill(
                        text: dueCount > 0 ? "今天的复习计划" : "今天的学习计划",
                        tint: dueCount > 0 ? AppTheme.orange : AppTheme.yellow
                    )
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(dueCount + newCount)")
                            .font(.system(size: 48, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.graphite)
                            .monospacedDigit()
                        Text("个词义待学习")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(AppTheme.warmSecondary)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text(reviewSummary)
                            .font(.callout)
                            .foregroundStyle(AppTheme.warmSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if shouldShowDailyNewCardQuota {
                            Label(
                                "今日新词额度：已学 \(consumedNewCardsToday) · 上限 \(dailyNewCardLimit)",
                                systemImage: "sparkles"
                            )
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.yellow)
                        }
                    }

                    Button {
                        isReviewing = true
                    } label: {
                        Label("开始约 \(estimatedMinutes) 分钟复习", systemImage: "play.fill")
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .disabled(dueCount + newCount == 0)
                }

                Spacer(minLength: 12)

                ZStack {
                    Circle()
                        .stroke(AppTheme.violet.opacity(0.22), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: reviewRingProgress)
                        .stroke(
                            AppTheme.cyan,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("约 \(estimatedMinutes)")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("分钟")
                            .font(.caption)
                            .foregroundStyle(AppTheme.warmSecondary)
                    }
                }
                .frame(width: 118, height: 118)
            }
            .appHeroCard(
                padding: 26,
                tint: AppTheme.violet,
                secondaryTint: AppTheme.pink
            )

        }
    }

    @ViewBuilder
    private var recentlyAdded: some View {
        let cards = model.cards.filter { Calendar.current.isDateInToday($0.createdAt) }
        Group {
            if !cards.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeading(
                "Added Today",
                subtitle: "今天新加入的词，会在之后的复习中出现。",
                symbol: "tray.and.arrow.down",
                tint: AppTheme.pink
            )

                ForEach(Array(cards.prefix(6).enumerated()), id: \.element.id) { index, card in
                    HStack(spacing: 12) {
                        AppIconBadge(
                            symbol: "character.cursor.ibeam",
                            tint: recentTint(index),
                            size: 28
                        )
                        Text(card.term)
                            .font(.callout.weight(.semibold))
                        Text(card.translationZH)
                            .foregroundStyle(AppTheme.warmSecondary)
                            .lineLimit(1)
                        Spacer()
                        RelativeDateText(date: card.createdAt)
                            .font(.caption)
                            .foregroundStyle(AppTheme.warmSecondary.opacity(0.72))
                    }
                    .padding(.vertical, 3)
                    if card.id != cards.prefix(6).last?.id {
                        Divider().overlay(AppTheme.divider)
                    }
            }
        }
        .appCard(padding: 20, shadow: false)
            }
        }
    }

    private var dueCount: Int { model.dueReviewSenses().count }

    private func recentTint(_ index: Int) -> Color {
        let palette: [Color] = [
            AppTheme.pink,
            AppTheme.cyan,
            AppTheme.yellow,
            AppTheme.violet,
            AppTheme.orange,
            AppTheme.accent
        ]
        return palette[index % palette.count]
    }
    private var consumedNewCardsToday: Int {
        dailyNewCardPolicy.consumedCount(from: model.reviewLogs, on: Date())
    }
    private var remainingNewCardQuota: Int {
        max(0, dailyNewCardLimit - consumedNewCardsToday)
    }
    private var newCount: Int {
        min(model.newSenses().count, remainingNewCardQuota)
    }
    private var estimatedMinutes: Int {
        let cardsToStudy = dueCount + newCount
        return cardsToStudy == 0 ? 0 : max(1, Int(ceil(Double(cardsToStudy) * 0.5)))
    }

    private var reviewRingProgress: Double {
        guard estimatedMinutes > 0 else { return 0 }
        return min(1, Double(estimatedMinutes) / 15)
    }

    private var reviewSummary: String {
        if dailyNewCardLimit == 0, !model.newSenses().isEmpty {
            return dueCount == 0
                ? "每日新词义额度设为 0；今天没有到期词义。"
                : "每日新词义额度设为 0，本次只复习 \(dueCount) 个到期词义。"
        }
        if dueCount + newCount == 0 {
            if !model.newSenses().isEmpty, remainingNewCardQuota == 0 {
                return "今天没有到期词义；新词额度也已用完。"
            }
            return "今天没有需要复习的词义。"
        }
        if dueCount > 0, newCount > 0 {
            return "\(dueCount) 个到期复习 · 本次加入 \(newCount) 个新词义 · 词库共 \(model.cards.count) 个词。"
        }
        if dueCount > 0 {
            return "\(dueCount) 个到期复习 · 词库共 \(model.cards.count) 个词。"
        }
        return "本次学习 \(newCount) 个新词义 · 词库共 \(model.cards.count) 个词。"
    }

    private var shouldShowDailyNewCardQuota: Bool {
        dailyNewCardLimit > 0 && (!model.newSenses().isEmpty || consumedNewCardsToday > 0)
    }

    private var todayTitle: String {
        if dueCount > 0 { return "今天有 \(dueCount) 个词义等你复习" }
        if newCount > 0 { return "今天可以学习 \(newCount) 个新词义" }
        return "今天的学习已完成"
    }

    private func load() async {
        await model.load()
        do {
            dailyNewCardLimit = try await appSettingsRepository.fetch().dailyNewCardLimit
            settingsErrorMessage = nil
        } catch {
            settingsErrorMessage = "无法读取每日新词义额度，暂按 20 处理。"
            dailyNewCardLimit = AppSettings.defaultDailyNewCardLimit
        }
        handleReviewStartRequest(reviewStartRequest)
    }

    private func handleReviewStartRequest(_ request: Int) {
        guard request > 0, request != lastHandledReviewStartRequest else { return }
        lastHandledReviewStartRequest = request
        isReviewing = true
        onReviewStartRequestHandled()
    }

}
