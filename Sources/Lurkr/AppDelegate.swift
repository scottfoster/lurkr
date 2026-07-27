import Cocoa
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let c = StatusBarController()
        controller = c
        UNUserNotificationCenter.current().delegate = c
        Notifications.requestAuthorization()
    }
}
