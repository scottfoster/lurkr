import Cocoa

@MainActor
final class AboutWindowController: NSWindowController {
    var onOpenURL: ((URL) -> Void)?

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "About Lurkr"
        win.isReleasedWhenClosed = false
        win.center()
        super.init(window: win)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 18, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])

        let iconView = NSImageView()
        let img = NSApp.applicationIconImage
        img?.size = NSSize(width: 64, height: 64)
        iconView.image = img
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 64).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 64).isActive = true
        stack.addArrangedSubview(iconView)

        let title = NSTextField(labelWithString: "Lurkr")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        stack.addArrangedSubview(title)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let versionLabel = NSTextField(labelWithString: "Version \(version) (build \(build))")
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(versionLabel)

        stack.addArrangedSubview(makeSpacer(10))

        stack.addArrangedSubview(makeLinkButton(title: "Made by Singlepeel",
                                                 urlString: "https://singlepeel.com"))
        stack.addArrangedSubview(makeLinkButton(title: "Powered by decapi.me",
                                                 urlString: "https://decapi.me"))

        stack.addArrangedSubview(makeSpacer(12))

        let quitBtn = NSButton(title: "Quit Lurkr",
                               target: NSApp,
                               action: #selector(NSApplication.terminate(_:)))
        quitBtn.bezelStyle = .rounded
        stack.addArrangedSubview(quitBtn)
    }

    private func makeLinkButton(title: String, urlString: String) -> NSButton {
        let btn = NSButton(title: title,
                           target: self,
                           action: #selector(linkClicked(_:)))
        btn.bezelStyle = .accessoryBarAction
        btn.isBordered = false
        btn.identifier = NSUserInterfaceItemIdentifier(urlString)
        btn.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
        )
        return btn
    }

    @objc private func linkClicked(_ sender: NSButton) {
        guard let urlStr = sender.identifier?.rawValue,
              let url = URL(string: urlStr) else { return }
        onOpenURL?(url)
    }

    private func makeSpacer(_ height: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        return v
    }

    func showAndFocus() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
