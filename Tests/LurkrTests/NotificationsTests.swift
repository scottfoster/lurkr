import XCTest
import UserNotifications
@testable import Lurkr

@MainActor
final class NotificationsTests: XCTestCase {
    private final class Center {
        var settings = NotificationClient.Settings(authorizationStatus: .authorized, alertSetting: .enabled, alertStyle: .banner)
        var requests: [UNNotificationRequest] = []
        var authorizationRequests = 0
        var grantPermission = true
        var authorizationError: Error?
        var deliveryError: Error?

        var client: NotificationClient {
            NotificationClient(
                settings: { self.settings },
                authorize: {
                    self.authorizationRequests += 1
                    if let error = self.authorizationError { throw error }
                    self.settings.authorizationStatus = self.grantPermission ? .authorized : .denied
                    return self.grantPermission
                },
                add: {
                    if let error = self.deliveryError { throw error }
                    self.requests.append($0)
                }
            )
        }
    }

    func testRealAndTestNotificationsUseCheckedDeliveryAndDistinctContent() async throws {
        let center = Center()
        try await Notifications.sendTest(using: center.client)
        try await Notifications.postGoLive(displayName: "Streamer", login: "streamer", game: "Chess", viewerCount: 1900, using: center.client)
        XCTAssertEqual(center.requests.count, 2)
        let test = center.requests[0]
        XCTAssertEqual(test.content.title, "Lurkr test notification")
        XCTAssertNil(test.content.userInfo["login"])
        let live = center.requests[1]
        XCTAssertEqual(live.content.title, "Streamer is live")
        XCTAssertEqual(live.content.body, "Chess · 1.9K viewers")
        XCTAssertEqual(live.content.userInfo["login"] as? String, "streamer")
        XCTAssertNotNil(live.content.sound)
        XCTAssertNil(live.trigger)
        XCTAssertEqual(center.authorizationRequests, 0)
    }

    func testDeniedPermissionBlocksBothKindsWithoutSubmitting() async {
        let center = Center()
        center.settings.authorizationStatus = .denied
        for isTest in [true, false] {
            do {
                if isTest {
                    try await Notifications.sendTest(using: center.client)
                } else {
                    try await Notifications.postGoLive(displayName: "A", login: "a", game: "", viewerCount: 0, using: center.client)
                }
                XCTFail("Denied notifications must not report success")
            } catch {
                XCTAssertTrue(error is Notifications.DeliveryError)
            }
        }
        XCTAssertTrue(center.requests.isEmpty)
        XCTAssertEqual(center.authorizationRequests, 0)
    }

    func testTestRequestsUndeterminedPermissionAndRechecksTheDecision() async throws {
        let center = Center()
        center.settings.authorizationStatus = .notDetermined
        try await Notifications.sendTest(using: center.client)
        XCTAssertEqual(center.authorizationRequests, 1)
        XCTAssertEqual(center.requests.count, 1)

        center.settings.authorizationStatus = .notDetermined
        center.grantPermission = false
        do {
            try await Notifications.sendTest(using: center.client)
            XCTFail("A denied permission request must fail")
        } catch {
            XCTAssertTrue(error is Notifications.DeliveryError)
        }
        XCTAssertEqual(center.requests.count, 1)
    }

    func testAuthorizationAndSubmissionErrorsReachTheCaller() async {
        let center = Center()
        let failure = NSError(domain: "NotificationTest", code: 42)
        center.settings.authorizationStatus = .notDetermined
        center.authorizationError = failure
        do {
            try await Notifications.sendTest(using: center.client)
            XCTFail("Authorization errors must propagate")
        } catch {
            XCTAssertEqual(error as? Notifications.DeliveryError, .authorizationFailed(failure.localizedDescription))
        }
        center.settings.authorizationStatus = .authorized
        center.deliveryError = failure
        for isTest in [true, false] {
            do {
                if isTest {
                    try await Notifications.sendTest(using: center.client)
                } else {
                    try await Notifications.postGoLive(displayName: "A", login: "a", game: "", viewerCount: 0, using: center.client)
                }
                XCTFail("Submission errors must propagate")
            } catch {
                XCTAssertEqual(error as NSError, failure)
            }
        }
        XCTAssertTrue(center.requests.isEmpty)
    }

    func testBannerTestChecksBothAlertPermissionAndPresentationStyle() async throws {
        let center = Center()
        for settings in [
            NotificationClient.Settings(authorizationStatus: .authorized, alertSetting: .disabled, alertStyle: .banner),
            NotificationClient.Settings(authorizationStatus: .authorized, alertSetting: .enabled, alertStyle: .none),
        ] {
            center.settings = settings
            do {
                try await Notifications.sendTest(using: center.client)
                XCTFail("A banner test must explain disabled banners")
            } catch {
                guard case Notifications.DeliveryError.alertsDisabled = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
        // Real notifications may still appear in Notification Center or play a sound.
        try await Notifications.postGoLive(displayName: "A", login: "a", game: "", viewerCount: 0, using: center.client)
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertEqual(center.requests[0].content.body, "")
    }

    func testRepeatedNotificationsHaveUniqueIdentifiers() async throws {
        let center = Center()
        for _ in 0..<2 {
            try await Notifications.sendTest(using: center.client)
            try await Notifications.postGoLive(displayName: "A", login: "a", game: "", viewerCount: 0, using: center.client)
        }
        XCTAssertEqual(Set(center.requests.map(\.identifier)).count, 4)
    }

    func testBackgroundGoLiveDoesNotPromptForUndeterminedPermission() async {
        let center = Center()
        center.settings.authorizationStatus = .notDetermined
        do {
            try await Notifications.postGoLive(displayName: "A", login: "a", game: "", viewerCount: 0, using: center.client)
            XCTFail("An undetermined permission must not report delivery")
        } catch {
            XCTAssertTrue(error is Notifications.DeliveryError)
        }
        XCTAssertEqual(center.authorizationRequests, 0)
        XCTAssertTrue(center.requests.isEmpty)
    }

    func testSetupStatusDistinguishesPendingDeniedAndQuietPermissions() {
        let cases: [(UNAuthorizationStatus, UNNotificationSetting, UNAlertStyle, Notifications.DeliveryError?)] = [
            (.notDetermined, .enabled, .banner, .permissionNeeded),
            (.denied, .enabled, .banner, .notAuthorized),
            (.authorized, .disabled, .banner, .alertsDisabled),
            (.authorized, .enabled, .none, .alertsDisabled),
            (.provisional, .enabled, .banner, .alertsDisabled),
            (.authorized, .enabled, .banner, nil),
            (.authorized, .enabled, .alert, nil),
        ]
        for (authorization, alerts, style, expected) in cases {
            let settings = NotificationClient.Settings(authorizationStatus: authorization, alertSetting: alerts, alertStyle: style)
            XCTAssertEqual(Notifications.bannerIssue(in: settings), expected)
        }
    }

    func testAuthorizationDoesNotRepromptAfterAPermissionDecision() async throws {
        let center = Center()
        for status in [UNAuthorizationStatus.authorized, .denied] {
            center.settings.authorizationStatus = status
            try await Notifications.requestAuthorization(using: center.client)
        }
        XCTAssertEqual(center.authorizationRequests, 0)
        center.settings.authorizationStatus = .notDetermined
        try await Notifications.requestAuthorization(using: center.client)
        XCTAssertEqual(center.authorizationRequests, 1)
    }

    func testAuthorizationFailureSurvivesStatusRefreshAndClearsAfterSuccessfulRetry() async throws {
        let center = Center()
        center.settings.authorizationStatus = .notDetermined
        center.authorizationError = NSError(domain: "NotificationTest", code: 42)
        var issue: Notifications.DeliveryError?
        do {
            try await Notifications.requestAuthorization(using: center.client)
            XCTFail("Authorization should fail")
        } catch {
            issue = error as? Notifications.DeliveryError
        }
        guard case .authorizationFailed = issue else { return XCTFail("Missing authorization failure") }
        issue = Notifications.refreshedIssue(issue, settings: center.settings)
        guard case .authorizationFailed = issue else { return XCTFail("A refresh erased the failure") }
        XCTAssertEqual(issue?.needsAuthorization, true)
        center.authorizationError = nil
        try await Notifications.requestAuthorization(using: center.client)
        XCTAssertNil(Notifications.refreshedIssue(issue, settings: center.settings))
    }

    func testPermissionRefreshDoesNotEraseASubmissionFailure() {
        let center = Center()
        let failure = Notifications.DeliveryError.submissionFailed("Service unavailable")
        XCTAssertEqual(Notifications.refreshedIssue(failure, settings: center.settings), failure)
        center.settings.authorizationStatus = .denied
        XCTAssertEqual(Notifications.refreshedIssue(failure, settings: center.settings), .notAuthorized)
    }

    func testNotificationSettingsUsesAppShortcutAndFallsBackWithoutOpeningMoreWindows() {
        for successAt in [1, 2, 3, 0] {
            var attempts: [URL] = []
            let opened = Notifications.openNotificationSettings { url in
                attempts.append(url)
                return attempts.count == successAt
            }
            XCTAssertEqual(opened, successAt != 0)
            XCTAssertEqual(attempts.count, successAt == 0 ? 3 : successAt)
            let first = URLComponents(url: attempts[0], resolvingAgainstBaseURL: false)
            XCTAssertEqual(first?.scheme, "x-apple.systempreferences")
            XCTAssertEqual(first?.queryItems?.first(where: { $0.name == "id" })?.value, "com.singlepeel.lurkr")
            if attempts.count >= 2 {
                XCTAssertEqual(attempts[1].absoluteString, "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
            }
        }
    }

    func testFocusSettingsHasItsOwnShortcutAndSystemSettingsFallback() {
        var attempts: [URL] = []
        XCTAssertTrue(Notifications.openFocusSettings { url in
            attempts.append(url)
            return attempts.count == 2
        })
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(attempts.first?.absoluteString, "x-apple.systempreferences:com.apple.Focus-Settings.extension")
        XCTAssertEqual(attempts.last?.path, "/System/Applications/System Settings.app")
    }
}
