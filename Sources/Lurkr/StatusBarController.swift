import Cocoa
import ServiceManagement
import UserNotifications

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let api = TwitchAPI()
    private var config: Config
    private var liveStreams: [Stream] { liveStatusTracker.streams }
    private var pollTimer: Timer?
    private var lastRefresh: Date?
    private var isRefreshing = false
    private var hasConnectionError = false
    private var liveStatusTracker = LiveStatusTracker()
    private var notificationIssue: Notifications.DeliveryError?
    private var isRequestingNotificationPermission = false

    private let popover = NSPopover()
    private let popoverVC = MainPopoverViewController()
    private var aboutWindow: AboutWindowController?
    private var settingsWindow: SettingsWindowController?

    override init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.config = Config.load()
        super.init()

        statusItem.button?.image = Icon.grey
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopoverFromButton)

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = popoverVC

        popoverVC.onOpenStream = { [unowned self] login in self.openStream(login: login) }
        popoverVC.onAddFavorite = { [unowned self] login in await self.addFavorite(login: login) }
        popoverVC.onRemoveFavorite = { [unowned self] login in self.confirmRemoveFavorite(login: login) }
        popoverVC.onRefresh = { [unowned self] in self.refresh(manual: true) }
        popoverVC.onOpenURL = { [unowned self] url in self.openInPreferredBrowser(url) }
        popoverVC.onOpenSettings = { [unowned self] in self.showSettings() }

        rebuildPopover()
        refresh(manual: false)
        restartPollTimer()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func appDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in await self.refreshNotificationStatus() }
    }

    func requestNotificationAuthorization() {
        guard !isRequestingNotificationPermission else { return }
        isRequestingNotificationPermission = true
        Task { @MainActor in
            defer { self.isRequestingNotificationPermission = false }
            do {
                try await Notifications.requestAuthorization()
            } catch {
                self.notificationIssue = (error as? Notifications.DeliveryError) ?? .authorizationFailed(error.localizedDescription)
                Notifications.logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            }
            await self.refreshNotificationStatus()
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await NotificationClient.system.settings()
        notificationIssue = Notifications.refreshedIssue(notificationIssue, settings: settings)
        updateNotificationUI()
    }

    private func updateNotificationUI() {
        settingsWindow?.updateNotificationIssue(notificationIssue)
        rebuildPopover()
    }

    @objc private func appDidResignActive(_ notification: Notification) {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    // MARK: - Status item click

    @objc private func togglePopoverFromButton() {
        togglePopover()
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        rebuildPopover()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        Task { @MainActor in await self.refreshNotificationStatus() }
    }

    private func sendTestNotification() async -> Bool {
        do {
            try await Notifications.sendTest()
            notificationIssue = nil
            await refreshNotificationStatus()
            return true
        } catch {
            notificationIssue = (error as? Notifications.DeliveryError) ?? .submissionFailed(error.localizedDescription)
            await refreshNotificationStatus()
            return false
        }
    }

    private func showAbout() {
        if aboutWindow == nil {
            let w = AboutWindowController()
            w.onOpenURL = { [unowned self] url in self.openInPreferredBrowser(url) }
            aboutWindow = w
        }
        aboutWindow?.showAndFocus()
    }

    private func showSettings() {
        if let existing = settingsWindow {
            existing.update(config: config)
            existing.showAndFocus()
            return
        }
        let w = SettingsWindowController(config: config, isAppBundle: isAppBundle)
        w.onConfigChanged = { [unowned self] newConfig in
            self.applySettings(newConfig)
        }
        w.onToggleLaunchAtLogin = { [unowned self] in self.toggleLaunchAtLogin() }
        w.onSendTestNotification = { [unowned self] in await self.sendTestNotification() }
        w.onRefreshNotificationStatus = { [weak self] in
            Task { @MainActor in await self?.refreshNotificationStatus() }
        }
        w.onResolveNotificationIssue = { [unowned self] in
            if self.notificationIssue?.needsAuthorization == true {
                self.requestNotificationAuthorization()
            } else if !Notifications.openNotificationSettings() {
                self.showAlert(title: "Couldn't open Notification Settings",
                               message: "Open System Settings → Notifications → Lurkr. Turn on Allow Notifications and choose Banners or Alerts, then return to Lurkr and send a test.")
            }
        }
        w.onOpenFocusSettings = { [unowned self] in
            if !Notifications.openFocusSettings() {
                self.showAlert(title: "Couldn't open Focus Settings",
                               message: "Open System Settings → Focus. Turn off the active Focus or allow notifications from Lurkr, then send another test.")
            }
        }
        w.onShowAbout = { [unowned self] in self.showAbout() }
        settingsWindow = w
        w.updateNotificationIssue(notificationIssue)
        w.showAndFocus()
    }

    private func applySettings(_ newConfig: Config) {
        let intervalChanged = newConfig.pollIntervalSeconds != config.pollIntervalSeconds
        let notificationsBecameEnabled = newConfig.notificationsEnabled && !config.notificationsEnabled
        config = newConfig
        config.save()
        updateNotificationUI()
        if notificationsBecameEnabled { requestNotificationAuthorization() }
        if intervalChanged { restartPollTimer() }
    }

    private func restartPollTimer() {
        pollTimer?.invalidate()
        let interval = TimeInterval(max(10, config.pollIntervalSeconds))
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(manual: false) }
        }
    }

    private var isAppBundle: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert(title: "Couldn't change Launch at Login", message: error.localizedDescription)
        }
    }

    // MARK: - Refresh

    func refresh(manual: Bool) {
        guard !isRefreshing else { return }
        isRefreshing = true
        rebuildPopover()

        let logins = config.favorites
        Task { @MainActor in
            let statuses = await self.api.liveStreams(logins: logins)
            let favorites = Set(self.config.favorites.map { $0.lowercased() })
            let newlyLive = self.liveStatusTracker.update(statuses, favorites: favorites)
            let streams = self.liveStreams

            self.lastRefresh = Date()
            self.isRefreshing = false
            self.hasConnectionError = favorites.contains { login in
                if case .unknown = statuses[login] ?? .unknown { return true }
                return false
            }
            let now = Date()
            for (login, status) in statuses where favorites.contains(login) {
                if case .live = status { self.config.lastSeenLive[login] = now }
            }
            self.config.save()
            self.updateIcon()
            self.rebuildPopover()

            if self.config.notificationsEnabled {
                for stream in newlyLive {
                    guard self.config.notificationsEnabled,
                          self.config.favorites.contains(where: { $0.lowercased() == stream.userLogin.lowercased() }) else { continue }
                    do {
                        try await Notifications.postGoLive(
                            displayName: stream.userLogin,
                            login: stream.userLogin,
                            game: stream.gameName,
                            viewerCount: stream.viewerCount
                        )
                        self.notificationIssue = nil
                    } catch {
                        self.notificationIssue = .submissionFailed(error.localizedDescription)
                        Notifications.logger.error("Go-live notification failed: \(error.localizedDescription, privacy: .public)")
                    }
                    await self.refreshNotificationStatus()
                }
            }

            // Backfill "last live" for offline favorites we've never observed,
            // by scraping the og:video:release_date from their most recent VOD.
            let liveSet = Set(streams.map { $0.userLogin.lowercased() })
            let needsBackfill = self.config.favorites.filter { fav in
                let key = fav.lowercased()
                if case .offline = statuses[key] {
                    return !liveSet.contains(key) && self.config.lastSeenLive[key] == nil
                }
                return false
            }
            guard !needsBackfill.isEmpty else { return }
            Task { @MainActor in
                var changed = false
                for fav in needsBackfill {
                    if let date = await self.api.lastStreamDate(login: fav) {
                        guard self.config.favorites.contains(where: { $0.lowercased() == fav.lowercased() }),
                              self.config.lastSeenLive[fav.lowercased()] == nil else { continue }
                        self.config.lastSeenLive[fav.lowercased()] = date
                        changed = true
                    }
                }
                if changed {
                    self.config.save()
                    self.rebuildPopover()
                }
            }
        }
    }

    private func updateIcon() {
        statusItem.button?.image = liveStreams.isEmpty ? Icon.grey : Icon.purple
    }

    private func rebuildPopover() {
        popoverVC.setContent(
            streams: liveStreams,
            favorites: config.favorites,
            lastSeenLive: config.lastSeenLive,
            lastRefresh: lastRefresh,
            isRefreshing: isRefreshing,
            hasConnectionError: hasConnectionError,
            notificationIssue: config.notificationsEnabled ? notificationIssue : nil
        )
        if popover.isShown {
            popover.contentSize = popoverVC.preferredContentSize
        }
    }

    // MARK: - Actions

    private func openStream(login: String) {
        guard let url = URL(string: "https://www.twitch.tv/\(login)") else { return }
        openInPreferredBrowser(url)
        popover.performClose(nil)
    }

    /// Opens a URL in the user's selected browser (Config.browser). Falls back to
    /// the system default browser if the chosen app isn't installed.
    func openInPreferredBrowser(_ url: URL) {
        let appPath = URL(fileURLWithPath: config.browser.appPath)
        if FileManager.default.fileExists(atPath: appPath.path) {
            NSWorkspace.shared.open([url], withApplicationAt: appPath, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func addFavorite(login: String) async -> String? {
        if config.favorites.contains(where: { $0.caseInsensitiveCompare(login) == .orderedSame }) {
            return "Already in your favorites."
        }
        let exists = await api.userExists(login: login)
        guard exists else { return "No Twitch user with that name." }
        config.favorites.append(login)
        config.favorites.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        config.save()
        rebuildPopover()
        refresh(manual: false)
        return nil
    }

    private func confirmRemoveFavorite(login: String) {
        let previousBehavior = popover.behavior
        popover.behavior = .applicationDefined

        let alert = NSAlert()
        alert.messageText = "Remove \(login) from favorites?"
        alert.alertStyle = .warning
        let removeBtn = alert.addButton(withTitle: "Remove")
        removeBtn.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        popover.behavior = previousBehavior

        guard response == .alertFirstButtonReturn else { return }
        config.favorites.removeAll { $0.caseInsensitiveCompare(login) == .orderedSame }
        config.save()
        rebuildPopover()
        refresh(manual: false)
    }

    private func showAlert(title: String, message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

// MARK: - Notification tap routing

extension StatusBarController: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let login = userInfo["login"] as? String
        Task { @MainActor in
            if let login {
                self.openStream(login: login)
            }
            completionHandler()
        }
    }

    /// Show notifications even when our app is foregrounded (status-bar apps
    /// usually need .banner/.sound here or banners are suppressed).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
