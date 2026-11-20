import AppKit
import SwiftUI

extension Notification.Name {
    static let vocabularyDataChanged = Notification.Name("VocabularyApp.vocabularyDataChanged")
}

@MainActor
final class QuickAddPanelController: NSObject, NSWindowDelegate {
    static let shared = QuickAddPanelController()

    private weak var environment: AppEnvironment?
    private var panel: NSPanel?
    private var presentationID = UUID()

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQuickAddRequest(_:)),
            name: .quickAddRequested,
            object: nil
        )
    }

    func configure(environment: AppEnvironment) {
        self.environment = environment
    }

    func showEmpty() {
        show(term: "", sourceApplication: nil, notice: nil, automaticallyGenerate: false)
    }

    @objc private func handleQuickAddRequest(_ notification: Notification) {
        let term = notification.userInfo?[QuickAddNotificationKey.term] as? String ?? ""
        let usedFallback = notification.userInfo?[
            QuickAddNotificationKey.usedClipboardFallback
        ] as? Bool ?? false
        let captureMessage = notification.userInfo?[
            QuickAddNotificationKey.captureMessage
        ] as? String
        let sourceApplication = notification.userInfo?[
            QuickAddNotificationKey.sourceApplication
        ] as? String
        let notice = captureMessage ?? (term.isEmpty
            ? "没有读取到选中文字。请先按 ⌘C 再试，或检查辅助功能权限。"
            : (usedFallback ? "已从剪贴板读取。" : nil))
        show(
            term: term,
            sourceApplication: sourceApplication,
            notice: notice,
            automaticallyGenerate: !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    private func show(
        term: String,
        sourceApplication: String?,
        notice: String?,
        automaticallyGenerate: Bool
    ) {
        guard let environment,
              let vocabularyRepository = environment.vocabularyRepository,
              let reviewStateRepository = environment.reviewStateRepository,
              let tagRepository = environment.tagRepository else {
            NSSound.beep()
            return
        }

        presentationID = UUID()
        let panel = panel ?? makePanel()
        let view = AddWordView(
            vocabularyRepository: vocabularyRepository,
            vocabularySenseRepository: environment.vocabularySenseRepository,
            reviewStateRepository: reviewStateRepository,
            tagRepository: tagRepository,
            aiProvider: environment.aiProvider,
            initialTerm: term,
            sourceApplication: sourceApplication,
            quickAddNotice: notice,
            automaticallyGenerate: automaticallyGenerate,
            presentation: .quickPanel,
            onFinished: { [weak self] savedTerm in
                self?.showSavedFeedback(term: savedTerm)
            },
            onCancel: { [weak self] in
                self?.close()
            }
        )
        panel.setContentSize(NSSize(width: 560, height: 540))
        panel.contentViewController = NSHostingController(
            rootView: view.preferredColorScheme(.light)
        )
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 540),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Quick Add"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        self.panel = panel
        return panel
    }

    private func showSavedFeedback(term: String) {
        let feedbackID = presentationID
        NotificationCenter.default.post(name: .vocabularyDataChanged, object: nil)
        let feedback = VStack(spacing: 12) {
            AppIconBadge(symbol: "checkmark", size: 44)
            VStack(spacing: 3) {
                Text("Saved to your library")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.warmSecondary)
                Text(term)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.graphite)
                    .lineLimit(1)
            }
        }
        .frame(width: 360, height: 150)
        .background(AppTheme.canvas)
        panel?.setContentSize(NSSize(width: 360, height: 150))
        panel?.contentViewController = NSHostingController(
            rootView: feedback.preferredColorScheme(.light)
        )
        panel?.center()

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(850))
            guard self?.presentationID == feedbackID else { return }
            self?.close()
        }
    }

    func close() {
        presentationID = UUID()
        panel?.orderOut(nil)
        panel?.contentViewController = nil
    }

    func windowWillClose(_ notification: Notification) {
        presentationID = UUID()
        panel?.contentViewController = nil
    }
}
