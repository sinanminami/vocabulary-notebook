import SwiftUI
import VocabularyCore

struct LibraryView: View {
    private enum SortOrder: String, CaseIterable, Identifiable {
        case recentlyAdded = "Recently Added"
        case alphabetical = "Alphabetical"
        case mostEncountered = "Most Encountered"
        case leastMastered = "Least Mastered"
        case recentlyReviewed = "Recently Reviewed"

        var id: Self { self }
    }

    private enum MasteryFilter: String, CaseIterable, Identifiable {
        case all = "All Mastery"
        case new = "New"
        case learning = "Learning"
        case familiar = "Familiar"
        case mastered = "Mastered"

        var id: Self { self }
        var level: MasteryLevel? { self == .all ? nil : MasteryLevel(rawValue: rawValue.lowercased()) }
    }

    private enum DueFilter: String, CaseIterable, Identifiable {
        case all = "All Due Status"
        case due = "Due"
        case new = "New"
        case scheduled = "Scheduled"

        var id: Self { self }
    }

    @State private var model: VocabularySnapshotModel
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .recentlyAdded
    @State private var selectedLanguage = "all"
    @State private var selectedTagID: UUID?
    @State private var masteryFilter: MasteryFilter = .all
    @State private var dueFilter: DueFilter = .all
    @State private var selectedCardID: UUID?
    @State private var editingCard: VocabularyCard?
    @State private var cardPendingDeletion: VocabularyCard?
    @State private var actionErrorMessage: String?
    @State private var isDeleting = false
    @State private var memoryActionCardID: UUID?
    @State private var pronunciationActionCardID: UUID?
    @State private var encounters: [VocabularyEncounter] = []
    @State private var editingSense: VocabularySense?
    @State private var sensePendingDeletion: VocabularySense?
    @State private var senseMemoryActionID: UUID?

    private let vocabularyRepository: any VocabularyRepository
    private let vocabularySenseRepository: any VocabularySenseRepository
    private let senseReviewRepository: any SenseReviewRepository
    private let aiProvider: any AIProvider
    let refreshToken: Int
    let onDataChanged: () -> Void

    init(
        vocabularyRepository: any VocabularyRepository,
        vocabularySenseRepository: any VocabularySenseRepository,
        reviewStateRepository: any ReviewStateRepository,
        senseReviewRepository: any SenseReviewRepository,
        tagRepository: any TagRepository,
        aiProvider: any AIProvider,
        refreshToken: Int,
        onDataChanged: @escaping () -> Void
    ) {
        self.vocabularyRepository = vocabularyRepository
        self.vocabularySenseRepository = vocabularySenseRepository
        self.senseReviewRepository = senseReviewRepository
        self.aiProvider = aiProvider
        _model = State(
            initialValue: VocabularySnapshotModel(
                vocabularyRepository: vocabularyRepository,
                reviewStateRepository: reviewStateRepository,
                vocabularySenseRepository: vocabularySenseRepository,
                senseReviewRepository: senseReviewRepository,
                tagRepository: tagRepository
            )
        )
        self.refreshToken = refreshToken
        self.onDataChanged = onDataChanged
    }

    var body: some View {
        presentationLayer
    }

    private var contentLayer: some View {
        Group {
            if model.isLoading && model.cards.isEmpty {
                ProgressView("Loading Library…")
            } else if let errorMessage = model.errorMessage, model.cards.isEmpty {
                ContentUnavailableView(
                    "无法读取词库",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(errorMessage)
                )
            } else if model.cards.isEmpty {
                ContentUnavailableView(
                    "Library 还是空的",
                    systemImage: "books.vertical",
                    description: Text("按 Command + N 添加第一个单词。")
                )
            } else if visibleCards.isEmpty {
                emptyFilterResult
            } else {
                VStack(spacing: 0) {
                    librarySummaryBar
                    Divider().overlay(AppTheme.divider)

                    if activeFilterCount > 0 {
                        activeFilterBar
                        Divider().overlay(AppTheme.divider)
                    }

                    HSplitView {
                        List(visibleCards, selection: $selectedCardID) { card in
                            cardRow(card)
                                .padding(.vertical, 5)
                                .tag(card.id)
                        }
                        .listStyle(.inset)
                        .scrollContentBackground(.hidden)
                        .background(AppTheme.canvas)
                        .frame(minWidth: 420, idealWidth: 560)

                        if let selectedCard {
                            cardDetail(selectedCard)
                                .frame(minWidth: 320, idealWidth: 400)
                        } else {
                            ContentUnavailableView(
                                "选择一个单词",
                                systemImage: "rectangle.and.hand.point.up.left",
                                description: Text("在左侧选择词条，查看、编辑或删除完整词卡。")
                            )
                            .appPageBackground()
                            .frame(minWidth: 320, idealWidth: 400)
                        }
                    }
                }
            }
        }
        .appPageBackground()
        .navigationTitle("Library")
        .searchable(text: $searchText, prompt: "Search term, meaning, example, or tag")
        .toolbar { libraryToolbar }
        .task(id: refreshToken) { await reloadKeepingSelection() }
        .task(id: selectedCardID) { await loadEncountersForSelectedCard() }
        .onChange(of: visibleCardIDs) { _, ids in
            if let selectedCardID, ids.contains(selectedCardID) { return }
            selectedCardID = ids.first
        }
    }

    private var presentationLayer: some View {
        contentLayer
        .sheet(item: $editingCard, onDismiss: {
            Task {
                await reloadKeepingSelection()
                onDataChanged()
            }
        }) { card in
            EditWordView(
                card: card,
                availableTags: model.tags,
                selectedTagIDs: model.tagIDsByCardID[card.id] ?? [],
                vocabularyRepository: vocabularyRepository,
                aiProvider: aiProvider
            )
        }
        .sheet(item: $editingSense, onDismiss: {
            Task {
                await reloadKeepingSelection()
                onDataChanged()
            }
        }) { sense in
            EditSenseView(
                sense: sense,
                vocabularySenseRepository: vocabularySenseRepository
            )
        }
        .alert(
            "删除这个词条？",
            isPresented: deletionAlertIsPresented,
            presenting: cardPendingDeletion
        ) { card in
            Button("Delete", role: .destructive) {
                Task { await delete(card) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { card in
            Text("“\(card.term)”及其复习状态和历史将从本机永久删除。")
        }
        .alert(
            "删除这个词义？",
            isPresented: senseDeletionAlertIsPresented,
            presenting: sensePendingDeletion
        ) { sense in
            Button("Delete", role: .destructive) {
                Task { await delete(sense) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { sense in
            Text("“\(sense.translationZH)”的相遇记录、排期和复习历史将从本机永久删除。")
        }
        .alert("操作失败", isPresented: actionErrorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "未知错误")
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                Picker("Language", selection: $selectedLanguage) {
                    Text("All Languages").tag("all")
                    ForEach(languageOptions, id: \.rawValue) { language in
                        Text(languageName(language)).tag(language.rawValue)
                    }
                }

                Picker("Tag", selection: $selectedTagID) {
                    Text("All Tags").tag(UUID?.none)
                    ForEach(model.tags) { tag in
                        Text(tag.name).tag(Optional(tag.id))
                    }
                }

                Picker("Mastery", selection: $masteryFilter) {
                    ForEach(MasteryFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }

                Picker("Due Status", selection: $dueFilter) {
                    ForEach(DueFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }

                if activeFilterCount > 0 {
                    Divider()
                    Button("Clear Filters") { clearFilters() }
                }
            } label: {
                Label(
                    activeFilterCount == 0 ? "Filter" : "Filter \(activeFilterCount)",
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            }

            Picker("Sort", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .frame(width: 175)
        }
    }

    @ViewBuilder
    private var emptyFilterResult: some View {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            ContentUnavailableView {
                Label("没有符合筛选条件的词", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("清除部分筛选条件后再试。")
            } actions: {
                Button("Clear Filters") { clearFilters() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var activeFilterBar: some View {
        HStack(spacing: 10) {
            Label("\(activeFilterCount) filters active", systemImage: "line.3.horizontal.decrease.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            filterSummaryPills
            Spacer()
            Button("Clear") { clearFilters() }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(AppTheme.accentSoft.opacity(0.76))
    }

    private var librarySummaryBar: some View {
        HStack(spacing: 14) {
            AppIconBadge(symbol: "books.vertical.fill", tint: AppTheme.violet, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Library")
                    .font(.headline)
                    .foregroundStyle(AppTheme.graphite)
                Text("\(visibleCards.count) shown · \(model.cards.count) total")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warmSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(AppTheme.surface.opacity(0.72))
    }

    @ViewBuilder
    private var filterSummaryPills: some View {
        if selectedLanguage != "all" {
            filterPill(languageName(LanguageCode(rawValue: selectedLanguage)))
        }
        if let selectedTagID, let tag = model.tags.first(where: { $0.id == selectedTagID }) {
            filterPill(tag.name)
        }
        if masteryFilter != .all { filterPill(masteryFilter.rawValue) }
        if dueFilter != .all { filterPill(dueFilter.rawValue) }
    }

    private var visibleCards: [VocabularyCard] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let filtered = model.cards.filter { card in
            let matchesQuery = query.isEmpty
                || card.term.localizedCaseInsensitiveContains(query)
                || card.translationZH.localizedCaseInsensitiveContains(query)
                || card.definitionEN.localizedCaseInsensitiveContains(query)
                || card.exampleSentence.localizedCaseInsensitiveContains(query)
                || model.senses(for: card).contains { sense in
                    sense.translationZH.localizedCaseInsensitiveContains(query)
                        || sense.definitionEN.localizedCaseInsensitiveContains(query)
                        || sense.exampleSentence.localizedCaseInsensitiveContains(query)
                }
                || model.tags(for: card).contains {
                    $0.name.localizedCaseInsensitiveContains(query)
                }
            let matchesLanguage = selectedLanguage == "all"
                || card.languageCode.rawValue == selectedLanguage
            let matchesTag = selectedTagID.map {
                model.tagIDsByCardID[card.id, default: []].contains($0)
            } ?? true
            let matchesMastery = masteryFilter.level.map {
                model.mastery(for: card) == $0
            } ?? true
            let matchesDue = matchesDueFilter(card, at: now)
            return matchesQuery && matchesLanguage && matchesTag && matchesMastery && matchesDue
        }

        switch sortOrder {
        case .recentlyAdded:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .alphabetical:
            return filtered.sorted {
                $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending
            }
        case .mostEncountered:
            return filtered.sorted {
                $0.encounterCount == $1.encounterCount
                    ? $0.updatedAt > $1.updatedAt
                    : $0.encounterCount > $1.encounterCount
            }
        case .leastMastered:
            return filtered.sorted { left, right in
                let leftRank = masteryRank(model.mastery(for: left))
                let rightRank = masteryRank(model.mastery(for: right))
                if leftRank != rightRank { return leftRank < rightRank }
                let leftStability = model.state(for: left)?.stability ?? 0
                let rightStability = model.state(for: right)?.stability ?? 0
                if leftStability != rightStability { return leftStability < rightStability }
                return left.createdAt < right.createdAt
            }
        case .recentlyReviewed:
            return filtered.sorted { left, right in
                let leftDate = model.lastReviewedAt(for: left) ?? .distantPast
                let rightDate = model.lastReviewedAt(for: right) ?? .distantPast
                if leftDate != rightDate { return leftDate > rightDate }
                return left.createdAt > right.createdAt
            }
        }
    }

    private var visibleCardIDs: [UUID] { visibleCards.map(\.id) }

    private func cardRow(_ card: VocabularyCard) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(card.term)
                        .font(.headline)
                        .foregroundStyle(AppTheme.graphite)
                    if !card.pronunciationIPA.isEmpty {
                        Text(card.pronunciationIPA)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppTheme.cyan)
                            .lineLimit(1)
                    }
                    AppPill(text: card.languageCode.rawValue.uppercased(), tint: AppTheme.warmSecondary)
                    Spacer(minLength: 6)
                    AppPill(
                        text: model.mastery(for: card).displayName,
                        tint: masteryTint(model.mastery(for: card))
                    )
                }
                Text(card.translationZH)
                    .font(.callout.weight(.medium))
                Text(card.definitionEN)
                    .font(.caption)
                    .foregroundStyle(AppTheme.warmSecondary)
                    .lineLimit(1)
                if model.senses(for: card).count > 1 {
                    AppPill(
                        text: "\(model.senses(for: card).count) meanings",
                        tint: AppTheme.pink
                    )
                }
                if !card.exampleSentence.isEmpty {
                    Label {
                        Text(card.exampleSentence).lineLimit(1)
                    } icon: {
                        Image(systemName: "quote.opening")
                    }
                    .font(.caption.italic())
                    .foregroundStyle(AppTheme.warmSecondary)
                    .padding(.top, 2)
                }
                let tags = model.tags(for: card)
                if !tags.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(tags.prefix(2)) { tag in tagPill(tag) }
                        if tags.count > 2 {
                            AppPill(text: "+\(tags.count - 2)", tint: AppTheme.warmSecondary)
                        }
                    }
                    .padding(.top, 2)
                }
            }

            VStack(alignment: .trailing, spacing: 7) {
                Label("\(card.encounterCount)", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warmSecondary)
                    .help("Encounter count")
                Text(card.createdAt, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(AppTheme.warmSecondary.opacity(0.72))
            }
        }
    }

    private var selectedCard: VocabularyCard? {
        guard let selectedCardID else { return nil }
        return model.cards.first { $0.id == selectedCardID }
    }

    private func cardDetail(_ card: VocabularyCard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 15) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(card.term)
                                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppTheme.graphite)
                                    .textSelection(.enabled)
                                AppPill(text: card.languageCode.rawValue.uppercased(), tint: AppTheme.warmSecondary)
                            }
                            if card.pronunciationIPA.isEmpty {
                                HStack(spacing: 8) {
                                    Text("音标尚未生成")
                                        .font(.callout)
                                        .foregroundStyle(AppTheme.warmSecondary)
                                    Button("AI 补充音标", systemImage: "waveform") {
                                        Task { await generatePronunciation(for: card) }
                                    }
                                    .buttonStyle(AppQuietButtonStyle())
                                    .disabled(pronunciationActionCardID != nil)
                                    if pronunciationActionCardID == card.id {
                                        ProgressView().controlSize(.small)
                                    }
                                }
                            } else {
                                Text(card.pronunciationIPA)
                                    .font(.system(.body, design: .monospaced).weight(.medium))
                                    .foregroundStyle(AppTheme.cyan)
                                    .textSelection(.enabled)
                            }
                            Text("\(max(1, model.senses(for: card).count)) 个词义 · \(card.encounterCount) 次相遇")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(AppTheme.warmSecondary)
                        }
                        Spacer()
                        Menu {
                            Button("Edit", systemImage: "pencil") { editingCard = card }
                            Divider()
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                cardPendingDeletion = card
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.headline)
                                .frame(width: 30, height: 30)
                                .background(AppTheme.field, in: Circle())
                        }
                        .menuStyle(.borderlessButton)
                        .disabled(isDeleting)
                        .help("Word actions")
                    }

                    let tags = model.tags(for: card)
                    if !tags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(tags) { tag in tagPill(tag) }
                        }
                    }
                }
                .appHeroCard(
                    padding: 20,
                    tint: AppTheme.violet,
                    secondaryTint: AppTheme.cyan
                )

                let senses = model.senses(for: card)
                if senses.isEmpty {
                    ContentUnavailableView(
                        "词义正在准备",
                        systemImage: "rectangle.stack",
                        description: Text("重新打开 App 后会完成本地迁移。")
                    )
                    .appCard(padding: 18, shadow: false)
                } else {
                    ForEach(senses) { sense in
                        senseDetail(sense, for: card)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.canvas)
    }

    private func senseDetail(_ sense: VocabularySense, for card: VocabularyCard) -> some View {
        let senseEncounters = encounters.filter { $0.senseID == sense.id }
        let state = model.state(for: sense)
        return VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        AppPill(
                            text: "MEANING \(sense.sortOrder + 1)",
                            tint: sense.isPrimary ? AppTheme.cyan : AppTheme.pink
                        )
                        if sense.isPrimary {
                            Text("主词义")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppTheme.warmSecondary)
                        }
                    }
                    Text(sense.translationZH)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppTheme.graphite)
                        .textSelection(.enabled)
                }
                Spacer()
                Menu {
                    Button("编辑词义", systemImage: "pencil") {
                        editingSense = sense
                    }
                    if !sense.isPrimary {
                        Divider()
                        Button("删除词义", systemImage: "trash", role: .destructive) {
                            sensePendingDeletion = sense
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: 28, height: 28)
                        .background(AppTheme.field, in: Circle())
                }
                .menuStyle(.borderlessButton)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("英文释义")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.cyan)
                Text(sense.definitionEN.isEmpty ? "暂无英文释义" : sense.definitionEN)
                    .foregroundStyle(sense.definitionEN.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("例句")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.pink)
                Text(sense.exampleSentence.isEmpty ? "暂无英例句" : sense.exampleSentence)
                    .font(.body.italic())
                    .foregroundStyle(sense.exampleSentence.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
            }

            Divider().overlay(AppTheme.divider)

            if let insight = sense.memoryInsight {
                MemoryInsightContent(insight: insight)
                HStack(spacing: 9) {
                    Button {
                        Task { await markMemoryInsightHelpful(for: sense) }
                    } label: {
                        Label(
                            sense.memoryInsightFeedback == .helpful ? "已标记有帮助" : "有帮助",
                            systemImage: sense.memoryInsightFeedback == .helpful
                                ? "checkmark.circle.fill"
                                : "hand.thumbsup"
                        )
                    }
                    .buttonStyle(AppQuietButtonStyle())
                    .disabled(sense.memoryInsightFeedback == .helpful || senseMemoryActionID != nil)

                    Button("换一种记法", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await generateMemoryInsight(for: sense, card: card, useDifferentStrategy: true) }
                    }
                    .buttonStyle(AppQuietButtonStyle())
                    .disabled(senseMemoryActionID != nil)

                    if senseMemoryActionID == sense.id {
                        ProgressView().controlSize(.small)
                    }
                }
            } else {
                HStack {
                    Text("这个词义还没有记忆线索。")
                        .font(.callout)
                        .foregroundStyle(AppTheme.warmSecondary)
                    Spacer()
                    Button("生成线索", systemImage: "sparkles") {
                        Task { await generateMemoryInsight(for: sense, card: card, useDifferentStrategy: false) }
                    }
                    .buttonStyle(AppQuietButtonStyle())
                    .disabled(senseMemoryActionID != nil)
                }
            }

            Divider().overlay(AppTheme.divider)

            HStack(spacing: 8) {
                AppPill(
                    text: model.mastery(for: sense).displayName,
                    tint: masteryTint(model.mastery(for: sense))
                )
                if let state {
                    Text("已复习 \(state.reps) 次")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.warmSecondary)
                    Spacer()
                    if state.reps == 0 {
                        Text("待学习")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.yellow)
                    } else {
                        RelativeDateText(date: state.dueAt, role: .due)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(state.dueAt <= Date() ? AppTheme.orange : AppTheme.cyan)
                    }
                }
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    if senseEncounters.isEmpty {
                        Text("还没有可展示的相遇原句。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.warmSecondary)
                    } else {
                        ForEach(senseEncounters) { encounter in
                            encounterRow(encounter)
                            if encounter.id != senseEncounters.last?.id {
                                Divider().overlay(AppTheme.divider)
                            }
                        }
                    }
                }
                .padding(.top, 10)
            } label: {
                Label(
                    "在 \(senseEncounters.count) 个场景遇到",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
                .font(.callout.weight(.semibold))
                .foregroundStyle(AppTheme.violet)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(padding: 18, shadow: false)
    }

    private func encounterRow(_ encounter: VocabularyEncounter) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                RelativeDateText(date: encounter.encounteredAt)
                    .font(.caption.weight(.medium))
                if let sourceApplication = encounter.sourceApplication {
                    AppPill(text: sourceApplication, tint: AppTheme.warmSecondary)
                }
                Spacer()
            }
            if let context = encounter.context {
                Text(context)
                    .font(.callout.italic())
                    .foregroundStyle(AppTheme.graphite)
                    .textSelection(.enabled)
            } else {
                Text("首次加入词库")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warmSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func encounterTrailSection(for card: VocabularyCard) -> some View {
        detailSection(
            "相遇轨迹",
            symbol: "point.topleft.down.to.point.bottomright.curvepath",
            tint: AppTheme.violet
        ) {
            if encounters.isEmpty {
                Text("正在读取相遇记录…")
                    .font(.callout)
                    .foregroundStyle(AppTheme.warmSecondary)
            } else {
                ForEach(encounters) { encounter in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            RelativeDateText(date: encounter.encounteredAt)
                                .font(.callout.weight(.medium))
                            if let sourceApplication = encounter.sourceApplication {
                                AppPill(text: sourceApplication, tint: AppTheme.warmSecondary)
                            }
                            Spacer()
                            if encounter.context != nil {
                                Image(systemName: "quote.opening")
                                    .foregroundStyle(AppTheme.pink)
                            }
                        }
                        if let context = encounter.context {
                            Text(context)
                                .font(.callout.italic())
                                .foregroundStyle(AppTheme.graphite)
                                .textSelection(.enabled)
                        } else {
                            Text("首次加入词库")
                                .font(.caption)
                                .foregroundStyle(AppTheme.warmSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if encounter.id != encounters.last?.id {
                        Divider().overlay(AppTheme.divider)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func memoryInsightSection(for card: VocabularyCard) -> some View {
        detailSection(
            "记忆线索",
            symbol: "sparkles",
            tint: AppTheme.yellow
        ) {
            if let insight = card.memoryInsight {
                MemoryInsightContent(insight: insight)

                Divider().overlay(AppTheme.divider)

                HStack(spacing: 10) {
                    Button {
                        Task { await markMemoryInsightHelpful(for: card) }
                    } label: {
                        Label(
                            card.memoryInsightFeedback == .helpful ? "已标记有帮助" : "有帮助",
                            systemImage: card.memoryInsightFeedback == .helpful
                                ? "checkmark.circle.fill"
                                : "hand.thumbsup"
                        )
                    }
                    .buttonStyle(AppQuietButtonStyle())
                    .disabled(card.memoryInsightFeedback == .helpful || memoryActionCardID != nil)

                    Button {
                        Task { await generateMemoryInsight(for: card, useDifferentStrategy: true) }
                    } label: {
                        Label("换一种记法", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(AppQuietButtonStyle())
                    .disabled(memoryActionCardID != nil)

                    if memoryActionCardID == card.id {
                        ProgressView().controlSize(.small)
                    }
                }
            } else {
                Text("这个旧词条还没有记忆线索。AI 会选择构词、辨析、语境等最合适的一种方式，不会强行拆词根。")
                    .font(.callout)
                    .foregroundStyle(AppTheme.warmSecondary)
                Button {
                    Task { await generateMemoryInsight(for: card, useDifferentStrategy: false) }
                } label: {
                    Label("生成记忆线索", systemImage: "sparkles")
                }
                .buttonStyle(AppQuietButtonStyle())
                .disabled(memoryActionCardID != nil)
            }
        }
    }

    private func detailSection<Content: View>(
        _ title: String,
        symbol: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(tint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(padding: 17, shadow: false)
    }

    private func tagPill(_ tag: Tag) -> some View {
        AppPill(text: tag.name, tint: AppTheme.warmSecondary)
    }

    private func filterPill(_ text: String) -> some View {
        AppPill(text: text)
    }

    private func masteryTint(_ level: MasteryLevel) -> Color {
        switch level {
        case .new: AppTheme.violet
        case .learning: AppTheme.orange
        case .familiar: AppTheme.cyan
        case .mastered: AppTheme.accent
        }
    }

    private var languageOptions: [LanguageCode] {
        Set(model.cards.map(\.languageCode)).sorted { $0.rawValue < $1.rawValue }
    }

    private var activeFilterCount: Int {
        (selectedLanguage == "all" ? 0 : 1)
            + (selectedTagID == nil ? 0 : 1)
            + (masteryFilter == .all ? 0 : 1)
            + (dueFilter == .all ? 0 : 1)
    }

    private var deletionAlertIsPresented: Binding<Bool> {
        Binding(
            get: { cardPendingDeletion != nil },
            set: { if !$0 { cardPendingDeletion = nil } }
        )
    }

    private var actionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )
    }

    private var senseDeletionAlertIsPresented: Binding<Bool> {
        Binding(
            get: { sensePendingDeletion != nil },
            set: { if !$0 { sensePendingDeletion = nil } }
        )
    }

    private func languageName(_ code: LanguageCode) -> String {
        if code == .english { return "English" }
        if code == .japanese { return "Japanese" }
        return code.rawValue.uppercased()
    }

    private func matchesDueFilter(_ card: VocabularyCard, at date: Date) -> Bool {
        guard dueFilter != .all else { return true }
        let states = model.senses(for: card).compactMap { model.state(for: $0) }
        guard !states.isEmpty else { return dueFilter == .new }
        return switch dueFilter {
        case .all: true
        case .due: states.contains { $0.reps > 0 && $0.dueAt <= date }
        case .new: states.contains { $0.reps == 0 || $0.fsrsState == .new }
        case .scheduled: states.allSatisfy { $0.reps > 0 && $0.dueAt > date }
        }
    }

    private func masteryRank(_ level: MasteryLevel) -> Int {
        switch level {
        case .new: 0
        case .learning: 1
        case .familiar: 2
        case .mastered: 3
        }
    }

    private func clearFilters() {
        selectedLanguage = "all"
        selectedTagID = nil
        masteryFilter = .all
        dueFilter = .all
    }

    private func reloadKeepingSelection() async {
        await model.load()
        if let selectedCardID, model.cards.contains(where: { $0.id == selectedCardID }) {
            return
        }
        selectedCardID = visibleCards.first?.id
    }

    private func loadEncountersForSelectedCard() async {
        guard let selectedCardID else {
            encounters = []
            return
        }
        do {
            encounters = try await vocabularyRepository.fetchEncounters(cardID: selectedCardID)
        } catch {
            encounters = []
        }
    }

    private func delete(_ card: VocabularyCard) async {
        isDeleting = true
        cardPendingDeletion = nil
        do {
            try await vocabularyRepository.delete(id: card.id)
            if selectedCardID == card.id { selectedCardID = nil }
            await reloadKeepingSelection()
            onDataChanged()
        } catch {
            actionErrorMessage = "无法删除“\(card.term)”：\(error.localizedDescription)"
        }
        isDeleting = false
    }

    private func delete(_ sense: VocabularySense) async {
        sensePendingDeletion = nil
        do {
            try await vocabularySenseRepository.delete(id: sense.id)
            await reloadKeepingSelection()
            await loadEncountersForSelectedCard()
            onDataChanged()
        } catch {
            actionErrorMessage = "无法删除词义：\(error.localizedDescription)"
        }
    }

    private func generateMemoryInsight(
        for sense: VocabularySense,
        card: VocabularyCard,
        useDifferentStrategy: Bool
    ) async {
        guard senseMemoryActionID == nil else { return }
        senseMemoryActionID = sense.id
        defer { senseMemoryActionID = nil }
        do {
            let insight = try await aiProvider.generateMemoryInsight(
                request: MemoryInsightGenerationRequest(
                    term: card.term,
                    languageCode: card.languageCode,
                    translationZH: sense.translationZH,
                    definitionEN: sense.definitionEN,
                    exampleSentence: sense.exampleSentence,
                    excludedStrategy: useDifferentStrategy ? sense.memoryInsight?.strategy : nil
                )
            )
            _ = try await vocabularySenseRepository.update(
                id: sense.id,
                changes: VocabularySenseChanges(
                    translationZH: sense.translationZH,
                    definitionEN: sense.definitionEN,
                    exampleSentence: sense.exampleSentence,
                    memoryInsight: insight
                ),
                at: Date()
            )
            await reloadKeepingSelection()
            onDataChanged()
        } catch {
            actionErrorMessage = "无法生成记忆线索：\(error.localizedDescription)"
        }
    }

    private func markMemoryInsightHelpful(for sense: VocabularySense) async {
        guard senseMemoryActionID == nil else { return }
        senseMemoryActionID = sense.id
        defer { senseMemoryActionID = nil }
        do {
            _ = try await vocabularySenseRepository.setMemoryInsightFeedback(
                id: sense.id,
                feedback: .helpful,
                at: Date()
            )
            await reloadKeepingSelection()
            onDataChanged()
        } catch {
            actionErrorMessage = "无法保存反馈：\(error.localizedDescription)"
        }
    }

    private func generateMemoryInsight(
        for card: VocabularyCard,
        useDifferentStrategy: Bool
    ) async {
        guard memoryActionCardID == nil else { return }
        memoryActionCardID = card.id
        defer { memoryActionCardID = nil }
        do {
            let insight = try await aiProvider.generateMemoryInsight(
                request: MemoryInsightGenerationRequest(
                    term: card.term,
                    languageCode: card.languageCode,
                    translationZH: card.translationZH,
                    definitionEN: card.definitionEN,
                    exampleSentence: card.exampleSentence,
                    excludedStrategy: useDifferentStrategy ? card.memoryInsight?.strategy : nil
                )
            )
            _ = try await vocabularyRepository.setMemoryInsight(
                id: card.id,
                insight: insight,
                at: Date()
            )
            await reloadKeepingSelection()
            onDataChanged()
        } catch {
            actionErrorMessage = "无法生成记忆线索：\(error.localizedDescription)"
        }
    }

    private func markMemoryInsightHelpful(for card: VocabularyCard) async {
        guard memoryActionCardID == nil else { return }
        memoryActionCardID = card.id
        defer { memoryActionCardID = nil }
        do {
            _ = try await vocabularyRepository.setMemoryInsightFeedback(
                id: card.id,
                feedback: .helpful,
                at: Date()
            )
            await reloadKeepingSelection()
            onDataChanged()
        } catch {
            actionErrorMessage = "无法保存反馈：\(error.localizedDescription)"
        }
    }

    private func generatePronunciation(for card: VocabularyCard) async {
        guard pronunciationActionCardID == nil else { return }
        pronunciationActionCardID = card.id
        defer { pronunciationActionCardID = nil }
        do {
            let pronunciation = try await aiProvider.generatePronunciationIPA(
                request: PronunciationGenerationRequest(
                    term: card.term,
                    languageCode: card.languageCode
                )
            )
            _ = try await vocabularyRepository.setPronunciationIPA(
                id: card.id,
                pronunciationIPA: pronunciation,
                at: Date()
            )
            await reloadKeepingSelection()
            onDataChanged()
        } catch {
            actionErrorMessage = "无法生成音标：\(error.localizedDescription)"
        }
    }
}

private struct EditSenseView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var translationZH: String
    @State private var definitionEN: String
    @State private var exampleSentence: String
    @State private var memoryInsight: MemoryInsight?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let sense: VocabularySense
    private let vocabularySenseRepository: any VocabularySenseRepository

    init(
        sense: VocabularySense,
        vocabularySenseRepository: any VocabularySenseRepository
    ) {
        self.sense = sense
        self.vocabularySenseRepository = vocabularySenseRepository
        _translationZH = State(initialValue: sense.translationZH)
        _definitionEN = State(initialValue: sense.definitionEN)
        _exampleSentence = State(initialValue: sense.exampleSentence)
        _memoryInsight = State(initialValue: sense.memoryInsight)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AppIconBadge(symbol: "text.book.closed.fill", tint: AppTheme.pink, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("编辑词义")
                        .font(.title2.weight(.semibold))
                    Text("词义 \(sense.sortOrder + 1) · 复习历史不会重置")
                        .font(.caption)
                        .foregroundStyle(AppTheme.warmSecondary)
                }
                Spacer()
                Button("关闭", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(AppQuietButtonStyle())
            }
            .padding(20)
            .background(AppTheme.surface.opacity(0.72))

            Divider().overlay(AppTheme.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    editField("中文释义") {
                        TextField("简洁自然的中文释义", text: $translationZH)
                            .textFieldStyle(.plain)
                            .appFieldSurface()
                    }
                    editField("English Definition") {
                        TextField("Simple English definition", text: $definitionEN, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(3...6)
                            .fixedSize(horizontal: false, vertical: true)
                            .appFieldSurface(minHeight: 76)
                    }
                    editField("Example") {
                        TextField("Natural example sentence", text: $exampleSentence, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(3...7)
                            .fixedSize(horizontal: false, vertical: true)
                            .appFieldSurface(minHeight: 88)
                    }
                    if memoryInsight != nil {
                        editField("记忆线索") {
                            MemoryInsightEditor(insight: $memoryInsight)
                        }
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .padding(24)
                .appCard(padding: 20, shadow: false)
                .padding(24)
            }

            Divider().overlay(AppTheme.divider)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                if isSaving { ProgressView().controlSize(.small) }
                Button("Save Meaning") { Task { await save() } }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSaving)
            }
            .padding(16)
            .background(AppTheme.surface.opacity(0.82))
        }
        .frame(width: 590, height: 650)
        .background(AppTheme.canvas)
        .tint(AppTheme.accent)
    }

    private var isValid: Bool {
        !translationZH.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !definitionEN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (memoryInsight.map { (try? $0.validated()) != nil } ?? true)
    }

    private func editField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() async {
        guard isValid, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await vocabularySenseRepository.update(
                id: sense.id,
                changes: VocabularySenseChanges(
                    translationZH: translationZH,
                    definitionEN: definitionEN,
                    exampleSentence: exampleSentence,
                    memoryInsight: memoryInsight
                ),
                at: Date()
            )
            dismiss()
        } catch {
            errorMessage = "无法保存词义：\(error.localizedDescription)"
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let arrangement = arrange(
            proposal: ProposedViewSize(width: bounds.width, height: proposal.height),
            subviews: subviews
        )
        for (index, point) in arrangement.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return (CGSize(width: min(maxWidth, max(0, x - spacing)), height: y + lineHeight), points)
    }
}
