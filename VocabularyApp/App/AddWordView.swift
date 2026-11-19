import SwiftUI
import VocabularyCore

enum AddWordPresentation {
    case sheet
    case quickPanel
}

struct AddWordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: AddWordViewModel
    private let quickAddNotice: String?
    private let automaticallyGenerate: Bool
    private let presentation: AddWordPresentation
    private let onFinished: ((String) -> Void)?
    private let onCancel: (() -> Void)?

    init(
        vocabularyRepository: any VocabularyRepository,
        vocabularySenseRepository: (any VocabularySenseRepository)? = nil,
        reviewStateRepository: any ReviewStateRepository,
        tagRepository: any TagRepository,
        aiProvider: any AIProvider,
        initialTerm: String = "",
        sourceApplication: String? = nil,
        quickAddNotice: String? = nil,
        automaticallyGenerate: Bool = false,
        presentation: AddWordPresentation = .sheet,
        onFinished: ((String) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.quickAddNotice = quickAddNotice
        self.automaticallyGenerate = automaticallyGenerate
        self.presentation = presentation
        self.onFinished = onFinished
        self.onCancel = onCancel
        _model = State(
            initialValue: AddWordViewModel(
                vocabularyRepository: vocabularyRepository,
                vocabularySenseRepository: vocabularySenseRepository,
                reviewStateRepository: reviewStateRepository,
                tagRepository: tagRepository,
                aiProvider: aiProvider,
                initialTerm: initialTerm,
                sourceApplication: sourceApplication
            )
        )
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            header
            Divider().overlay(AppTheme.divider)

            if let quickAddNotice {
                Label(quickAddNotice, systemImage: "info.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.orange.opacity(0.1))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch model.phase {
                    case .entry:
                        entryForm
                    case .generating:
                        loadingState
                    case .editing, .saving:
                        cardEditor
                    case .duplicate:
                        duplicateState
                    }

                    if let errorMessage = model.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
                .padding(24)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().overlay(AppTheme.divider)
            footer
        }
        .background(AppTheme.canvas)
        .tint(AppTheme.accent)
        .frame(
            width: presentation == .quickPanel ? 560 : 620,
            height: presentation == .quickPanel ? 540 : preferredHeight
        )
        .task { await model.prepare(automaticallyGenerate: automaticallyGenerate) }
        .onChange(of: model.context) { _, _ in
            model.duplicateContextDidChange()
        }
        .onChange(of: model.didFinish) { _, didFinish in
            guard didFinish else { return }
            if let onFinished {
                onFinished(model.term)
            } else {
                dismiss()
            }
        }
        .onExitCommand(perform: cancel)
    }

    private var header: some View {
        HStack(spacing: 13) {
            AppIconBadge(
                symbol: presentation == .quickPanel ? "bolt.fill" : "plus.rectangle.on.rectangle",
                tint: presentation == .quickPanel ? AppTheme.cyan : AppTheme.pink,
                size: 38
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(presentation == .quickPanel ? "Quick Add" : "Add Word")
                    .font(.title2.weight(.semibold))
                Text("AI 生成后可修改全部字段，再保存到本地。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("关闭", systemImage: "xmark") { cancel() }
                .labelStyle(.iconOnly)
                .buttonStyle(AppQuietButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .background(AppTheme.surface.opacity(0.72))
    }

    private var entryForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            formSection("Word or phrase") {
                TextField("例如 meticulously 或 ablation study", text: $model.term)
                    .textFieldStyle(.plain)
                    .appFieldSurface()
                    .font(.title3)
            }

            formSection("Context（可选）") {
                TextField(
                    "粘贴含有这个词的原句或段落",
                    text: $model.context,
                    axis: .vertical
                )
                .lineLimit(4...8)
                .multilineFieldSurface(minHeight: 100)
            }


            if let sourceApplication = model.sourceApplication {
                Label("From \(sourceApplication) · 来源只保存在本机", systemImage: "lock.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.cyan)
            }

            Text("你填写的原句会发送给 AI 以匹配词义，并作为相遇记录保存在本机；来源应用名不会发送给 AI。")
                .font(.caption)
                .foregroundStyle(AppTheme.warmSecondary)
        }
        .appCard(padding: 20, shadow: false)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("正在生成 \(model.term)…")
                .font(.headline)
            Text("仅发送当前词条和你填写的上下文。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .appCard(padding: 20, shadow: false)
    }

    private var cardEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            formSection("Term") {
                TextField("Term", text: $model.term)
                    .textFieldStyle(.plain)
                    .appFieldSurface()
                    .font(.title3.weight(.semibold))
            }

            formSection("Language") {
                Picker("Language", selection: $model.languageCode) {
                    Text("English").tag(LanguageCode.english)
                    Text("Japanese").tag(LanguageCode.japanese)
                    if model.languageCode != .english && model.languageCode != .japanese {
                        Text(model.languageCode.rawValue).tag(model.languageCode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            formSection("发音音标 · IPA") {
                TextField("例如 /kənˈsɪdərəbəl/", text: $model.pronunciationIPA)
                    .textFieldStyle(.plain)
                    .appFieldSurface()
                    .font(.system(.body, design: .monospaced))
            }

            formSection("中文释义") {
                TextField("简洁自然的中文释义", text: $model.translationZH)
                    .textFieldStyle(.plain)
                    .appFieldSurface()
            }

            formSection("English Definition") {
                TextField(
                    "Simple English definition",
                    text: $model.definitionEN,
                    axis: .vertical
                )
                .lineLimit(3...6)
                .multilineFieldSurface(minHeight: 72)
            }

            formSection("Example") {
                TextField(
                    "Natural example sentence",
                    text: $model.exampleSentence,
                    axis: .vertical
                )
                .lineLimit(3...7)
                .multilineFieldSurface(minHeight: 90)
            }

            formSection("这次遇到的原句（可选）") {
                TextField(
                    "粘贴含有这个词的原句，作为本地相遇记录",
                    text: $model.context,
                    axis: .vertical
                )
                .lineLimit(3...6)
                .multilineFieldSurface(minHeight: 72)
            }

            if let sourceApplication = model.sourceApplication {
                Label("From \(sourceApplication) · 来源只保存在本机", systemImage: "lock.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.cyan)
            }

            if model.memoryInsight != nil {
                formSection("记忆线索") {
                    MemoryInsightEditor(insight: $model.memoryInsight)
                }
            }

            formSection("Tags") { tagGrid }
        }
        .appCard(padding: 20, shadow: false)
        .disabled(model.phase == .saving)
    }

    private var tagGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], spacing: 8) {
            ForEach(model.availableTags) { tag in
                let isSelected = model.selectedTagIDs.contains(tag.id)
                Button {
                    model.toggleTag(tag)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        Text(tag.name)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        isSelected ? AppTheme.accentSoft : AppTheme.field,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? AppTheme.accent.opacity(0.28) : AppTheme.border, lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? AppTheme.accentStrong : AppTheme.warmSecondary)
            }
        }
    }

    @ViewBuilder
    private var duplicateState: some View {
        if let card = model.duplicateCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("再次遇到", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                            .font(.headline)
                            .foregroundStyle(AppTheme.pink)
                        Text(card.term)
                            .font(.largeTitle.weight(.semibold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(card.encounterCount) encounters")
                            .font(.caption.weight(.semibold))
                        Text(model.duplicateMastery.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("这次的原句（可选）")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(model.isMatchingDuplicateSense ? "匹配中…" : "用 AI 重新匹配") {
                            Task { await model.matchDuplicateSense() }
                        }
                        .buttonStyle(AppQuietButtonStyle())
                        .disabled(
                            model.isMatchingDuplicateSense
                                || model.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }

                    TextField(
                        "粘贴原句后可以更准确地匹配词义",
                        text: $model.context,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                    .multilineFieldSurface(minHeight: 58)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("这次是哪个词义？")
                            .font(.headline)
                        if model.isMatchingDuplicateSense {
                            ProgressView().controlSize(.small)
                            Text("AI 正在对照语境")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(model.duplicateSenses) { sense in
                        duplicateSenseOption(
                            choice: .existing(sense.id),
                            title: sense.translationZH,
                            subtitle: sense.definitionEN,
                            badge: sense.isPrimary ? "主词义" : nil
                        )
                    }

                    duplicateSenseOption(
                        choice: .newSense,
                        title: model.proposedNewSenseTranslation.isEmpty
                            ? "作为新词义"
                            : model.proposedNewSenseTranslation,
                        subtitle: model.proposedNewSenseDefinition,
                        badge: "新词义"
                    )

                    if let recommendation = model.duplicateSenseRecommendation {
                        Label("AI 建议 · \(recommendation.reasonZH)", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(AppTheme.cyan)
                    } else if let notice = model.duplicateSenseMatchNotice {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let sourceApplication = model.sourceApplication {
                    Label("From \(sourceApplication) · 只保存应用名", systemImage: "lock.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.cyan)
                }

                Text("只有点击保存后才会增加相遇次数；创建新词义也必须由你确认。相遇本身不改变复习排期。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .appCard(padding: 22, shadow: false)
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { cancel() }
            Spacer()

            switch model.phase {
            case .entry:
                Button("Generate with AI") {
                    Task { await model.generate() }
                }
                .buttonStyle(AppPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(model.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            case .generating:
                Text("Generating…")
                    .foregroundStyle(.secondary)
            case .editing:
                Button("Save") {
                    Task { await model.save() }
                }
                .buttonStyle(AppPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!model.isFormValid)
            case .saving:
                ProgressView()
                    .controlSize(.small)
                Text("Saving…")
                    .foregroundStyle(.secondary)
            case .duplicate:
                Button(model.duplicateActionTitle) {
                    Task { await model.addEncounter() }
                }
                .buttonStyle(AppPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSaveDuplicateEncounter)
            }
        }
        .padding(16)
        .background(AppTheme.surface.opacity(0.82))
    }

    private func duplicateSenseOption(
        choice: AddWordViewModel.DuplicateSenseChoice,
        title: String,
        subtitle: String,
        badge: String?
    ) -> some View {
        let isSelected = model.duplicateSenseChoice == choice
        return Button {
            model.duplicateSenseChoice = choice
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.warmSecondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(title)
                            .font(.body.weight(.semibold))
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.accentSoft, in: Capsule())
                        }
                    }
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? AppTheme.accentSoft.opacity(0.72) : AppTheme.field,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? AppTheme.accent.opacity(0.42) : AppTheme.border, lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isMatchingDuplicateSense)
    }

    private var preferredHeight: CGFloat {
        switch model.phase {
        case .entry, .generating, .duplicate: 540
        case .editing, .saving: 690
        }
    }

    private func cancel() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }

    private func fieldLabel(_ value: String) -> some View {
        Text(value)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private func formSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func multilineFieldSurface(minHeight: CGFloat) -> some View {
        textFieldStyle(.plain)
            .fixedSize(horizontal: false, vertical: true)
            .appFieldSurface(minHeight: minHeight)
    }
}
