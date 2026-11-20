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
            VStack(alignment: .leading, spacing: 24) {
                AppPageHeader(
                    eyebrow: Date().formatted(.dateTime.month(.wide).day().weekday(.wide)),
                    title: todayTitle,
                    subtitle: "先完成今天该复习的词，再回到阅读。"
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
                    rhythmCard
                    // Two columns when there is room, stacked otherwise.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            masteryCard.frame(minWidth: 300)
                            recentlyAdded.frame(minWidth: 300)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 16) {
                            masteryCard
                            recentlyAdded
                        }
                    }
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
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(dueCount + newCount)")
                        .font(AppTheme.display(52))
                        .foregroundStyle(AppTheme.graphite)
                        .monospacedDigit()
                    Text("个词义待学习")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(AppTheme.warmSecondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(reviewSummary)
                        .font(.callout)
                        .foregroundStyle(AppTheme.warmSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if shouldShowDailyNewCardQuota {
                        Text("今日新词额度：已学 \(consumedNewCardsToday) · 上限 \(dailyNewCardLimit)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.warmSecondary)
                    }
                }
                Button {
                    isReviewing = true
                } label: {
                    Label("开始约 \(estimatedMinutes) 分钟复习", systemImage: "play.fill")
                }
                .buttonStyle(AppPrimaryButtonStyle())
                .disabled(dueCount + newCount == 0)
                .padding(.top, 4)
            }

            Spacer(minLength: 12)

            if !fanItems.isEmpty {
                // The handwritten aside only appears when there is room for it beside the cards.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 8) {
                        PaintedHandNote(lines: fanNoteLines)
                        WordCardFan(items: fanItems, caption: fanCaption)
                    }
                    // Narrow windows: the note sits under the cards, without the arrow.
                    VStack(spacing: 6) {
                        WordCardFan(items: fanItems)
                        PaintedHandNote(lines: [fanNoteLines.joined()], showsArrow: false)
                        if let fanCaption {
                            Text(fanCaption)
                                .font(.caption)
                                .foregroundStyle(AppTheme.warmSecondary)
                        }
                    }
                }
                .padding(.trailing, 18)
            }
        }
        .appHeroCard(padding: 28)
    }

    @ViewBuilder
    private var recentlyAdded: some View {
        let addedToday = model.cards.filter { Calendar.current.isDateInToday($0.createdAt) }
        let showsToday = !addedToday.isEmpty
        let cards = Array((showsToday ? addedToday : model.cards.sorted { $0.createdAt > $1.createdAt }).prefix(5))
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                AppSectionHeading(
                    showsToday ? "今天新加入" : "最近收录",
                    subtitle: showsToday ? "会在之后的复习中出现" : "按加入时间排列"
                )
                VStack(spacing: 0) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(card.term)
                                .font(AppTheme.display(15))
                                .foregroundStyle(AppTheme.graphite)
                                .lineLimit(1)
                            Text(card.translationZH)
                                .font(.callout)
                                .foregroundStyle(AppTheme.warmSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            RelativeDateText(date: card.createdAt)
                                .font(.caption)
                                .foregroundStyle(AppTheme.warmSecondary)
                        }
                        .padding(.vertical, 8)
                        if index < cards.count - 1 {
                            Divider().overlay(AppTheme.divider)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .appCard(padding: 20, shadow: false)
        }
    }

    private var dueCount: Int { model.dueReviewSenses().count }

    // MARK: Rhythm (all values come from local review logs and sense states)

    private var rhythmCard: some View {
        HStack(alignment: .top, spacing: 0) {
            rhythmColumn(title: "近 7 天复习", value: "\(reviewsPerDayThisWeek.reduce(0) { $0 + $1.count })", unit: "次") {
                weekBars
            }
            Divider().overlay(AppTheme.divider).padding(.horizontal, 20)
            rhythmColumn(title: "连续学习", value: "\(studyStreak)", unit: "天") {
                Text(studyStreak == 0 ? "今天复习一次就开始计数" : "保持每天至少复习一次")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warmSecondary)
            }
            Divider().overlay(AppTheme.divider).padding(.horizontal, 20)
            rhythmColumn(title: "已熟悉", value: "\(settledSenseCount)", unit: "/ \(model.senses.count)") {
                Text("熟悉或已掌握的词义")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warmSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .appCard(padding: 20, shadow: false)
    }

    private func rhythmColumn<Footer: View>(
        title: String,
        value: String,
        unit: String,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.warmSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(AppTheme.display(28))
                    .foregroundStyle(AppTheme.graphite)
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(AppTheme.warmSecondary)
            }
            footer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weekBars: some View {
        let counts = reviewsPerDayThisWeek
        let peak = max(counts.map(\.count).max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(counts.enumerated()), id: \.offset) { index, day in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(index == counts.count - 1 ? AppTheme.accent : AppTheme.lilac)
                    .frame(width: 8, height: 4 + 18 * CGFloat(day.count) / CGFloat(peak))
                    .help("\(day.date.formatted(.dateTime.month().day()))：\(day.count) 次")
            }
        }
        .frame(height: 22, alignment: .bottom)
    }

    private var reviewsPerDayThisWeek: [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        var counts: [Date: Int] = [:]
        for log in model.reviewLogs {
            counts[calendar.startOfDay(for: log.reviewedAt), default: 0] += 1
        }
        return days.map { ($0, counts[$0] ?? 0) }
    }

    /// Consecutive days with at least one review, ending today (or yesterday if today has none yet).
    private var studyStreak: Int {
        let calendar = Calendar.current
        let reviewDays = Set(model.reviewLogs.map { calendar.startOfDay(for: $0.reviewedAt) })
        var day = calendar.startOfDay(for: Date())
        if !reviewDays.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while reviewDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    private var settledSenseCount: Int {
        model.senses.filter {
            let level = model.mastery(for: $0)
            return level == .familiar || level == .mastered
        }.count
    }

    // MARK: Mastery distribution

    @ViewBuilder
    private var masteryCard: some View {
        let total = model.senses.count
        if total > 0 {
            let levels: [MasteryLevel] = [.new, .learning, .familiar, .mastered]
            let counts = Dictionary(grouping: model.senses, by: { model.mastery(for: $0) }).mapValues(\.count)
            VStack(alignment: .leading, spacing: 14) {
                AppSectionHeading("学习阶段", subtitle: "全部 \(total) 个词义")
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(levels, id: \.self) { level in
                            let count = counts[level] ?? 0
                            if count > 0 {
                                Rectangle()
                                    .fill(masteryColor(level))
                                    .frame(width: max(4, (proxy.size.width - 6) * CGFloat(count) / CGFloat(total)))
                            }
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 8)
                VStack(spacing: 8) {
                    ForEach(levels, id: \.self) { level in
                        HStack(spacing: 8) {
                            Circle().fill(masteryColor(level)).frame(width: 7, height: 7)
                            Text(level.displayName)
                                .font(.callout)
                                .foregroundStyle(AppTheme.graphite)
                            Spacer()
                            Text("\(counts[level] ?? 0)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(AppTheme.warmSecondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .appCard(padding: 20, shadow: false)
        }
    }

    /// One-hue ramp: lighter = earlier stage.
    private func masteryColor(_ level: MasteryLevel) -> Color {
        switch level {
        case .new: AppTheme.lilac.opacity(0.7)
        case .learning: AppTheme.grape.opacity(0.6)
        case .familiar: AppTheme.grape
        case .mastered: AppTheme.accentStrong
        }
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

    /// Up to three real words for today's session: most overdue first, then new senses.
    private var fanSenses: [VocabularySense] {
        let due = model.dueReviewSenses().sorted {
            (model.state(for: $0)?.dueAt ?? .distantFuture) < (model.state(for: $1)?.dueAt ?? .distantFuture)
        }
        let fresh = model.newSenses().sorted { $0.createdAt < $1.createdAt }.prefix(newCount)
        return Array((due + fresh).prefix(3))
    }

    private var fanItems: [WordCardFanItem] {
        let cardsByID = Dictionary(uniqueKeysWithValues: model.cards.map { ($0.id, $0) })
        return fanSenses.compactMap { sense in
            guard let card = cardsByID[sense.cardID] else { return nil }
            return WordCardFanItem(
                id: sense.id,
                term: card.term,
                meaning: sense.translationZH,
                language: card.languageCode.rawValue.uppercased()
            )
        }
    }

    private var fanNoteLines: [String] {
        switch fanItems.count {
        case 1: return ["先从这一个", "开始吧"]
        case 2: return ["先从这两个", "开始吧"]
        default: return ["先从这三个", "开始吧"]
        }
    }

    private var fanCaption: String? {
        let remaining = dueCount + newCount - fanItems.count
        return remaining > 0 ? "还有 \(remaining) 个词义在等你" : nil
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
