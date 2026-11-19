import Charts
import SwiftUI
import VocabularyCore

struct StatisticsView: View {
    private enum ActivityRange: Int, CaseIterable, Identifiable {
        case seven = 7
        case thirty = 30

        var id: Int { rawValue }
        var title: String { "\(rawValue) 天" }
    }

    @State private var model: VocabularySnapshotModel
    @State private var activityRange: ActivityRange = .seven
    private let calculator = StatisticsCalculator()
    private let diagnosticsPlanner = LearningDiagnosticsPlanner()
    let refreshToken: Int

    init(
        vocabularyRepository: any VocabularyRepository,
        reviewStateRepository: any ReviewStateRepository,
        reviewSessionRepository: any ReviewSessionRepository,
        vocabularySenseRepository: any VocabularySenseRepository,
        senseReviewRepository: any SenseReviewRepository,
        refreshToken: Int
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
        self.refreshToken = refreshToken
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                AppPageHeader(
                    eyebrow: "Statistics",
                    title: "了解你的学习节奏",
                    subtitle: "查看词库进度、复习习惯，以及值得优先回看的词。",
                    tint: AppTheme.orange
                )

                if model.isLoading && model.cards.isEmpty {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if let errorMessage = model.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else {
                    learningOverview
                    reviewPulse
                    reviewActivity
                    recentReviews
                    wordsToRevisit
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 30)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .appPageBackground()
        .navigationTitle("Statistics")
        .task(id: refreshToken) { await model.load() }
    }

    private var learningOverview: some View {
        HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                AppPill(text: "词库概览", tint: AppTheme.yellow)
                Text("\(statistics.totalMeanings)")
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .tracking(-1)
                    .foregroundStyle(AppTheme.graphite)
                    .monospacedDigit()
                Text("个学习词义")
                    .font(.callout)
                    .foregroundStyle(AppTheme.warmSecondary)
                Text("来自 \(statistics.totalWords) 个词条")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warmSecondary.opacity(0.78))
            }
            .frame(width: 170, alignment: .leading)

            Rectangle()
                .fill(AppTheme.divider)
                .frame(width: 1, height: 112)

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("已建立基础")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(AppTheme.graphite)
                        Text("处于熟悉或已掌握阶段的词义")
                            .font(.caption)
                            .foregroundStyle(AppTheme.warmSecondary)
                    }
                    Spacer()
                    Text("\(establishedPercent)%")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.cyan)
                        .monospacedDigit()
                }
                ProgressView(value: Double(establishedPercent), total: 100)
                    .tint(AppTheme.cyan)

                HStack(spacing: 22) {
                    masteryBreakdown("已掌握", statistics.count(.mastered), AppTheme.accent)
                    masteryBreakdown("熟悉", statistics.count(.familiar), AppTheme.cyan)
                    masteryBreakdown("学习中", statistics.count(.learning), AppTheme.orange)
                    masteryBreakdown("待学习", statistics.count(.new), AppTheme.violet)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .appHeroCard(
            padding: 24,
            tint: AppTheme.orange,
            secondaryTint: AppTheme.pink
        )
    }

    private var reviewPulse: some View {
        HStack(spacing: 15) {
            AppInlineMetric(
                title: "今天到期词义",
                value: "\(statistics.dueToday)",
                symbol: "calendar.badge.clock",
                tint: statistics.dueToday > 0 ? AppTheme.orange : AppTheme.yellow
            )
            pulseDivider
            AppInlineMetric(
                title: "本周新增词义",
                value: "\(statistics.thisWeekAdded)",
                symbol: "calendar.badge.plus",
                tint: AppTheme.violet
            )
            pulseDivider
            AppInlineMetric(
                title: "本周完成复习",
                value: "\(statistics.thisWeekReviewed)",
                symbol: "rectangle.stack.badge.play",
                tint: AppTheme.cyan
            )
        }
        .appCard(padding: 18, shadow: false)
    }

    private var establishedPercent: Int {
        guard statistics.totalMeanings > 0 else { return 0 }
        let count = statistics.count(.mastered) + statistics.count(.familiar)
        return Int((Double(count) / Double(statistics.totalMeanings) * 100).rounded())
    }

    private var pulseDivider: some View {
        Rectangle()
            .fill(AppTheme.divider)
            .frame(width: 1, height: 42)
    }

    private func masteryBreakdown(_ title: String, _ value: Int, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(AppTheme.warmSecondary)
            }
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.graphite)
                .monospacedDigit()
        }
    }

    private var reviewActivity: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                AppSectionHeading(
                    "复习活动",
                    subtitle: "每天完成的复习次数",
                    symbol: "chart.xyaxis.line",
                    tint: AppTheme.cyan
                )
                Spacer()
                Picker("Activity Range", selection: $activityRange) {
                    ForEach(ActivityRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            Chart(activity) { item in
                BarMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Reviews", item.reviewCount)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.cyan, AppTheme.violet],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(5)
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
            }
            .chartXAxis {
                AxisMarks(values: .stride(
                    by: .day,
                    count: activityRange == .seven ? 1 : 5
                )) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 180)

            Text("这里记录每天完成的复习次数，不用评分高低定义学习成果。")
                .font(.caption)
                .foregroundStyle(AppTheme.warmSecondary)
        }
        .appCard(padding: 20)
    }

    @ViewBuilder
    private var recentReviews: some View {
        let cardsByID = Dictionary(uniqueKeysWithValues: model.cards.map { ($0.id, $0) })
        let sensesByID = Dictionary(uniqueKeysWithValues: model.senses.map { ($0.id, $0) })
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeading(
                "最近复习",
                subtitle: "最近完成的复习记录。",
                symbol: "clock.arrow.circlepath",
                tint: AppTheme.pink
            )

            if model.reviewLogs.isEmpty {
                Text("完成第一次复习后，这里会显示评分历史。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.reviewLogs.prefix(8)) { log in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cardsByID[log.cardID]?.term ?? "已删除的词")
                                .fontWeight(.medium)
                            if let senseID = log.senseID, let sense = sensesByID[senseID] {
                                Text(sense.translationZH)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.warmSecondary)
                            }
                        }
                        Text(log.rating.displayName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(log.rating.tint)
                        Spacer()
                            RelativeDateText(date: log.reviewedAt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider().overlay(AppTheme.divider)
                }
            }
        }
        .appCard(padding: 20, shadow: false)
    }

    @ViewBuilder
    private var wordsToRevisit: some View {
        let cardsByID = Dictionary(uniqueKeysWithValues: model.cards.map { ($0.id, $0) })
        let sensesByID = Dictionary(uniqueKeysWithValues: model.senses.map { ($0.id, $0) })
        let diagnostics = learningDiagnostics

        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeading(
                "建议优先回看",
                subtitle: "只显示有明确客观信号的词义，并给出下一步动作。",
                symbol: "arrow.trianglehead.2.clockwise.rotate.90",
                tint: AppTheme.orange
            )

            if diagnostics.isEmpty {
                Text("暂时没有需要特别干预的词义，按 Today 的正常节奏继续即可。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(diagnostics) { diagnostic in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(cardsByID[diagnostic.cardID]?.term ?? "已删除的词")
                                .fontWeight(.medium)
                            Text(sensesByID[diagnostic.senseID]?.translationZH ?? "词义已删除")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(diagnostic.signal.explanationZH)
                                .font(.caption)
                                .foregroundStyle(AppTheme.warmSecondary)
                        }
                        Spacer()
                        AppPill(
                            text: diagnostic.suggestedPrompt.actionTitleZH,
                            tint: diagnostic.suggestedPrompt.tint
                        )
                    }
                    Divider().overlay(AppTheme.divider)
                }
            }
        }
        .appCard(padding: 20, shadow: false)
    }

    private var statistics: VocabularyStatistics {
        calculator.calculate(
            cards: model.cards,
            senses: model.senses,
            reviewStates: model.senseReviewStates,
            reviewLogs: model.reviewLogs,
            now: Date()
        )
    }

    private var learningRecords: [SenseLearningRecord] {
        let cardsByID = Dictionary(uniqueKeysWithValues: model.cards.map { ($0.id, $0) })
        return model.senses.compactMap { sense in
            guard let card = cardsByID[sense.cardID], let state = model.state(for: sense) else {
                return nil
            }
            return SenseLearningRecord(
                card: card,
                sense: sense,
                state: state,
                encounters: model.encounters(for: sense),
                reviewLogs: model.reviewLogs
            )
        }
    }

    private var learningDiagnostics: [LearningDiagnostic] {
        diagnosticsPlanner.rankedDiagnostics(from: learningRecords, now: Date(), limit: 4)
    }

    private var activity: [DailyReviewActivity] {
        Array(statistics.dailyReviewActivity.suffix(activityRange.rawValue))
    }

}

private extension LearningDiagnosticSignal {
    var explanationZH: String {
        switch self {
        case .repeatedForgetting: "近期反复忘记，先换一种提取线索。"
        case .sustainedDifficulty: "连续觉得困难，单纯重复已经不够。"
        case .overdue: "已经逾期，先恢复一次主动回忆。"
        case .narrowContext: "只在很少的语境里遇到，含义还不够稳。"
        case .missingLearningSupport: "缺少音标或记忆线索，学习支架不完整。"
        }
    }
}

private extension AdaptiveReviewPrompt {
    var actionTitleZH: String {
        switch self {
        case .recognition: "主动回忆"
        case .listening: "听音辨义"
        case .contextCloze: "语境填空"
        case .spelling: "拼写回忆"
        case .contrast: "易混辨析"
        }
    }

    var tint: Color {
        switch self {
        case .recognition: AppTheme.yellow
        case .listening: AppTheme.cyan
        case .contextCloze: AppTheme.pink
        case .spelling: AppTheme.violet
        case .contrast: AppTheme.orange
        }
    }
}
