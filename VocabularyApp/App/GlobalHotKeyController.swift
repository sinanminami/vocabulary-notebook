import AppKit
import ApplicationServices
import Carbon.HIToolbox

extension Notification.Name {
    static let quickAddRequested = Notification.Name("VocabularyApp.quickAddRequested")
}

enum QuickAddNotificationKey {
    static let term = "term"
    static let usedClipboardFallback = "usedClipboardFallback"
    static let captureMessage = "captureMessage"
    static let sourceApplication = "sourceApplication"
}

enum QuickAddShortcut: String, CaseIterable, Identifiable {
    case controlOptionW
    case controlShiftW
    case controlOptionA

    var id: Self { self }

    var displayName: String {
        switch self {
        case .controlOptionW: "⌃⌥W"
        case .controlShiftW: "⌃⇧W"
        case .controlOptionA: "⌃⌥A"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .controlOptionW, .controlShiftW: UInt32(kVK_ANSI_W)
        case .controlOptionA: UInt32(kVK_ANSI_A)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .controlOptionW, .controlOptionA: UInt32(controlKey | optionKey)
        case .controlShiftW: UInt32(controlKey | shiftKey)
        }
    }
}

@MainActor
final class GlobalHotKeyController {
    static let shared = GlobalHotKeyController()

    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private(set) var selectedShortcut: QuickAddShortcut
    private(set) var registrationErrorMessage: String?

    private init() {
        selectedShortcut = UserDefaults.standard.string(forKey: "quickAddShortcut")
            .flatMap(QuickAddShortcut.init(rawValue:)) ?? .controlOptionW
        installEventHandler()
        registerHotKey()
    }

    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    static func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func updateShortcut(_ shortcut: QuickAddShortcut) {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
        selectedShortcut = shortcut
        UserDefaults.standard.set(shortcut.rawValue, forKey: "quickAddShortcut")
        registerHotKey()
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            nil,
            &eventHandlerReference
        )
        if status != noErr {
            registrationErrorMessage = "无法监听全局快捷键（错误 \(status)）。"
        }
    }

    private func registerHotKey() {
        let hotKeyID = EventHotKeyID(signature: 0x5756424B, id: 1)
        let status = RegisterEventHotKey(
            selectedShortcut.keyCode,
            selectedShortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        registrationErrorMessage = status == noErr
            ? nil
            : "\(selectedShortcut.displayName) 已被其他应用占用，请换一个快捷键（错误 \(status)）。"
    }

    private static let eventHandler: EventHandlerUPP = { _, event, _ in
        guard let event else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == 0x5756424B, hotKeyID.id == 1 else {
            return OSStatus(eventNotHandledErr)
        }
        Task { @MainActor in captureSelectionAndOpenQuickAdd() }
        return noErr
    }

    private static func captureSelectionAndOpenQuickAdd() {
        // Remember the app that owned the selection before VocabularyApp is activated.
        // Chrome's PDF viewer exposes page text to Accessibility, but not its selected
        // range, so the fallback copy must be delivered back to Chrome explicitly.
        let sourceApplication = NSWorkspace.shared.frontmostApplication
        let sourceApplicationName = sourceApplication?.localizedName

        if let selectedText = selectedTextFromAccessibility() {
            presentQuickAdd(
                term: selectedText,
                sourceApplication: sourceApplicationName,
                usedClipboardFallback: false,
                captureMessage: nil
            )
            return
        }

        guard hasAccessibilityPermission else {
            let clipboard = clipboardText() ?? ""
            presentQuickAdd(
                term: clipboard,
                sourceApplication: sourceApplicationName,
                usedClipboardFallback: true,
                captureMessage: clipboard.isEmpty
                    ? "辅助功能权限尚未生效，无法替 Chrome 执行复制。请重新授权，或先按 ⌘C。"
                    : "辅助功能权限尚未生效，已使用当前剪贴板内容。"
            )
            return
        }

        let pasteboardChangeCount = NSPasteboard.general.changeCount
        Task { @MainActor in
            // Wait for the physical shortcut keys to be released, otherwise
            // Chrome may interpret the synthetic copy with extra modifiers.
            try? await Task.sleep(for: .milliseconds(150))
            guard let sourceApplication,
                  synthesizeCopy(to: sourceApplication.processIdentifier) else {
                presentQuickAdd(
                    term: "",
                    sourceApplication: sourceApplicationName,
                    usedClipboardFallback: true,
                    captureMessage: "无法向原应用发送复制指令。请先按 ⌘C，再使用全局快捷键。"
                )
                return
            }

            // Chrome's PDF viewer can populate the pasteboard asynchronously.
            // Poll instead of relying on one short fixed delay.
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(100))
                if NSPasteboard.general.changeCount != pasteboardChangeCount,
                   let copiedText = clipboardText() {
                    presentQuickAdd(
                        term: copiedText,
                        sourceApplication: sourceApplicationName,
                        usedClipboardFallback: true,
                        captureMessage: "Chrome 没有直接提供选区，已自动复制并读取。"
                    )
                    return
                }
            }

            presentQuickAdd(
                term: "",
                sourceApplication: sourceApplicationName,
                usedClipboardFallback: true,
                captureMessage: "Chrome 复制超时。请先按 ⌘C，确认可以复制该单词，再使用全局快捷键。"
            )
        }
    }

    private static func selectedTextFromAccessibility() -> String? {
        guard hasAccessibilityPermission else { return nil }
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
              let focusedValue else {
            return nil
        }

        let focusedElement = unsafeDowncast(focusedValue, to: AXUIElement.self)
        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        ) == .success,
              let selectedText = selectedValue as? String else {
            return nil
        }
        return cleaned(selectedText)
    }

    @discardableResult
    private static func synthesizeCopy(to processIdentifier: pid_t) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
        return true
    }

    private static func clipboardText() -> String? {
        NSPasteboard.general.string(forType: .string).flatMap(cleaned)
    }

    private static func cleaned(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func presentQuickAdd(
        term: String,
        sourceApplication: String?,
        usedClipboardFallback: Bool,
        captureMessage: String?
    ) {
        var userInfo: [String: Any] = [
            QuickAddNotificationKey.term: term,
            QuickAddNotificationKey.usedClipboardFallback: usedClipboardFallback
        ]
        if let captureMessage {
            userInfo[QuickAddNotificationKey.captureMessage] = captureMessage
        }
        if let sourceApplication {
            userInfo[QuickAddNotificationKey.sourceApplication] = sourceApplication
        }
        NotificationCenter.default.post(
            name: .quickAddRequested,
            object: nil,
            userInfo: userInfo
        )
        NSApp.activate(ignoringOtherApps: true)
    }
}
