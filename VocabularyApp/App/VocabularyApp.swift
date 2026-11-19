import AppKit
import SwiftUI

extension Notification.Name {
    static let settingsRequested = Notification.Name("VocabularyApp.settingsRequested")
}

@MainActor
final class AppNavigationRequest {
    static let shared = AppNavigationRequest()
    private var hasPendingSettingsRequest = false

    private init() {}

    func requestSettings() {
        hasPendingSettingsRequest = true
        NotificationCenter.default.post(name: .settingsRequested, object: nil)
    }

    func consumeSettingsRequest() -> Bool {
        guard hasPendingSettingsRequest else { return false }
        hasPendingSettingsRequest = false
        return true
    }
}

@main
struct VocabularyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment.live()
    private let globalHotKeyController = GlobalHotKeyController.shared

    var body: some Scene {
        WindowGroup("单词记录本", id: "main") {
            RootView()
                .environment(environment)
                .preferredColorScheme(.dark)
                .frame(minWidth: 840, minHeight: 560)
        }
        .defaultSize(width: 1_040, height: 700)
        .commands {
            SidebarCommands()
            CommandMenu("Vocabulary") {
                Button("Quick Add…") {
                    QuickAddPanelController.shared.showEmpty()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Review Today") {
                    ReviewReminderNavigation.shared.requestReviewOpen()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("单词记录本", systemImage: "character.book.closed") {
            VocabularyMenuBarView()
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct VocabularyMenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Quick Add…", systemImage: "plus") {
            QuickAddPanelController.shared.showEmpty()
        }

        Button("Review Today", systemImage: "rectangle.stack.badge.play") {
            ReviewReminderNavigation.shared.requestReviewOpen()
            showMainWindow()
        }

        Divider()

        Button("Open Main Window", systemImage: "macwindow") {
            showMainWindow()
        }

        Button("Settings…", systemImage: "gearshape") {
            AppNavigationRequest.shared.requestSettings()
            showMainWindow()
        }

        Divider()

        Button("Quit 单词记录本") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeKey }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}
