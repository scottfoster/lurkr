import Cocoa
import ServiceManagement
import UserNotifications

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let api = TwitchAPI()
    private var config: Config
    private var liveStreams: [Stream] = []
    private var pollTimer: Timer?
    private var lastRefresh: Date?
    private var isRefreshing = false
    private var hasConnectionError = false
    private var hasCompletedFirstRefresh = false

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
    }

    private func sendTestNotification() {
        Notifications.postGoLive(
            displayName: "piratesoftware",
            login: "piratesoftware",
            game: "Path of Exile 2",
            viewerCount: 1900
        )
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
        w.onSendTestNotification = { [unowned self] in self.sendTestNotification() }
        w.onShowAbout = { [unowned self] in self.showAbout() }
        settingsWindow = w
        w.showAndFocus()
    }

    private func applySettings(_ newConfig: Config) {
        let intervalChanged = newConfig.pollIntervalSeconds != config.pollIntervalSeconds
        config = newConfig
        config.save()
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
        let previousLive = Set(self.liveStreams.map { $0.userLogin.lowercased() })
        Task { @MainActor in
            let streams = await self.api.liveStreams(logins: logins)

            // Diff to find just-went-live before overwriting self.liveStreams.
            let nowLiveByLogin: [String: Stream] = Dictionary(
                uniqueKeysWithValues: streams.map { ($0.userLogin.lowercased(), $0) }
            )
            let newlyLive = Set(nowLiveByLogin.keys).subtracting(previousLive)
            if self.hasCompletedFirstRefresh && self.config.notificationsEnabled {
                for login in newlyLive {
                    guard let s = nowLiveByLogin[login] else { continue }
                    Notifications.postGoLive(
                        displayName: s.userLogin,
                        login: s.userLogin,
                        game: s.gameName,
                        viewerCount: s.viewerCount
                    )
                }
            }

            self.liveStreams = streams
            self.lastRefresh = Date()
            self.isRefreshing = false
            self.hasConnectionError = await self.api.lastCallHadConnectionError
            self.hasCompletedFirstRefresh = true
            let now = Date()
            for stream in streams {
                self.config.lastSeenLive[stream.userLogin.lowercased()] = now
            }
            self.config.save()
            self.updateIcon()
            self.rebuildPopover()

            // Backfill "last live" for offline favorites we've never observed,
            // by scraping the og:video:release_date from their most recent VOD.
            let liveSet = Set(streams.map { $0.userLogin.lowercased() })
            let needsBackfill = logins.filter { fav in
                let key = fav.lowercased()
                return !liveSet.contains(key) && self.config.lastSeenLive[key] == nil
            }
            guard !needsBackfill.isEmpty else { return }
            Task { @MainActor in
                var changed = false
                for fav in needsBackfill {
                    if let date = await self.api.lastStreamDate(login: fav) {
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
            hasConnectionError: hasConnectionError
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
        completionHandler([.banner, .sound])
    }
}
