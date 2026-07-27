import Cocoa
import UserNotifications

/// Thin wrapper around UNUserNotificationCenter for go-live alerts.
@MainActor
enum Notifications {
    /// Asks the system for permission to show alerts/sounds. The user only sees
    /// the prompt once; later calls are no-ops on already-decided state.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    /// Post a notification "<displayName> is live" with subtitle "<game> · <viewers> viewers".
    /// The userInfo dictionary carries the login for the tap-handler to route to.
    static func postGoLive(displayName: String, login: String, game: String, viewerCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(displayName) is live"
        var subtitleParts: [String] = []
        if !game.isEmpty { subtitleParts.append(game) }
        if viewerCount > 0 { subtitleParts.append("\(formatViewers(viewerCount)) viewers") }
        content.body = subtitleParts.joined(separator: " · ")
        content.userInfo = ["login": login]
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "golive.\(login).\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil  // fire immediately
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private static func formatViewers(_ count: Int) -> String {
        if count >= 10_000 { return String(format: "%.0fK", Double(count) / 1000.0) }
        if count >= 1000   { return String(format: "%.1fK", Double(count) / 1000.0) }
        return "\(count)"
    }
}
