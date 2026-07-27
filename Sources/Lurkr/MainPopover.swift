import Cocoa

@MainActor
final class MainPopoverViewController: NSViewController {

    // MARK: - Public callbacks (wired by StatusBarController)
    var onOpenStream: ((String) -> Void)?
    var onAddFavorite: ((String) async -> String?)?
    var onRemoveFavorite: ((String) -> Void)?
    var onRefresh: (() -> Void)?
    var onOpenURL: ((URL) -> Void)?
    var onOpenSettings: (() -> Void)?

    // MARK: - State
    private var streams: [Stream] = []
    private var favorites: [String] = []
    private var lastSeenLive: [String: Date] = [:]
    private var isAdding = false
    private var isWorking = false
    private var lastRefresh: Date?
    private var isRefreshing = false
    private var hasConnectionError = false

    // MARK: - Layout constants
    private static let width: CGFloat = 320

    // MARK: - Persistent UI
    private let rootStack = NSStackView()
    private let addField = NSTextField()
    private let addStatusLabel = NSTextField(labelWithString: "")
    private let addSpinner = NSProgressIndicator()

    func setContent(streams: [Stream], favorites: [String], lastSeenLive: [String: Date], lastRefresh: Date?, isRefreshing: Bool, hasConnectionError: Bool) {
        self.streams = streams
        self.favorites = favorites
        self.lastSeenLive = lastSeenLive
        self.lastRefresh = lastRefresh
        self.isRefreshing = isRefreshing
        self.hasConnectionError = hasConnectionError
        if isViewLoaded {
            rebuild()
            preferredContentSize = NSSize(width: Self.width, height: contentHeight())
        }
    }

    /// Explicit height calculation that matches the constraint-based heights of each row.
    /// `view.fittingSize` was over-reporting and leaving extra padding below the footer.
    private func contentHeight() -> CGFloat {
        var h: CGFloat = 4 // top spacer
        if hasConnectionError { h += 30 }
        if !streams.isEmpty {
            h += 22 + 4                              // LIVE NOW section label
            h += CGFloat(streams.count) * 60         // stream cards
        }
        h += 22 + (streams.isEmpty ? 4 : 10)         // FAVORITES section label
        if isAdding { h += 54 }
        if favorites.isEmpty && !isAdding {
            h += 30                                  // empty-state row
        } else {
            h += CGFloat(favorites.count) * 30       // favorite rows
        }
        h += 6  // bottom spacer
        h += 1  // divider
        h += 32 // footer
        return h
    }

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 0
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: container.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: Self.width),
        ])
        view = container
        rebuild()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if !isWorking {
            isAdding = false
            addField.stringValue = ""
            addStatusLabel.stringValue = ""
        }
    }

    // MARK: - Build

    private func rebuild() {
        for v in rootStack.arrangedSubviews {
            rootStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        rootStack.addArrangedSubview(spacer(4))

        if hasConnectionError {
            rootStack.addArrangedSubview(makeConnectionBanner())
        }

        if !streams.isEmpty {
            rootStack.addArrangedSubview(makeSectionLabel("LIVE NOW", topPad: 4))
            let sorted = streams.sorted(by: { $0.viewerCount > $1.viewerCount })
            for s in sorted {
                rootStack.addArrangedSubview(makeStreamCard(s))
            }
        }

        rootStack.addArrangedSubview(makeSectionLabel("FAVORITES", topPad: streams.isEmpty ? 4 : 10))
        if isAdding {
            rootStack.addArrangedSubview(makeAddInput())
        }
        if favorites.isEmpty && !isAdding {
            rootStack.addArrangedSubview(makeEmptyFavorites())
        } else {
            let sortedFavorites = favorites.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            for fav in sortedFavorites {
                let isLive = streams.contains { $0.userLogin.caseInsensitiveCompare(fav) == .orderedSame }
                rootStack.addArrangedSubview(makeFavoriteRow(login: fav, isLive: isLive))
            }
        }

        rootStack.addArrangedSubview(spacer(6))
        rootStack.addArrangedSubview(makeDivider())
        rootStack.addArrangedSubview(makeFooter())

        if isAdding {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.view.window?.makeFirstResponder(self.addField)
            }
        }
    }

    // MARK: - Builders

    private func makeConnectionBanner() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.18).cgColor

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        icon.contentTintColor = .systemOrange
        icon.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(icon)

        let label = NSTextField(wrappingLabelWithString: "Can't reach decapi.me. Live status may be stale.")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(label)

        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: Self.width),
            v.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            icon.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: v.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -6),
        ])
        return v
    }

    private func makeSectionLabel(_ text: String, topPad: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(label)
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: Self.width),
            v.heightAnchor.constraint(equalToConstant: 22 + topPad),
            label.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 14),
            label.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -4),
        ])
        return v
    }

    private func makeStreamCard(_ s: Stream) -> NSView {
        let card = HoverableRow()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.onClick = { [weak self] in self?.onOpenStream?(s.userLogin) }

        let thumb = NSImageView()
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 4
        thumb.layer?.masksToBounds = true
        thumb.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        thumb.translatesAutoresizingMaskIntoConstraints = false
        if let data = s.thumbnailData, let img = NSImage(data: data) {
            thumb.image = img
        }
        card.addSubview(thumb)

        let live = NSTextField(labelWithString: "LIVE")
        live.font = .systemFont(ofSize: 9, weight: .heavy)
        live.textColor = .white
        live.alignment = .center
        live.wantsLayer = true
        live.drawsBackground = true
        live.backgroundColor = NSColor(red: 0.92, green: 0.20, blue: 0.20, alpha: 1.0)
        live.layer?.cornerRadius = 3
        live.layer?.masksToBounds = true
        live.isBezeled = false
        live.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(live)

        let name = NSTextField(labelWithString: s.userLogin)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(name)

        let sub = NSTextField(labelWithString: subtitleFor(s))
        sub.font = .systemFont(ofSize: 11)
        sub.textColor = .secondaryLabelColor
        sub.lineBreakMode = .byTruncatingTail
        sub.maximumNumberOfLines = 1
        sub.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(sub)

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: Self.width),
            card.heightAnchor.constraint(equalToConstant: 60),

            thumb.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            thumb.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            thumb.widthAnchor.constraint(equalToConstant: 72),
            thumb.heightAnchor.constraint(equalToConstant: 40),

            live.topAnchor.constraint(equalTo: thumb.topAnchor, constant: 4),
            live.leadingAnchor.constraint(equalTo: thumb.leadingAnchor, constant: 4),
            live.heightAnchor.constraint(equalToConstant: 13),
            live.widthAnchor.constraint(equalToConstant: 28),

            name.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 10),
            name.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -14),
            name.topAnchor.constraint(equalTo: thumb.topAnchor, constant: 1),

            sub.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            sub.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            sub.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2),
        ])
        return card
    }

    private func subtitleFor(_ s: Stream) -> String {
        var parts: [String] = []
        if !s.gameName.isEmpty { parts.append(s.gameName) }
        if s.viewerCount > 0 { parts.append("\(Self.formatViewers(s.viewerCount)) viewers") }
        let up = Self.shortUptime(s.uptime)
        if !up.isEmpty { parts.append(up) }
        return parts.joined(separator: " · ")
    }

    /// Collapses decapi's verbose uptime ("2 hours, 53 minutes, 33 seconds") to "2h 53m".
    /// Returns the most-significant non-zero unit and the next one if both are hours/minutes.
    static func shortUptime(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        let lower = raw.lowercased()
        // decapi format is "<n> hour[s], <m> minute[s], <s> second[s]" (or "<n> day[s]" prefix)
        func extract(_ unit: String) -> Int? {
            // match e.g. "(\d+) hour"
            let pattern = #"(\d+)\s+\#(unit)"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            guard let m = regex.firstMatch(in: lower, range: range),
                  m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: lower) else { return nil }
            return Int(lower[r])
        }
        let days = extract("day") ?? 0
        let hours = extract("hour") ?? 0
        let mins = extract("minute") ?? 0
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h" }
        if mins > 0 { return "\(mins)m" }
        return ""
    }

    static func formatViewers(_ count: Int) -> String {
        if count >= 10_000 { return String(format: "%.0fK", Double(count) / 1000.0) }
        if count >= 1000   { return String(format: "%.1fK", Double(count) / 1000.0) }
        return "\(count)"
    }

    private func makeFavoriteRow(login: String, isLive: Bool) -> NSView {
        let row = HoverableRow()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.onClick = { [weak self] in
            if isLive { self?.onOpenStream?(login) }
        }

        let dot = NSView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = (isLive
            ? NSColor(red: 0.576, green: 0.247, blue: 1.0, alpha: 1.0)
            : NSColor.tertiaryLabelColor).cgColor
        row.addSubview(dot)

        let name = NSTextField(labelWithString: login)
        name.font = .systemFont(ofSize: 13)
        name.textColor = isLive ? .labelColor : .secondaryLabelColor
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(name)

        let lastSeenText: String
        if !isLive, let seen = lastSeenLive[login.lowercased()] {
            lastSeenText = Self.relativeShort(from: seen)
        } else {
            lastSeenText = ""
        }
        let lastSeen = NSTextField(labelWithString: lastSeenText)
        lastSeen.font = .systemFont(ofSize: 11)
        lastSeen.textColor = .tertiaryLabelColor
        lastSeen.translatesAutoresizingMaskIntoConstraints = false
        lastSeen.setContentHuggingPriority(.required, for: .horizontal)
        lastSeen.setContentCompressionResistancePriority(.required, for: .horizontal)
        row.addSubview(lastSeen)

        let remove = NSButton(title: "", target: self, action: #selector(removeFavoriteClicked(_:)))
        remove.bezelStyle = .accessoryBarAction
        remove.isBordered = false
        remove.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove")
        remove.contentTintColor = .tertiaryLabelColor
        remove.identifier = NSUserInterfaceItemIdentifier(login)
        remove.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(remove)

        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: Self.width),
            row.heightAnchor.constraint(equalToConstant: 30),
            dot.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            dot.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            name.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 10),
            name.trailingAnchor.constraint(lessThanOrEqualTo: lastSeen.leadingAnchor, constant: -8),
            name.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            lastSeen.trailingAnchor.constraint(equalTo: remove.leadingAnchor, constant: -8),
            lastSeen.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            remove.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
            remove.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            remove.widthAnchor.constraint(equalToConstant: 18),
            remove.heightAnchor.constraint(equalToConstant: 18),
        ])
        return row
    }

    private static func relativeShort(from date: Date, now: Date = Date()) -> String {
        let secs = Int(now.timeIntervalSince(date))
        if secs < 60 { return "just now" }
        if secs < 3600 { return "\(secs / 60)m ago" }
        if secs < 86_400 { return "\(secs / 3600)h ago" }
        let days = secs / 86_400
        if days < 30 { return "\(days)d ago" }
        let months = days / 30
        if months < 12 { return "\(months)mo ago" }
        return "\(months / 12)y ago"
    }

    @objc private func removeFavoriteClicked(_ sender: NSButton) {
        guard let login = sender.identifier?.rawValue else { return }
        onRemoveFavorite?(login)
    }

    private func makeEmptyFavorites() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: "Press + below to add your first favorite.")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(label)
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: Self.width),
            v.heightAnchor.constraint(equalToConstant: 30),
            label.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 18),
            label.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }

    private func makeAddInput() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false

        addField.placeholderString = "Twitch username"
        addField.bezelStyle = .roundedBezel
        addField.font = .systemFont(ofSize: 12)
        addField.target = self
        addField.action = #selector(addFromField)
        addField.isEnabled = true
        addField.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(addField)

        let submit = NSButton(title: "Add", target: self, action: #selector(addFromField))
        submit.bezelStyle = .rounded
        submit.controlSize = .small
        submit.keyEquivalent = "\r"
        submit.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(submit)

        addSpinner.style = .spinning
        addSpinner.controlSize = .small
        addSpinner.isDisplayedWhenStopped = false
        addSpinner.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(addSpinner)

        addStatusLabel.font = .systemFont(ofSize: 11)
        addStatusLabel.textColor = .secondaryLabelColor
        addStatusLabel.lineBreakMode = .byTruncatingTail
        addStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(addStatusLabel)

        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: Self.width),
            v.heightAnchor.constraint(equalToConstant: 54),
            addField.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 14),
            addField.trailingAnchor.constraint(equalTo: submit.leadingAnchor, constant: -8),
            addField.topAnchor.constraint(equalTo: v.topAnchor, constant: 0),
            addField.heightAnchor.constraint(equalToConstant: 22),
            submit.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -14),
            submit.centerYAnchor.constraint(equalTo: addField.centerYAnchor),
            submit.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),
            addSpinner.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 14),
            addSpinner.topAnchor.constraint(equalTo: addField.bottomAnchor, constant: 6),
            addSpinner.widthAnchor.constraint(equalToConstant: 12),
            addSpinner.heightAnchor.constraint(equalToConstant: 12),
            addStatusLabel.leadingAnchor.constraint(equalTo: addSpinner.trailingAnchor, constant: 4),
            addStatusLabel.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -14),
            addStatusLabel.centerYAnchor.constraint(equalTo: addSpinner.centerYAnchor),
        ])
        return v
    }

    @objc private func toggleAdding() {
        if isWorking { return }
        isAdding.toggle()
        addStatusLabel.stringValue = ""
        addField.stringValue = ""
        rebuild()
    }

    @objc private func addFromField() {
        guard !isWorking else { return }
        let raw = addField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !raw.isEmpty else { return }

        isWorking = true
        addField.isEnabled = false
        addSpinner.startAnimation(nil)
        addStatusLabel.textColor = .secondaryLabelColor
        addStatusLabel.stringValue = "Checking…"

        Task { @MainActor in
            let error = await self.onAddFavorite?(raw)
            self.addSpinner.stopAnimation(nil)
            self.addField.isEnabled = true
            self.isWorking = false
            if let error {
                self.addStatusLabel.textColor = .systemRed
                self.addStatusLabel.stringValue = error
                self.view.window?.makeFirstResponder(self.addField)
            } else {
                self.isAdding = false
                self.rebuild()
            }
        }
    }

    private func makeDivider() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.separatorColor.cgColor
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        v.widthAnchor.constraint(equalToConstant: Self.width).isActive = true
        return v
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        v.widthAnchor.constraint(equalToConstant: Self.width).isActive = true
        return v
    }

    private func makeFooter() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false

        let orange = NSButton(title: "🍊", target: self, action: #selector(openSinglepeel))
        orange.bezelStyle = .accessoryBarAction
        orange.isBordered = false
        orange.font = .systemFont(ofSize: 14)
        orange.toolTip = "singlepeel.com"
        orange.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(orange)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let label = NSTextField(labelWithString: isRefreshing ? "Updating…" : "Lurkr \(version)")
        label.font = .systemFont(ofSize: 10)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(label)

        let addBtn = NSButton(title: "", target: self, action: #selector(toggleAdding))
        addBtn.bezelStyle = .accessoryBarAction
        addBtn.isBordered = false
        addBtn.image = NSImage(
            systemSymbolName: isAdding ? "xmark.circle.fill" : "plus.circle.fill",
            accessibilityDescription: isAdding ? "Cancel" : "Add favorite"
        )
        addBtn.contentTintColor = .secondaryLabelColor
        addBtn.toolTip = isAdding ? "Cancel" : "Add favorite"
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(addBtn)

        let settingsBtn = NSButton(title: "", target: self, action: #selector(settingsClicked))
        settingsBtn.bezelStyle = .accessoryBarAction
        settingsBtn.isBordered = false
        settingsBtn.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings")
        settingsBtn.contentTintColor = .secondaryLabelColor
        settingsBtn.toolTip = "Settings"
        settingsBtn.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(settingsBtn)

        let trailing: NSView
        if isRefreshing {
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.isDisplayedWhenStopped = false
            spinner.startAnimation(nil)
            spinner.translatesAutoresizingMaskIntoConstraints = false
            trailing = spinner
        } else {
            let refresh = NSButton(title: "", target: self, action: #selector(refreshClicked))
            refresh.bezelStyle = .accessoryBarAction
            refresh.isBordered = false
            refresh.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
            refresh.contentTintColor = .secondaryLabelColor
            refresh.toolTip = "Refresh now"
            refresh.translatesAutoresizingMaskIntoConstraints = false
            trailing = refresh
        }
        v.addSubview(trailing)

        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: Self.width),
            v.heightAnchor.constraint(equalToConstant: 32),
            orange.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 10),
            orange.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            orange.widthAnchor.constraint(equalToConstant: 20),
            orange.heightAnchor.constraint(equalToConstant: 20),
            label.leadingAnchor.constraint(equalTo: orange.trailingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            trailing.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
            trailing.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            trailing.widthAnchor.constraint(equalToConstant: 16),
            trailing.heightAnchor.constraint(equalToConstant: 16),
            settingsBtn.trailingAnchor.constraint(equalTo: trailing.leadingAnchor, constant: -12),
            settingsBtn.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            settingsBtn.widthAnchor.constraint(equalToConstant: 16),
            settingsBtn.heightAnchor.constraint(equalToConstant: 16),
            addBtn.trailingAnchor.constraint(equalTo: settingsBtn.leadingAnchor, constant: -12),
            addBtn.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            addBtn.widthAnchor.constraint(equalToConstant: 16),
            addBtn.heightAnchor.constraint(equalToConstant: 16),
        ])
        return v
    }

    @objc private func refreshClicked() {
        onRefresh?()
    }

    @objc private func settingsClicked() {
        onOpenSettings?()
    }

    @objc private func openSinglepeel() {
        guard let url = URL(string: "https://singlepeel.com") else { return }
        if let onOpenURL { onOpenURL(url) } else { NSWorkspace.shared.open(url) }
    }
}

/// Row view that highlights on hover and reports clicks.
@MainActor
final class HoverableRow: NSView {
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeInActiveApp, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard onClick != nil else { return }
        layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.18).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        guard onClick != nil else { return }
        layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.32).cgColor
    }

    override func mouseUp(with event: NSEvent) {
        guard onClick != nil else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        layer?.backgroundColor = inside
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor
        if inside { onClick?() }
    }

    override func resetCursorRects() {
        if onClick != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}
