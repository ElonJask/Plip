import Foundation
import ServiceManagement

/// 开机自启（登录项）的可观察状态。
/// `on` 表示用户意图为开启：系统已启用，或已登记但还要在「登录项」里点允许。
public enum LoginItemState: Equatable {
    case off
    case on
    case needsApproval
    case failed(String)

    public var isOn: Bool {
        switch self {
        case .on, .needsApproval: return true
        default: return false
        }
    }

    public var message: String? {
        switch self {
        case .needsApproval:
            return "已登记，但系统要求在「登录项」里允许 Plip，否则开机不会启动。"
        case .failed(let text):
            return text
        case .off, .on:
            return nil
        }
    }
}

public enum LoginItemInterpreter {
    /// 把 ServiceManagement 的状态映射成界面状态。
    /// `requiresApproval` 不是失败：登记成功，只是用户还没在系统设置里允许。
    public static func state(for status: SMAppService.Status) -> LoginItemState {
        switch status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        case .notRegistered, .notFound: return .off
        @unknown default: return .off
        }
    }

    /// 登记/取消登记失败时的说明。签名和用户拒绝要单独说清楚，不能只显示“失败”。
    public static func failureMessage(for error: Error, enabling: Bool) -> String {
        let ns = error as NSError
        if isServiceManagement(ns) {
            switch ns.code {
            case 1, 3: // 未授权 / kSMErrorInvalidSignature
                return "系统拒绝登记开机自启。临时签名，或应用不在「应用程序」文件夹时，macOS 不会在登录时启动它。请用 Developer ID 签名后安装到「应用程序」。"
            case 10: // kSMErrorLaunchDeniedByUser
                return "你之前在系统设置里关闭了 Plip 的登录项。请到「登录项」里重新允许。"
            case 11 where enabling: // kSMErrorAlreadyRegistered
                return "登录项已经登记过了。若开机仍不启动，请到系统设置的「登录项」里确认它是允许状态。"
            default:
                break
            }
        }
        let action = enabling ? "开启" : "关闭"
        return "\(action)开机自启失败：\(ns.localizedDescription)"
    }

    private static func isServiceManagement(_ error: NSError) -> Bool {
        error.domain.contains("ServiceManagement") || error.domain.contains("SMApp")
    }
}

/// 菜单栏应用的登录项。状态变化会推到界面；失败不会被吞掉。
public final class LoginItemController: ObservableObject {
    public static let shared = LoginItemController()

    @Published public private(set) var state: LoginItemState

    private let status: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    private let openSettings: () -> Void

    public init(status: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
         unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() },
         openSettings: @escaping () -> Void = { SMAppService.openSystemSettingsLoginItems() }) {
        self.status = status
        self.register = register
        self.unregister = unregister
        self.openSettings = openSettings
        self.state = LoginItemInterpreter.state(for: status())
    }

    public func refresh() {
        let next = LoginItemInterpreter.state(for: status())
        if case .failed = state, case .off = next { return }
        state = next
    }

    /// 勾选：登记登录项。若系统要求批准，打开「登录项」设置。
    /// 取消：解除登记。
    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try register()
            } else {
                try unregister()
            }
            state = LoginItemInterpreter.state(for: status())
            if case .needsApproval = state {
                openSettings()
            }
        } catch {
            let ns = error as NSError
            // 已经登记过：以系统当前状态为准，不要当成失败。
            if enabled, isAlreadyRegistered(ns) {
                state = LoginItemInterpreter.state(for: status())
                if case .needsApproval = state { openSettings() }
                if case .off = state {
                    state = .failed(LoginItemInterpreter.failureMessage(for: error, enabling: true))
                }
                return
            }
            state = .failed(LoginItemInterpreter.failureMessage(for: error, enabling: enabled))
            if isDeniedByUser(ns) { openSettings() }
        }
    }

    private func isAlreadyRegistered(_ error: NSError) -> Bool {
        error.code == 11 && (error.domain.contains("ServiceManagement") || error.domain.contains("SMApp"))
    }

    private func isDeniedByUser(_ error: NSError) -> Bool {
        error.code == 10 && (error.domain.contains("ServiceManagement") || error.domain.contains("SMApp"))
    }
}
