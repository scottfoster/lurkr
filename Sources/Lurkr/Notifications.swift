import Cocoa
import UserNotifications
import OSLog

@MainActor
struct NotificationClient {
    // Framework settings can't be constructed in tests; keep the fields used by delivery.
    struct Settings {
        var authorizationStatus: UNAuthorizationStatus
        var alertSetting: UNNotificationSetting
        var alertStyle: UNAlertStyle
    }

    var settings: () async -> Settings
    var authorize: () async throws -> Bool
    var add: (UNNotificationRequest) async throws -> Void

    static var system: NotificationClient {
        let center = UNUserNotificationCenter.current()
        return NotificationClient(
            settings: {
                let settings = await center.notificationSettings()
                return Settings(authorizationStatus: settings.authorizationStatus,
                                alertSetting: settings.alertSetting,
                                alertStyle: settings.alertStyle)
            },
            authorize: { try await center.requestAuthorization(options: [.alert, .sound]) },
            add: { try await center.add($0) }
        )
    }
}

@MainActor
enum Notifications {
    static let logger = Logger(subsystem: "com.singlepeel.lurkr", category: "Notifications")
    static func requestAuthorization(using client: NotificationClient? = nil) async throws {
        let client = client ?? .system
        let settings = await client.settings()
        guard settings.authorizationStatus == .notDetermined else { return }
        do {
            _ = try await client.authorize()
        } catch {
            throw DeliveryError.authorizationFailed(error.localizedDescription)
        }
    }

    static func sendTest(using client: NotificationClient? = nil) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Lurkr test notification"
        content.body = "Test from Lurkr. Focus or Do Not Disturb can silence go-live alerts."
        content.sound = .default
        try await send(UNNotificationRequest(
            identifier: "test.\(UUID().uuidString)",
            content: content,
            trigger: nil
        ), using: client ?? .system, requestPermission: true, requireBanner: true)
    }

    enum DeliveryError: LocalizedError, Equatable {
        case permissionNeeded
        case notAuthorized
        case alertsDisabled
        case authorizationFailed(String)
        case submissionFailed(String)

        var title: String {
            switch self {
            case .permissionNeeded: return "Allow Lurkr to show notifications"
            case .notAuthorized: return "Notifications are blocked by macOS"
            case .alertsDisabled: return "Notification banners are turned off"
            case .authorizationFailed: return "Couldn't request notification permission"
            case .submissionFailed: return "A notification couldn't be sent"
            }
        }

        var instructions: String {
            switch self {
            case .permissionNeeded:
                return "Choose Allow Notifications, then allow Lurkr in the macOS prompt. Return here and send a test."
            case .notAuthorized:
                return "1. Open System Settings → Notifications → Lurkr.\n2. Turn on Allow Notifications and choose Banners or Alerts.\n3. Return here and send a test."
            case .alertsDisabled:
                return "1. Open System Settings → Notifications → Lurkr.\n2. Turn on Allow Notifications and choose Banners or Alerts instead of None.\n3. Return here and send a test."
            case .authorizationFailed(let message):
                return "macOS couldn't request permission: \(message)\n\n\(Self.permissionNeeded.instructions) If the request keeps failing, quit and reopen Lurkr."
            case .submissionFailed(let message):
                return "macOS couldn't accept the notification: \(message)\n\nTry Send test again. If it keeps failing, quit and reopen Lurkr."
            }
        }

        var errorDescription: String? { instructions }

        var needsAuthorization: Bool {
            switch self {
            case .permissionNeeded, .authorizationFailed: return true
            default: return false
            }
        }
    }

    static func bannerIssue(in settings: NotificationClient.Settings) -> DeliveryError? {
        if settings.authorizationStatus == .notDetermined { return .permissionNeeded }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return .notAuthorized
        }
        if settings.authorizationStatus == .provisional || settings.alertSetting != .enabled || settings.alertStyle == .none {
            return .alertsDisabled
        }
        return nil
    }

    static func refreshedIssue(_ previous: DeliveryError?, settings: NotificationClient.Settings) -> DeliveryError? {
        let issue = bannerIssue(in: settings)
        if issue == .permissionNeeded, case .authorizationFailed = previous { return previous }
        if issue == nil, case .submissionFailed = previous { return previous }
        return issue
    }

    static func openNotificationSettings(using open: (URL) -> Bool = { NSWorkspace.shared.open($0) }) -> Bool {
        // macOS has no public per-app settings API. Keep manual directions in the UI if this deep link changes.
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.singlepeel.lurkr")!,
            URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!,
            URL(fileURLWithPath: "/System/Applications/System Settings.app"),
        ]
        return urls.contains(where: open)
    }

    static func openFocusSettings(using open: (URL) -> Bool = { NSWorkspace.shared.open($0) }) -> Bool {
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension")!,
            URL(fileURLWithPath: "/System/Applications/System Settings.app"),
        ]
        return urls.contains(where: open)
    }

    private static func send(_ request: UNNotificationRequest, using client: NotificationClient,
                             requestPermission: Bool = false, requireBanner: Bool = false) async throws {
        var settings = await client.settings()
        if requestPermission && settings.authorizationStatus == .notDetermined {
            try await requestAuthorization(using: client)
            settings = await client.settings()
        }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            throw DeliveryError.notAuthorized
        }
        if requireBanner, let issue = bannerIssue(in: settings) { throw issue }
        try await client.add(request)
    }

    static func postGoLive(displayName: String, login: String, game: String, viewerCount: Int,
                           using client: NotificationClient? = nil) async throws {
        let content = UNMutableNotificationContent()
        content.title = "\(displayName) is live"
        var subtitleParts: [String] = []
        if !game.isEmpty { subtitleParts.append(game) }
        if viewerCount > 0 { subtitleParts.append("\(formatViewers(viewerCount)) viewers") }
        content.body = subtitleParts.joined(separator: " · ")
        content.userInfo = ["login": login]
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "golive.\(login).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try await send(request, using: client ?? .system)
    }

    private static func formatViewers(_ count: Int) -> String {
        if count >= 10_000 { return String(format: "%.0fK", Double(count) / 1000.0) }
        if count >= 1000   { return String(format: "%.1fK", Double(count) / 1000.0) }
        return "\(count)"
    }
}
