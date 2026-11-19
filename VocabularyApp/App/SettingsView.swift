import AppKit
import SwiftUI
import VocabularyAI
import VocabularyCore

struct SettingsView: View {
    @State private var aiModel: AISettingsViewModel
    @State private var reviewModel: ReviewSettingsViewModel
    @State private var tagModel: TagSettingsViewModel
    @State private var dataModel: DataManagementViewModel
    @State private var launchAtLoginModel = LaunchAtLoginSettingsModel()
    @State private var tagPendingDeletion: Tag?
    @State private var hasAccessibilityPermission = GlobalHotKeyController.hasAccessibilityPermission
    @State private var quickAddShortcut = GlobalHotKeyController.shared.selectedShortcut
    @State private var shortcutErrorMessage: String?
    private let onReviewSettingsChanged: () -> Void

    init(
        apiKeyStore: any APIKeyStore,
        aiProvider: any AIProvider,
        vocabularyRepository: any VocabularyRepository,
        reviewStateRepository: any ReviewStateRepository,
        appSettingsRepository: any AppSettingsRepository,
        tagRepository: any TagRepository,
        reminderManager: ReviewReminderManager,
        onReviewSettingsChanged: @escaping () -> Void
    ) {
        _aiModel = State(initialValue: AISettingsViewModel(
            apiKeyStore: apiKeyStore,
            aiProvider: aiProvider
        ))
        _reviewModel = State(
            initialValue: ReviewSettingsViewModel(
                repository: appSettingsRepository,
                reminderManager: reminderManager
            )
        )
        _tagModel = State(initialValue: TagSettingsViewModel(repository: tagRepository))
        _dataModel = State(initialValue: DataManagementViewModel(
            vocabularyRepository: vocabularyRepository,
            reviewStateRepository: reviewStateRepository,
            tagRepository: tagRepository
        ))
        self.onReviewSettingsChanged = onReviewSettingsChanged
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AppPageHeader(
                    eyebrow: "Settings",
                    title: "把学习方式调成适合你的节奏",
                    subtitle: "在这里管理收词、自动启动、复习提醒、AI 内容和本地数据。",
                    tint: AppTheme.cyan
                )
                quickAddSection
                startupSection
                reviewSection
                aiSection
                tagSection
                dataSection
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 30)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .appPageBackground()
        .navigationTitle("Settings")
        .task {
            aiModel.load()
            await reviewModel.load()
            await tagModel.load()
            await dataModel.loadHealthReport()
            hasAccessibilityPermission = GlobalHotKeyController.hasAccessibilityPermission
            quickAddShortcut = GlobalHotKeyController.shared.selectedShortcut
            shortcutErrorMessage = GlobalHotKeyController.shared.registrationErrorMessage
            launchAtLoginModel.refresh()
        }
        .alert(
            "删除自定义标签？",
            isPresented: Binding(
                get: { tagPendingDeletion != nil },
                set: { if !$0 { tagPendingDeletion = nil } }
            ),
            presenting: tagPendingDeletion
        ) { tag in
            Button("Delete", role: .destructive) {
                tagPendingDeletion = nil
                Task {
                    if await tagModel.delete(tag) { onReviewSettingsChanged() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { tag in
            Text("“\(tag.name)”会从所有词卡中移除，但词卡和复习记录会保留。")
        }
    }

    private var startupSection: some View {
        @Bindable var launchAtLoginModel = launchAtLoginModel
        return settingsPanel(
            "启动与后台",
            subtitle: "登录 Mac 后自动启动，让快捷收词随时可用。",
            symbol: "power",
            tint: AppTheme.cyan
        ) {
            settingsRow(
                "登录时自动启动",
                subtitle: "由 macOS 管理，可随时在系统设置的登录项中关闭。"
            ) {
                Toggle(
                    "登录时自动启动",
                    isOn: Binding(
                        get: { launchAtLoginModel.isEnabled },
                        set: { enabled in
                            Task { await launchAtLoginModel.setEnabled(enabled) }
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(launchAtLoginModel.isWorking)
            }

            settingDivider

            settingsRow("系统状态") {
                HStack(spacing: 7) {
                    if launchAtLoginModel.isWorking {
                        ProgressView().controlSize(.small)
                    }
                    Label(
                        launchAtLoginModel.statusLabel,
                        systemImage: launchAtLoginModel.statusSymbol
                    )
                    .foregroundStyle(
                        launchAtLoginModel.status == .enabled
                            ? Color.green
                            : launchAtLoginModel.needsApproval ? Color.orange : AppTheme.warmSecondary
                    )
                }
            }

            HStack(spacing: 8) {
                if launchAtLoginModel.needsApproval {
                    Button("打开登录项设置") { launchAtLoginModel.openSystemSettings() }
                        .buttonStyle(AppPrimaryButtonStyle())
                }
                Button("重新检查") { launchAtLoginModel.refresh() }
                    .buttonStyle(AppQuietButtonStyle())
            }

            if let statusMessage = launchAtLoginModel.statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(launchAtLoginModel.needsApproval ? .orange : .green)
            }
            if let errorMessage = launchAtLoginModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            helpText("开启后，单词记录本会在你登录 macOS 时启动，菜单栏快捷收词和全局快捷键也会随之就绪。")
        }
    }

    private var quickAddSection: some View {
        settingsPanel(
            "快速收词",
            subtitle: "在阅读时直接收下选中的词，不必离开当前页面。",
            symbol: "bolt.horizontal.circle",
            tint: AppTheme.violet
        ) {
            settingsRow("全局快捷键", subtitle: "适用于浏览器、PDF 阅读器和大多数文本应用。") {
                Picker("Global Shortcut", selection: $quickAddShortcut) {
                    ForEach(QuickAddShortcut.allCases) { shortcut in
                        Text(shortcut.displayName).tag(shortcut)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                .onChange(of: quickAddShortcut) { _, shortcut in
                    GlobalHotKeyController.shared.updateShortcut(shortcut)
                    shortcutErrorMessage = GlobalHotKeyController.shared.registrationErrorMessage
                }
            }
            settingDivider
            settingsRow("辅助功能权限", subtitle: "只用于读取你主动选中的文字。") {
                Label(
                    hasAccessibilityPermission ? "已授权" : "未授权",
                    systemImage: hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(hasAccessibilityPermission ? .green : .orange)
            }
            HStack(spacing: 8) {
                if !hasAccessibilityPermission {
                    Button("请求辅助功能权限") { GlobalHotKeyController.requestAccessibilityPermission() }
                        .buttonStyle(AppPrimaryButtonStyle())
                }
                Button("打开系统设置") { GlobalHotKeyController.openAccessibilitySettings() }
                    .buttonStyle(AppQuietButtonStyle())
                Button("重新检查") {
                    hasAccessibilityPermission = GlobalHotKeyController.hasAccessibilityPermission
                }
                .buttonStyle(AppQuietButtonStyle())
            }
            if let shortcutErrorMessage {
                Label(shortcutErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            helpText("在 Chrome、Safari 或 PDF 中选中文字后按 \(quickAddShortcut.displayName)。若目标应用不提供选区，可先按 ⌘C。")
        }
    }

    private var reviewSection: some View {
        @Bindable var reviewModel = reviewModel
        return settingsPanel(
            "复习计划",
            subtitle: "控制每天首次学习的词义量，并让提醒只在需要时出现。",
            symbol: "rectangle.stack.badge.play",
            tint: AppTheme.accent
        ) {
            settingsRow("每日新词义", subtitle: "每天最多首次学习多少个新词义。") {
                Stepper(
                    value: $reviewModel.dailyNewCardLimit,
                    in: AppSettings.dailyNewCardLimitRange,
                    step: 5
                ) {
                    Text("\(reviewModel.dailyNewCardLimit)")
                        .font(.body.monospacedDigit().weight(.semibold))
                        .frame(minWidth: 30, alignment: .trailing)
                }
                .fixedSize()
            }
            settingDivider
            Toggle("每日提醒", isOn: $reviewModel.reviewRemindersEnabled)
            if reviewModel.reviewRemindersEnabled {
                DatePicker("提醒时间", selection: $reviewModel.reminderTime, displayedComponents: .hourAndMinute)
                Toggle("仅在有到期词义时提醒", isOn: $reviewModel.notifyOnlyWhenDue)
            }
            settingDivider
            settingsRow("通知权限") {
                Label(
                    reviewModel.authorizationState.displayName,
                    systemImage: reviewModel.authorizationState.allowsNotifications
                        ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(reviewModel.authorizationState.allowsNotifications ? .green : .orange)
            }
            if reviewModel.authorizationState == .denied {
                HStack {
                    Button("Open Notification Settings") { reviewModel.openNotificationSettings() }
                    Button("Refresh Permission") { Task { await reviewModel.refreshAuthorization() } }
                }
            }
            HStack(spacing: 9) {
                Button("Save Review Settings") {
                    Task {
                        if await reviewModel.save() { onReviewSettingsChanged() }
                    }
                }
                .buttonStyle(AppPrimaryButtonStyle())
                .disabled(!reviewModel.hasChanges || reviewModel.isSaving)
                if reviewModel.isSaving { ProgressView().controlSize(.small) }
            }
            if let statusMessage = reviewModel.statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
            if let errorMessage = reviewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            helpText("新词义额度按自然日计算；同一拼写的不同词义会分别学习。提醒会滚动安排未来 14 天。")
        }
    }

    private var aiSection: some View {
        @Bindable var aiModel = aiModel
        return settingsPanel(
            "AI 内容生成",
            subtitle: "用于生成释义、例句、音标、记忆线索和推荐标签。",
            symbol: "wand.and.stars.inverse",
            tint: AppTheme.pink
        ) {
            settingsRow("Provider") { Text("Google Gemini").foregroundStyle(AppTheme.warmSecondary) }
            settingDivider
            settingsRow("Model") { Text(GeminiInteractionsProvider.defaultModel).foregroundStyle(AppTheme.warmSecondary) }
            SecureField(
                aiModel.hasStoredKey ? "输入新 Key 以替换当前 Key" : "AIza…",
                text: $aiModel.apiKeyInput
            )
            .textFieldStyle(.plain)
            .appFieldSurface()
            HStack(spacing: 8) {
                Button(aiModel.hasStoredKey ? "Replace API Key" : "Save API Key") { aiModel.save() }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .disabled(aiModel.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if aiModel.hasStoredKey {
                    Button("Test Connection") { Task { await aiModel.testConnection() } }
                        .buttonStyle(AppQuietButtonStyle())
                        .disabled(aiModel.isTesting)
                    Button("Delete", role: .destructive) { aiModel.delete() }
                }
                if aiModel.isTesting { ProgressView().controlSize(.small) }
                Spacer()
                Link("Get Gemini API Key", destination: URL(string: "https://aistudio.google.com/app/apikey")!)
            }
            if let statusMessage = aiModel.statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
            if let errorMessage = aiModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            helpText("Key 仅保存在本机 Keychain。生成词卡时，只发送当前词条和可选上下文。")
        }
    }

    private var tagSection: some View {
        @Bindable var tagModel = tagModel
        return settingsPanel(
            "标签管理",
            subtitle: "用轻量标签整理你的阅读和学习主题。",
            symbol: "tag",
            tint: AppTheme.orange
        ) {
            settingsRow("New Custom Tag") {
                HStack(spacing: 8) {
                    TextField("Research Notes", text: $tagModel.newTagName)
                        .textFieldStyle(.plain)
                        .appFieldSurface()
                        .frame(width: 190)
                        .onSubmit { createTag() }
                    Button("Add") { createTag() }
                        .disabled(
                            tagModel.newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || tagModel.isWorking
                        )
                }
            }

            settingDivider
            settingsRow("Default Tags") {
                Text(tagModel.systemTags.map(\.name).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(AppTheme.warmSecondary)
                    .multilineTextAlignment(.trailing)
            }

            if tagModel.customTags.isEmpty {
                Text("还没有自定义标签。默认标签始终保留。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tagModel.customTags) { tag in
                    customTagRow(tag)
                }
            }

            if let statusMessage = tagModel.statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if let errorMessage = tagModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            helpText("自定义标签可重命名或删除；删除标签只会移除词卡上的标签关联，不会删除词卡。")
        }
    }

    @ViewBuilder
    private func customTagRow(_ tag: Tag) -> some View {
        @Bindable var tagModel = tagModel
        if tagModel.editingTagID == tag.id {
            HStack {
                TextField("Tag name", text: $tagModel.editingName)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    Task {
                        if await tagModel.saveRename() { onReviewSettingsChanged() }
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Cancel") { tagModel.cancelRename() }
            }
        } else {
            LabeledContent(tag.name) {
                HStack {
                    Button("Rename", systemImage: "pencil") { tagModel.beginRename(tag) }
                        .labelStyle(.iconOnly)
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        tagPendingDeletion = tag
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
    }

    private var dataSection: some View {
        settingsPanel(
            "数据与隐私",
            subtitle: "词库只保存在本机，也可以随时导出备份。",
            symbol: "lock.doc",
            tint: AppTheme.yellow
        ) {
            settingsRow("Data Health") { dataHealthStatus }

            HStack {
                Button("Export Vocabulary CSV", systemImage: "square.and.arrow.up") {
                    exportCSV()
                }
                .buttonStyle(AppQuietButtonStyle())
                .disabled(dataModel.isWorking)
                Button("Refresh Health", systemImage: "arrow.clockwise") {
                    Task { await dataModel.loadHealthReport() }
                }
                .buttonStyle(AppQuietButtonStyle())
                if dataModel.isWorking { ProgressView().controlSize(.small) }
            }

            if let statusMessage = dataModel.statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if let errorMessage = dataModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            helpText("CSV 包含词卡、标签、掌握度和复习时间，便于本地备份或迁移。除 AI 生成所需内容外，词库不会上传。")
        }
    }

    private var settingDivider: some View {
        Divider().overlay(AppTheme.divider)
    }

    private func settingsPanel<Content: View>(
        _ title: String,
        subtitle: String,
        symbol: String,
        tint: Color = AppTheme.accent,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            AppSectionHeading(title, subtitle: subtitle, symbol: symbol, tint: tint)
            settingDivider
            content()
        }
        .appCard(padding: 20, shadow: false)
    }

    private func settingsRow<Content: View>(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AppTheme.graphite)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.warmSecondary)
                }
            }
            Spacer(minLength: 20)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func helpText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(AppTheme.warmSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var dataHealthStatus: some View {
        if let report = dataModel.healthReport {
            Text(healthStatusText(report))
                .foregroundStyle(
                    report.incompleteCardCount == 0
                        && report.missingMemoryInsightCount == 0
                        && report.missingPronunciationCount == 0
                        ? Color.secondary
                        : Color.orange
                )
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func healthStatusText(_ report: VocabularyDataHealthReport) -> String {
        report.incompleteCardCount == 0
            && report.untaggedCardCount == 0
            && report.missingMemoryInsightCount == 0
            && report.missingPronunciationCount == 0
            ? "词卡信息完整"
            : "\(report.incompleteCardCount) 张信息不完整 · \(report.untaggedCardCount) 张未打标签 · \(report.missingMemoryInsightCount) 张缺少记忆线索 · \(report.missingPronunciationCount) 张缺少音标"
    }

    private func createTag() {
        Task {
            if await tagModel.create() { onReviewSettingsChanged() }
        }
    }

    private func exportCSV() {
        Task {
            guard let data = await dataModel.prepareCSV() else { return }
            let panel = NSSavePanel()
            panel.title = "Export Vocabulary CSV"
            panel.nameFieldStringValue = "vocabulary-\(Date().formatted(.iso8601.year().month().day())).csv"
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
                dataModel.markExported(fileName: url.lastPathComponent)
            } catch {
                dataModel.reportExportFailure(error)
            }
        }
    }
}
