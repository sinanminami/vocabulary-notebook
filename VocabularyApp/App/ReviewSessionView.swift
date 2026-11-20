import SwiftUI
import VocabularyCore

struct ReviewSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ReviewSessionModel
    @State private var pronouncer = WordPronouncer()
    @State private var pronunciationActionCardID: UUID?
    @State private var pronunciationErrorMessage: String?

    private let vocabularyRepository: any VocabularyRepository
    private let aiProvider: any AIProvider

    init(
        repository: any SenseReviewRepository,
        appSettingsRepository: any AppSettingsRepository,
        vocabularyRepository: any VocabularyRepository,
        aiProvider: any AIProvider
    ) {
        _model = State(initialValue: ReviewSessionModel(
            repository: repository,
            appSettingsRepository: appSettingsRepository,
            vocabularyRepository: vocabularyRepository
        ))
        self.vocabularyRepository = vocabularyRepository
        self.aiProvider = aiProvider
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AppTheme.divider)
            content
        }
        .background(AppTheme.canvas)
        .tint(AppTheme.accent)
        .frame(minWidth: 720, idealWidth: 800, minHeight: 570, idealHeight: 650)
        .task { await model.load() }
        .task(id: model.currentPresentationToken) {
            guard model.currentItem != nil else { return }
            pronounceCurrentCard()
        }
        .onDisappear { pronouncer.stop() }
        .onExitCommand { dismiss() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            AppIconBadge(
                symbol: "rectangle.stack.badge.play",
                tint: AppTheme.cyan,
                size: 36
            )

            if model.currentItem != nil {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("Review Session")
                            .font(.headline)
                            .foregroundStyle(AppTheme.graphite)
                            .fixedSize(horizontal: true, vertical: false)
                        Text("\(model.currentIndex + 1) of \(model.queue.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.warmSecondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    ProgressView(
                        value: Double(model.currentIndex),
                        total: Double(max(1, model.queue.count))
                    )
                    .tint(AppTheme.accent)
                    .frame(width: 180)
                }

                if model.newCardsIncluded > 0 {
                    AppPill(text: "\(model.newCardsIncluded) new", tint: AppTheme.yellow)
                }
            } else {
                Text("Review Session")
                    .font(.headline)
                    .foregroundStyle(AppTheme.graphite)
            }

            Spacer()

            Picker("Mode", selection: $model.sessionMode) {
                Text("自适应").tag(ReviewSessionMode.adaptive)
                Text("英 → 中").tag(ReviewSessionMode.termToMeaning)
                Text("中 → 英").tag(ReviewSessionMode.meaningToTerm)
            }
            .pickerStyle(.segmented)
            .frame(width: 255)
            .help("自适应模式会依据当前词义的遗忘、难度和语境覆盖选择题型")

            Button("Done") { dismiss() }
                .buttonStyle(AppQuietButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(AppTheme.surface.opacity(0.84))
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            VStack(spacing: 14) {
                ProgressView().controlSize(.regular)
                Text("Preparing your review…")
                    .foregroundStyle(AppTheme.warmSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = model.errorMessage, model.currentItem == nil {
            ContentUnavailableView(
                "Unable to Load Review",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if model.isComplete {
            completionView
        } else if let item = model.currentItem {
            reviewCard(item)
        }
    }

    private var completionView: some View {
        VStack(spacing: 18) {
            AppIconBadge(symbol: "checkmark", tint: AppTheme.accent, size: 58)
            VStack(spacing: 6) {
                Text("You’re done for today.")
                    .font(.system(size: 27, weight: .semibold, design: .serif))
                    .foregroundStyle(AppTheme.graphite)
                Text("完成 \(model.initialMeaningCount) 个词义 · 共 \(model.reviewAttempts) 次主动回忆")
                    .foregroundStyle(AppTheme.warmSecondary)
            }
            Button("Finish") { dismiss() }
                .buttonStyle(AppPrimaryButtonStyle())
        }
        .padding(42)
        .appCard(padding: 0)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reviewCard(_ item: SenseReviewQueueItem) -> some View {
        ScrollView {
            VStack(spacing: model.isAnswerShown ? 28 : 20) {
            VStack(spacing: 22) {
                AppPill(
                    text: promptTitle,
                    tint: promptTint
                )

                if item.card.encounterCount > 1 || !item.sense.isPrimary {
                    AppPill(
                        text: "MEANING \(item.sense.sortOrder + 1)",
                        tint: item.sense.isPrimary ? AppTheme.cyan : AppTheme.pink
                    )
                }


                if model.isCurrentItemRequeued {
                    AppPill(text: "再巩固一次", tint: AppTheme.orange)
                }

                VStack(spacing: 8) {
                    Text(prompt(for: item))
                        .font(.system(
                            size: model.currentPrompt == .contextCloze ? 30 : 42,
                            weight: .semibold,
                            design: .serif
                        ))
                        .foregroundStyle(AppTheme.graphite)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                    pronunciationLine(for: item.card)
                }

                Button {
                    pronounceCurrentCard()
                } label: {
                    Label("Listen Again", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(AppQuietButtonStyle())
                .help("Replay pronunciation")
                .accessibilityLabel("Replay pronunciation")

                if model.isAnswerShown {
                    Divider().overlay(AppTheme.divider)
                        .padding(.horizontal, 20)
                    answer(for: item)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    if model.isHintShown, let insight = item.sense.memoryInsight {
                        reviewHint(insight)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    Text(promptGuidance)
                        .font(.callout)
                        .foregroundStyle(AppTheme.warmSecondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 10) {
                        if item.sense.memoryInsight != nil, !model.isHintShown {
                            Button("给我一个提示", systemImage: "lightbulb") {
                                withAnimation(.easeOut(duration: 0.2)) { model.showHint() }
                            }
                            .buttonStyle(AppQuietButtonStyle())
                        }
                        Button("Reveal Answer", systemImage: "eye") {
                            withAnimation(.easeOut(duration: 0.2)) { model.showAnswer() }
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                        .keyboardShortcut(.space, modifiers: [])
                    }
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: 650, minHeight: model.isAnswerShown ? 315 : 300)
            .appHeroCard(padding: 0)

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if model.isAnswerShown {
                VStack(spacing: 9) {
                    Text("选择最接近真实回忆情况的一项")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.warmSecondary)
                    ratingButtons
                    Text("诚实选择能让下次复习时间更合适。可按 1–4 快速评分。")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.warmSecondary.opacity(0.78))
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 34)
        .padding(.top, 26)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, minHeight: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func prompt(for item: SenseReviewQueueItem) -> String {
        switch model.currentPrompt {
        case .recognition, .contrast:
            return item.card.term
        case .listening:
            return "听发音，回忆含义"
        case .contextCloze:
            return model.currentClozeSentence ?? item.sense.translationZH
        case .spelling:
            return item.sense.translationZH
        }
    }

    private func answer(for item: SenseReviewQueueItem) -> some View {
        VStack(spacing: 11) {
            Text(answerTitle(for: item))
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.graphite)
                .textSelection(.enabled)
            if shouldShowSeparateTranslation {
                Text(item.sense.translationZH)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.yellow)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            if !item.sense.definitionEN.isEmpty {
                Text(item.sense.definitionEN)
                    .foregroundStyle(AppTheme.warmSecondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            if !item.sense.exampleSentence.isEmpty {
                Text(item.sense.exampleSentence)
                    .font(.callout.italic())
                    .foregroundStyle(AppTheme.graphite.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding(.top, 2)
            }
            if let insight = item.sense.memoryInsight {
                Divider().overlay(AppTheme.divider)
                    .padding(.vertical, 4)
                MemoryInsightContent(insight: insight, compact: true)
                    .padding(14)
                    .background(
                        AppTheme.yellow.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
            }
        }
        .frame(maxWidth: 560)
    }

    @ViewBuilder
    private func pronunciationLine(for card: VocabularyCard) -> some View {
        if card.pronunciationIPA.isEmpty {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text("音标尚未生成")
                        .font(.caption)
                        .foregroundStyle(AppTheme.warmSecondary.opacity(0.72))
                    Button("AI 生成音标", systemImage: "waveform") {
                        Task { await generatePronunciation(for: card) }
                    }
                    .buttonStyle(AppQuietButtonStyle())
                    .controlSize(.small)
                    .disabled(pronunciationActionCardID != nil)

                    if pronunciationActionCardID == card.id {
                        ProgressView().controlSize(.small)
                    }
                }

                if let pronunciationErrorMessage {
                    Text(pronunciationErrorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        } else {
            Text(card.pronunciationIPA)
                .font(.system(.title3, design: .monospaced).weight(.medium))
                .foregroundStyle(AppTheme.cyan)
                .textSelection(.enabled)
        }
    }

    private func reviewHint(_ insight: MemoryInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(AppTheme.yellow)
                Text(insight.strategy.displayNameZH)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.yellow)
                Text(insight.titleZH)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.graphite)
            }
            if [.recognition, .listening, .contrast].contains(model.currentPrompt),
               let breakdown = insight.breakdown {
                Text(breakdown)
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .foregroundStyle(AppTheme.cyan)
            }
            Text(insight.cueZH)
                .font(.callout)
                .foregroundStyle(AppTheme.graphite.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: 540, alignment: .leading)
        .background(AppTheme.yellow.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(AppTheme.yellow.opacity(0.18), lineWidth: 0.8)
        }
    }

    private func pronounceCurrentCard() {
        guard let card = model.currentItem?.card else { return }
        pronouncer.speak(term: card.term, languageCode: card.languageCode)
    }

    private var promptTitle: String {
        switch model.currentPrompt {
        case .recognition: "RECALL THE MEANING"
        case .listening: "LISTEN & RECALL"
        case .contextCloze: "COMPLETE THE CONTEXT"
        case .spelling: "SPELL FROM THE MEANING"
        case .contrast: "TELL THE DIFFERENCE"
        }
    }

    private var promptTint: Color {
        switch model.currentPrompt {
        case .recognition: AppTheme.yellow
        case .listening: AppTheme.cyan
        case .contextCloze: AppTheme.pink
        case .spelling: AppTheme.violet
        case .contrast: AppTheme.orange
        }
    }

    private var promptGuidance: String {
        switch model.currentPrompt {
        case .recognition: "先主动回忆含义，再揭晓答案。"
        case .listening: "先听声音，再回忆这个词义。"
        case .contextCloze: "在语境中补出最自然的词，再揭晓答案。"
        case .spelling: "在心里完整拼写后再揭晓答案。"
        case .contrast: "先说出含义，再想它与易混词的边界。"
        }
    }

    private func answerTitle(for item: SenseReviewQueueItem) -> String {
        switch model.currentPrompt {
        case .recognition, .contrast:
            item.sense.translationZH
        case .listening:
            "\(item.card.term) · \(item.sense.translationZH)"
        case .contextCloze, .spelling:
            item.card.term
        }
    }

    private var shouldShowSeparateTranslation: Bool {
        model.currentPrompt == .contextCloze || model.currentPrompt == .spelling
    }

    private func generatePronunciation(for card: VocabularyCard) async {
        guard pronunciationActionCardID == nil else { return }
        pronunciationActionCardID = card.id
        pronunciationErrorMessage = nil
        defer { pronunciationActionCardID = nil }

        do {
            let pronunciation = try await aiProvider.generatePronunciationIPA(
                request: PronunciationGenerationRequest(
                    term: card.term,
                    languageCode: card.languageCode
                )
            )
            let updatedCard = try await vocabularyRepository.setPronunciationIPA(
                id: card.id,
                pronunciationIPA: pronunciation,
                at: Date()
            )
            model.replaceCurrentCard(with: updatedCard)
        } catch {
            pronunciationErrorMessage = "无法生成音标：\(error.localizedDescription)"
        }
    }

    private var ratingButtons: some View {
        HStack(spacing: 10) {
            ratingButton(.again, key: "1")
            ratingButton(.hard, key: "2")
            ratingButton(.good, key: "3")
            ratingButton(.easy, key: "4")
        }
        .frame(maxWidth: 650)
        .disabled(model.isSubmitting)
    }

    private func ratingButton(_ rating: ReviewRating, key: KeyEquivalent) -> some View {
        Button {
            Task { await model.rate(rating) }
        } label: {
            VStack(spacing: 7) {
                HStack(spacing: 6) {
                    Circle().fill(rating.tint).frame(width: 7, height: 7)
                    Text(rating.displayName)
                        .font(.callout.weight(.semibold))
                }
                Text(intervalText(for: rating))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.warmSecondary)
            }
            .foregroundStyle(AppTheme.graphite)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(rating.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(rating.tint.opacity(0.20), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: [])
    }

    private func intervalText(for rating: ReviewRating) -> String {
        guard let dueAt = model.previews[rating]?.dueAt else { return "—" }
        let seconds = max(0, dueAt.timeIntervalSinceNow)
        switch seconds {
        case ..<90: return "< 1 分钟"
        case ..<3_600: return "\(Int((seconds / 60).rounded())) 分钟"
        case ..<86_400: return "\(Int((seconds / 3_600).rounded())) 小时"
        case ..<2_592_000: return "\(Int((seconds / 86_400).rounded())) 天"
        case ..<31_536_000: return "\(Int((seconds / 2_592_000).rounded())) 个月"
        default: return "\(Int((seconds / 31_536_000).rounded())) 年"
        }
    }
}

extension ReviewRating {
    var displayName: String {
        switch self {
        case .again: "忘了"
        case .hard: "模糊"
        case .good: "记得"
        case .easy: "很熟"
        }
    }

    var tint: Color {
        switch self {
        case .again: .red
        case .hard: .orange
        case .good: AppTheme.accent
        case .easy: .teal
        }
    }
}
