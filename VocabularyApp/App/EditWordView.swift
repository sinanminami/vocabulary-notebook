import SwiftUI
import VocabularyCore

struct EditWordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: EditWordViewModel

    init(
        card: VocabularyCard,
        availableTags: [Tag],
        selectedTagIDs: Set<UUID>,
        vocabularyRepository: any VocabularyRepository,
        aiProvider: any AIProvider
    ) {
        _model = State(
            initialValue: EditWordViewModel(
                card: card,
                availableTags: availableTags,
                selectedTagIDs: selectedTagIDs,
                vocabularyRepository: vocabularyRepository,
                aiProvider: aiProvider
            )
        )
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            HStack(spacing: 13) {
                AppIconBadge(
                    symbol: "pencil.and.outline",
                    tint: AppTheme.orange,
                    size: 38
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text("Edit Word")
                        .font(.title2.weight(.semibold))
                    Text("Refine the card without resetting its review history.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(AppQuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            .background(AppTheme.surface.opacity(0.72))

            Divider().overlay(AppTheme.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Term") {
                        TextField("Term", text: $model.term)
                            .textFieldStyle(.plain)
                            .appFieldSurface()
                            .font(.title3.weight(.semibold))
                    }

                    field("Language") {
                        Picker("Language", selection: $model.languageCode) {
                            Text("English").tag(LanguageCode.english)
                            Text("Japanese").tag(LanguageCode.japanese)
                            if model.languageCode != .english && model.languageCode != .japanese {
                                Text(model.languageCode.rawValue.uppercased()).tag(model.languageCode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }

                    field("发音音标 · IPA") {
                        TextField("例如 /kənˈsɪdərəbəl/", text: $model.pronunciationIPA)
                            .textFieldStyle(.plain)
                            .appFieldSurface()
                            .font(.system(.body, design: .monospaced))
                    }

                    field("中文释义") {
                        TextField("简洁自然的中文释义", text: $model.translationZH)
                            .textFieldStyle(.plain)
                            .appFieldSurface()
                    }

                    field("English Definition") {
                        multilineField(
                            "Simple English definition",
                            text: $model.definitionEN,
                            minHeight: 72
                        )
                    }

                    field("Example") {
                        multilineField(
                            "Natural example sentence",
                            text: $model.exampleSentence,
                            minHeight: 90
                        )
                    }

                    if model.memoryInsight != nil {
                        field("记忆线索") {
                            MemoryInsightEditor(insight: $model.memoryInsight)
                        }
                    }

                    field("Tags") {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 145), spacing: 8)],
                            spacing: 8
                        ) {
                            ForEach(model.availableTags) { tag in
                                let isSelected = model.selectedTagIDs.contains(tag.id)
                                Button {
                                    model.toggleTag(tag)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        Text(tag.name).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(isSelected ? AppTheme.accentStrong : AppTheme.warmSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    isSelected ? AppTheme.accentSoft : AppTheme.field,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                            }
                        }
                    }

                    if let errorMessage = model.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
                .padding(24)
                .appCard(padding: 0, shadow: false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(model.isSaving || model.isGenerating)
            }

            Divider().overlay(AppTheme.divider)

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(AppQuietButtonStyle())
                Button("Regenerate with AI", systemImage: "sparkles") {
                    Task { await model.regenerate() }
                }
                .buttonStyle(AppQuietButtonStyle())
                .disabled(
                    model.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.isGenerating
                        || model.isSaving
                )
                if model.isGenerating {
                    ProgressView().controlSize(.small)
                    Text("Generating…").foregroundStyle(.secondary)
                }
                Spacer()
                if model.isSaving {
                    ProgressView().controlSize(.small)
                    Text("Saving…").foregroundStyle(.secondary)
                } else {
                    Button("Save Changes") {
                        Task { await model.save() }
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.isFormValid)
                }
            }
            .padding(16)
            .background(AppTheme.surface.opacity(0.82))
        }
        .background(AppTheme.canvas)
        .tint(AppTheme.accent)
        .frame(width: 620, height: 670)
        .onChange(of: model.didFinish) { _, didFinish in
            if didFinish { dismiss() }
        }
    }

    private func field<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.warmSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func multilineField(
        _ prompt: String,
        text: Binding<String>,
        minHeight: CGFloat
    ) -> some View {
        TextField(prompt, text: text, axis: .vertical)
            .lineLimit(3...7)
            .textFieldStyle(.plain)
            .fixedSize(horizontal: false, vertical: true)
            .appFieldSurface(minHeight: minHeight)
    }
}
