import Cocoa
import ServiceManagement

@MainActor
final class SettingsWindowController: NSWindowController {
    var onConfigChanged: ((Config) -> Void)?
    var onToggleLaunchAtLogin: (() -> Void)?
    var onSendTestNotification: (() -> Void)?
    var onShowAbout: (() -> Void)?

    private var currentConfig: Config
    private let isAppBundle: Bool

    private let intervalPopup = NSPopUpButton()
    private let browserPopup = NSPopUpButton()
    private let launchAtLoginSwitch = NSSwitch()
    private let notifySwitch = NSSwitch()

    private static let intervalChoices: [(label: String, seconds: Int)] = [
        ("30 seconds", 30),
        ("1 minute",   60),
        ("2 minutes",  120),
        ("5 minutes",  300),
    ]

    init(config: Config, isAppBundle: Bool) {
        self.currentConfig = config
        self.isAppBundle = isAppBundle
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Lurkr Settings"
        win.isReleasedWhenClosed = false
        win.center()
        super.init(window: win)
        buildUI()
        loadFromConfig()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func update(config: Config) {
        currentConfig = config
        loadFromConfig()
    }

    func showAndFocus() {
        NSApp.activate(ignoringOtherApps: true)
        loadFromConfig()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        for (label, _) in Self.intervalChoices {
            intervalPopup.addItem(withTitle: label)
        }
        intervalPopup.target = self
        intervalPopup.action = #selector(intervalChanged)

        for browser in Browser.allCases {
            browserPopup.addItem(withTitle: browser.displayName)
        }
        browserPopup.target = self
        browserPopup.action = #selector(browserChanged)

        let popupWidth: CGFloat = 120
        intervalPopup.translatesAutoresizingMaskIntoConstraints = false
        browserPopup.translatesAutoresizingMaskIntoConstraints = false
        intervalPopup.widthAnchor.constraint(equalToConstant: popupWidth).isActive = true
        browserPopup.widthAnchor.constraint(equalToConstant: popupWidth).isActive = true

        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(launchAtLoginChanged)
        launchAtLoginSwitch.isEnabled = isAppBundle

        notifySwitch.target = self
        notifySwitch.action = #selector(notificationsChanged)

        // Notifications row carries the switch + a small "Send test" button stacked together.
        let notifyCluster = NSStackView()
        notifyCluster.orientation = .horizontal
        notifyCluster.spacing = 8
        notifyCluster.alignment = .centerY
        notifyCluster.translatesAutoresizingMaskIntoConstraints = false
        let testBtn = NSButton(title: "Send test", target: self, action: #selector(testNotificationClicked))
        testBtn.bezelStyle = .rounded
        testBtn.controlSize = .small
        notifyCluster.addArrangedSubview(testBtn)
        notifyCluster.addArrangedSubview(notifySwitch)

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.distribution = .gravityAreas
        root.spacing = 22
        root.edgeInsets = NSEdgeInsets(top: 24, left: 26, bottom: 24, right: 26)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
        ])

        let launchHelper = isAppBundle
            ? "Open Lurkr automatically when you log in."
            : "Available only when Lurkr is installed in /Applications."

        root.addArrangedSubview(makeSection(
            header: "GENERAL",
            rows: [
                makeRow(title: "Refresh interval",
                        helper: "How often Lurkr checks for live streamers.",
                        control: intervalPopup),
                makeSeparator(),
                makeRow(title: "Open streams in",
                        helper: "Which browser to launch when you click a stream.",
                        control: browserPopup),
                makeSeparator(),
                makeRow(title: "Launch at login",
                        helper: launchHelper,
                        control: launchAtLoginSwitch),
            ]
        ))

        root.addArrangedSubview(makeSection(
            header: "NOTIFICATIONS",
            rows: [
                makeRow(title: "Notify on go-live",
                        helper: "Show a banner when a favorite starts streaming.",
                        control: notifyCluster),
            ]
        ))

        // About link footer
        let aboutBtn = NSButton(title: "About Lurkr…",
                                target: self,
                                action: #selector(aboutClicked))
        aboutBtn.bezelStyle = .accessoryBarAction
        aboutBtn.isBordered = false
        aboutBtn.attributedTitle = NSAttributedString(
            string: "About Lurkr…",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.linkColor,
            ]
        )
        root.addArrangedSubview(aboutBtn)
    }

    // MARK: - Section / row builders

    private func makeSection(header: String, rows: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .gravityAreas
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let h = NSTextField(labelWithString: header)
        h.font = .systemFont(ofSize: 11, weight: .semibold)
        h.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(h)

        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.5).cgColor
        box.layer?.cornerRadius = 10
        box.layer?.borderWidth = 0.5
        box.layer?.borderColor = NSColor.separatorColor.cgColor

        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .width
        inner.distribution = .gravityAreas
        inner.spacing = 0
        inner.translatesAutoresizingMaskIntoConstraints = false
        for r in rows { inner.addArrangedSubview(r) }

        box.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            inner.topAnchor.constraint(equalTo: box.topAnchor),
            inner.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            box.widthAnchor.constraint(equalToConstant: 388),
        ])

        stack.addArrangedSubview(box)
        return stack
    }

    private func makeRow(title: String, helper: String, control: NSView) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let helperLabel = NSTextField(wrappingLabelWithString: helper)
        helperLabel.font = .systemFont(ofSize: 11)
        helperLabel.textColor = .secondaryLabelColor
        helperLabel.translatesAutoresizingMaskIntoConstraints = false
        helperLabel.maximumNumberOfLines = 2

        control.translatesAutoresizingMaskIntoConstraints = false
        control.setContentHuggingPriority(.required, for: .horizontal)

        row.addSubview(titleLabel)
        row.addSubview(helperLabel)
        row.addSubview(control)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -12),

            helperLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            helperLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            helperLabel.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -12),
            helperLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),

            control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    private func makeSeparator() -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false

        let line = NSView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        wrapper.addSubview(line)

        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
            line.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            line.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 0.5),
            wrapper.heightAnchor.constraint(equalToConstant: 0.5),
        ])
        return wrapper
    }

    private func loadFromConfig() {
        let idx = Self.intervalChoices.firstIndex { $0.seconds == currentConfig.pollIntervalSeconds } ?? 1
        intervalPopup.selectItem(at: idx)

        let bIdx = Browser.allCases.firstIndex(of: currentConfig.browser) ?? 0
        browserPopup.selectItem(at: bIdx)

        notifySwitch.state = currentConfig.notificationsEnabled ? .on : .off
        launchAtLoginSwitch.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    @objc private func intervalChanged() {
        let idx = max(0, intervalPopup.indexOfSelectedItem)
        currentConfig.pollIntervalSeconds = Self.intervalChoices[idx].seconds
        onConfigChanged?(currentConfig)
    }

    @objc private func browserChanged() {
        let idx = max(0, browserPopup.indexOfSelectedItem)
        currentConfig.browser = Browser.allCases[idx]
        onConfigChanged?(currentConfig)
    }

    @objc private func notificationsChanged() {
        currentConfig.notificationsEnabled = (notifySwitch.state == .on)
        onConfigChanged?(currentConfig)
    }

    @objc private func launchAtLoginChanged() {
        onToggleLaunchAtLogin?()
        // Re-read the real state; SMAppService may have flipped to .requiresApproval
        // or failed entirely.
        launchAtLoginSwitch.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    @objc private func testNotificationClicked() {
        onSendTestNotification?()
    }

    @objc private func aboutClicked() {
        onShowAbout?()
    }
}
