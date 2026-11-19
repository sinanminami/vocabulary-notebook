import AppKit
import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginSettingsModel {
    private(set) var isEnabled = false
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var isWorking = false
    private(set) var statusMessage: String?
    private(set) var errorMessage: String?

    init() {
        refresh()
    }

    var statusLabel: String {
        switch status {
        case .enabled:
            "已启用"
        case .requiresApproval:
            "等待系统批准"
        case .notRegistered:
            "未启用"
        case .notFound:
            "暂不可用"
        @unknown default:
            "状态未知"
        }
    }

    var statusSymbol: String {
        switch status {
        case .enabled:
            "checkmark.circle.fill"
        case .requiresApproval:
            "exclamationmark.triangle.fill"
        case .notRegistered:
            "circle"
        case .notFound:
            "xmark.circle.fill"
        @unknown default:
            "questionmark.circle.fill"
        }
    }

    var needsApproval: Bool {
        status == .requiresApproval
    }

    func refresh() {
        status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isWorking, enabled != isEnabled else { return }
        let previousValue = isEnabled
        isEnabled = enabled
        isWorking = true
        statusMessage = nil
        errorMessage = nil

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try await SMAppService.mainApp.unregister()
            }
            refresh()
            if status == .requiresApproval {
                statusMessage = "已添加为登录项，请在系统设置中允许后生效。"
            } else {
                statusMessage = enabled ? "已开启登录时自动启动。" : "已关闭登录时自动启动。"
            }
        } catch {
            isEnabled = previousValue
            refresh()
            errorMessage = enabled
                ? "无法开启自动启动：\(error.localizedDescription)"
                : "无法关闭自动启动：\(error.localizedDescription)"
        }

        isWorking = false
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
