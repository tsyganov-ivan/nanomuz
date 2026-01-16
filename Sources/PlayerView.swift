import AppKit

class PlayerView: NSView {
    var nowPlaying: NowPlayingInfo?
    var artworkImage: NSImage?
    var colors: DynamicColors = DynamicColors(baseColor: NSColor(hex: "1E1E1E"), opacity: 0.95)
    var isSettingsExpanded: Bool = false
    var onFavorite: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onQuit: (() -> Void)?
    var onSettingsToggle: (() -> Void)?
    var onOpacityChange: ((CGFloat) -> Void)?
    var onColorChange: ((NSColor) -> Void)?
    var onLaunchOnLoginChange: ((Bool) -> Void)?
    var onShowInDockChange: ((Bool) -> Void)?
    var onShowInMenuBarChange: ((Bool) -> Void)?
    var onAlwaysOnTopChange: ((Bool) -> Void)?
    var onLastfmEnabledChange: ((Bool) -> Void)?
    var onLastfmConnect: (() -> Void)?
    var onLastfmDisconnect: (() -> Void)?
    var onAdaptiveColorsChange: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var hoveredButton: String?

    private var opacitySlider: NSSlider?
    private var colorWell: NSColorWell?
    private var opacityLabel: NSTextField?
    private var launchOnLoginCheckbox: NSButton?
    private var launchOnLoginLabel: NSTextField?
    private var showInDockCheckbox: NSButton?
    private var showInDockLabel: NSTextField?
    private var showInMenuBarCheckbox: NSButton?
    private var showInMenuBarLabel: NSTextField?
    private var alwaysOnTopCheckbox: NSButton?
    private var alwaysOnTopLabel: NSTextField?
    private var lastfmHeaderLabel: NSTextField?
    private var lastfmEnabledCheckbox: NSButton?
    private var lastfmEnabledLabel: NSTextField?
    private var lastfmConnectButton: NSButton?
    private var adaptiveColorsCheckbox: NSButton?
    private var adaptiveColorsLabel: NSTextField?
    private var separator1: NSBox?
    private var separator2: NSBox?

    private var scrollOffset: CGFloat = 0
    private var scrollTimer: Timer?
    private var scrollPauseCounter: Int = 0
    private let scrollSpeed: CGFloat = 0.5
    private let pauseFrames: Int = 60

    static let settingsPanelHeight: CGFloat = 160

    var lastfmUsername: String = ""
    var lastfmConnected: Bool = false

    override var isFlipped: Bool { true }

    func setupSettingsControls(opacity: CGFloat, color: NSColor, launchOnLogin: Bool, showInDock: Bool, showInMenuBar: Bool, alwaysOnTop: Bool, lastfmEnabled: Bool = true, lastfmConnected: Bool = false, lastfmUsername: String = "", adaptiveColors: Bool = true) {
        self.lastfmUsername = lastfmUsername
        self.lastfmConnected = lastfmConnected
        opacitySlider = NSSlider(value: Double(opacity), minValue: 0.3, maxValue: 1.0, target: self, action: #selector(opacityChanged))
        opacitySlider?.isContinuous = true
        addSubview(opacitySlider!)

        colorWell = NSColorWell(frame: .zero)
        colorWell?.color = color
        colorWell?.target = self
        colorWell?.action = #selector(colorChanged)
        addSubview(colorWell!)

        opacityLabel = NSTextField(labelWithString: "Opacity")
        opacityLabel?.font = NSFont.systemFont(ofSize: 11)
        opacityLabel?.textColor = colors.textSecondary
        addSubview(opacityLabel!)

        launchOnLoginCheckbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(launchOnLoginChanged))
        launchOnLoginCheckbox?.state = launchOnLogin ? .on : .off
        addSubview(launchOnLoginCheckbox!)
        launchOnLoginLabel = NSTextField(labelWithString: "Launch at login")
        launchOnLoginLabel?.font = NSFont.systemFont(ofSize: 11)
        addSubview(launchOnLoginLabel!)

        showInDockCheckbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(showInDockChanged))
        showInDockCheckbox?.state = showInDock ? .on : .off
        addSubview(showInDockCheckbox!)
        showInDockLabel = NSTextField(labelWithString: "Dock")
        showInDockLabel?.font = NSFont.systemFont(ofSize: 11)
        addSubview(showInDockLabel!)

        showInMenuBarCheckbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(showInMenuBarChanged))
        showInMenuBarCheckbox?.state = showInMenuBar ? .on : .off
        addSubview(showInMenuBarCheckbox!)
        showInMenuBarLabel = NSTextField(labelWithString: "Menu Bar")
        showInMenuBarLabel?.font = NSFont.systemFont(ofSize: 11)
        addSubview(showInMenuBarLabel!)

        alwaysOnTopCheckbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(alwaysOnTopChanged))
        alwaysOnTopCheckbox?.state = alwaysOnTop ? .on : .off
        addSubview(alwaysOnTopCheckbox!)
        alwaysOnTopLabel = NSTextField(labelWithString: "Always on top")
        alwaysOnTopLabel?.font = NSFont.systemFont(ofSize: 11)
        addSubview(alwaysOnTopLabel!)

        lastfmEnabledCheckbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(lastfmEnabledChanged))
        lastfmEnabledCheckbox?.state = lastfmEnabled ? .on : .off
        addSubview(lastfmEnabledCheckbox!)
        lastfmEnabledLabel = NSTextField(labelWithString: "Scrobble")
        lastfmEnabledLabel?.font = NSFont.systemFont(ofSize: 11)
        addSubview(lastfmEnabledLabel!)

        lastfmHeaderLabel = NSTextField(labelWithString: lastfmConnected ? "Last.FM as \(lastfmUsername)" : "Last.FM")
        lastfmHeaderLabel?.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        addSubview(lastfmHeaderLabel!)

        lastfmConnectButton = NSButton(title: lastfmConnected ? "Disconnect" : "Connect", target: self, action: #selector(lastfmConnectClicked))
        lastfmConnectButton?.bezelStyle = .rounded
        lastfmConnectButton?.font = NSFont.systemFont(ofSize: 11)
        lastfmConnectButton?.isBordered = false
        lastfmConnectButton?.wantsLayer = true
        addSubview(lastfmConnectButton!)

        adaptiveColorsCheckbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(adaptiveColorsChanged))
        adaptiveColorsCheckbox?.state = adaptiveColors ? .on : .off
        addSubview(adaptiveColorsCheckbox!)
        adaptiveColorsLabel = NSTextField(labelWithString: "Adaptive")
        adaptiveColorsLabel?.font = NSFont.systemFont(ofSize: 11)
        addSubview(adaptiveColorsLabel!)

        colorWell?.isEnabled = !adaptiveColors

        separator1 = NSBox()
        separator1?.boxType = .custom
        separator1?.borderWidth = 0
        addSubview(separator1!)
        separator2 = NSBox()
        separator2?.boxType = .custom
        separator2?.borderWidth = 0
        addSubview(separator2!)

        updateSettingsColors()
        updateSettingsControlsVisibility()
    }

    func updateLastfmStatus(connected: Bool, username: String) {
        self.lastfmConnected = connected
        self.lastfmUsername = username
        lastfmHeaderLabel?.stringValue = connected ? "Last.FM as \(username)" : "Last.FM"
        let title = connected ? "Disconnect" : "Connect"
        lastfmConnectButton?.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: colors.textSecondary,
            .font: NSFont.systemFont(ofSize: 11)
        ])
        setNeedsDisplay(bounds)
    }

    func updateLastfmEnabled(_ enabled: Bool) {
        lastfmEnabledCheckbox?.state = enabled ? .on : .off
    }

    func updateSettingsControlsVisibility() {
        let hidden = !isSettingsExpanded
        opacitySlider?.isHidden = hidden
        colorWell?.isHidden = hidden
        opacityLabel?.isHidden = hidden
        launchOnLoginCheckbox?.isHidden = hidden
        launchOnLoginLabel?.isHidden = hidden
        showInDockCheckbox?.isHidden = hidden
        showInDockLabel?.isHidden = hidden
        showInMenuBarCheckbox?.isHidden = hidden
        showInMenuBarLabel?.isHidden = hidden
        alwaysOnTopCheckbox?.isHidden = hidden
        alwaysOnTopLabel?.isHidden = hidden
        lastfmEnabledCheckbox?.isHidden = hidden
        lastfmEnabledLabel?.isHidden = hidden
        lastfmHeaderLabel?.isHidden = hidden
        lastfmConnectButton?.isHidden = hidden
        adaptiveColorsCheckbox?.isHidden = hidden
        adaptiveColorsLabel?.isHidden = hidden
        separator1?.isHidden = hidden
        separator2?.isHidden = hidden
    }

    func updateSettingsControlsLayout() {
        guard isSettingsExpanded else { return }
        let padding: CGFloat = 12
        let checkboxSize: CGFloat = 16
        let gap: CGFloat = 4
        let labelHeight: CGFloat = 16

        let baseY = bounds.height - PlayerView.settingsPanelHeight
        let row1Y = baseY + 16
        let sep1Y = baseY + 38
        let row2Y = baseY + 50
        let row2bY = baseY + 70
        let sep2Y = baseY + 92
        let row3Y = baseY + 104
        let row3bY = baseY + 128

        opacityLabel?.frame = NSRect(x: padding, y: row1Y, width: 52, height: labelHeight)
        opacitySlider?.frame = NSRect(x: 64, y: row1Y, width: 100, height: labelHeight)
        colorWell?.frame = NSRect(x: 172, y: row1Y - 4, width: 44, height: 24)
        let adaptiveX: CGFloat = 224
        adaptiveColorsCheckbox?.frame = NSRect(x: adaptiveX, y: row1Y, width: checkboxSize, height: checkboxSize)
        adaptiveColorsLabel?.frame = NSRect(x: adaptiveX + checkboxSize + gap, y: row1Y, width: 70, height: labelHeight)

        separator1?.frame = NSRect(x: padding, y: sep1Y, width: bounds.width - padding * 2, height: 1)

        let col1: CGFloat = padding
        let col2: CGFloat = 200

        alwaysOnTopCheckbox?.frame = NSRect(x: col1, y: row2Y, width: checkboxSize, height: checkboxSize)
        alwaysOnTopLabel?.frame = NSRect(x: col1 + checkboxSize + gap, y: row2Y, width: 80, height: labelHeight)
        showInDockCheckbox?.frame = NSRect(x: col2, y: row2Y, width: checkboxSize, height: checkboxSize)
        showInDockLabel?.frame = NSRect(x: col2 + checkboxSize + gap, y: row2Y, width: 35, height: labelHeight)
        showInMenuBarCheckbox?.frame = NSRect(x: col1, y: row2bY, width: checkboxSize, height: checkboxSize)
        showInMenuBarLabel?.frame = NSRect(x: col1 + checkboxSize + gap, y: row2bY, width: 60, height: labelHeight)
        launchOnLoginCheckbox?.frame = NSRect(x: col2, y: row2bY, width: checkboxSize, height: checkboxSize)
        launchOnLoginLabel?.frame = NSRect(x: col2 + checkboxSize + gap, y: row2bY, width: 90, height: labelHeight)

        separator2?.frame = NSRect(x: padding, y: sep2Y, width: bounds.width - padding * 2, height: 1)

        lastfmHeaderLabel?.frame = NSRect(x: padding, y: row3Y, width: bounds.width - padding * 2, height: labelHeight)
        lastfmConnectButton?.frame = NSRect(x: padding, y: row3bY - 2, width: 80, height: 22)
        lastfmEnabledCheckbox?.frame = NSRect(x: col2, y: row3bY, width: checkboxSize, height: checkboxSize)
        lastfmEnabledLabel?.frame = NSRect(x: col2 + checkboxSize + gap, y: row3bY, width: 60, height: labelHeight)
    }

    func updateSettingsColors() {
        opacityLabel?.textColor = colors.textSecondary
        launchOnLoginLabel?.textColor = colors.textSecondary
        showInDockLabel?.textColor = colors.textSecondary
        showInMenuBarLabel?.textColor = colors.textSecondary
        alwaysOnTopLabel?.textColor = colors.textSecondary
        launchOnLoginCheckbox?.contentTintColor = colors.textSecondary
        showInDockCheckbox?.contentTintColor = colors.textSecondary
        showInMenuBarCheckbox?.contentTintColor = colors.textSecondary
        alwaysOnTopCheckbox?.contentTintColor = colors.textSecondary
        lastfmHeaderLabel?.textColor = colors.textSecondary
        if let button = lastfmConnectButton {
            let title = button.title
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .foregroundColor: colors.textSecondary,
                .font: NSFont.systemFont(ofSize: 11)
            ])
            button.layer?.backgroundColor = colors.buttonBackground.cgColor
            button.layer?.cornerRadius = 5
        }
        lastfmEnabledLabel?.textColor = colors.textSecondary
        lastfmEnabledCheckbox?.contentTintColor = colors.textSecondary
        adaptiveColorsLabel?.textColor = colors.textSecondary
        adaptiveColorsCheckbox?.contentTintColor = colors.text
        separator1?.fillColor = colors.buttonBackground
        separator2?.fillColor = colors.buttonBackground
    }

    @objc private func opacityChanged() {
        onOpacityChange?(CGFloat(opacitySlider?.doubleValue ?? 0.95))
    }

    @objc private func colorChanged() {
        if let color = colorWell?.color {
            onColorChange?(color)
        }
    }

    @objc private func launchOnLoginChanged() {
        onLaunchOnLoginChange?(launchOnLoginCheckbox?.state == .on)
    }

    @objc private func showInDockChanged() {
        onShowInDockChange?(showInDockCheckbox?.state == .on)
    }

    @objc private func showInMenuBarChanged() {
        onShowInMenuBarChange?(showInMenuBarCheckbox?.state == .on)
    }

    @objc private func alwaysOnTopChanged() {
        onAlwaysOnTopChange?(alwaysOnTopCheckbox?.state == .on)
    }

    @objc private func lastfmEnabledChanged() {
        onLastfmEnabledChange?(lastfmEnabledCheckbox?.state == .on)
    }

    @objc private func lastfmConnectClicked() {
        if lastfmConnected { onLastfmDisconnect?() } else { onLastfmConnect?() }
    }

    @objc private func adaptiveColorsChanged() {
        let enabled = adaptiveColorsCheckbox?.state == .on
        colorWell?.isEnabled = !enabled
        onAdaptiveColorsChange?(enabled)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea {
            removeTrackingArea(ta)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self
        )
        addTrackingArea(trackingArea!)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let path = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        colors.background.setFill()
        path.fill()

        drawCompact()
    }

    private func drawCompact() {
        let buttonSize: CGFloat = 32
        let playerHeight: CGFloat = 50
        let buttonY: CGFloat = (playerHeight - buttonSize) / 2
        var x: CGFloat = 12

        drawButton(rect: NSRect(x: x, y: buttonY, width: buttonSize, height: buttonSize), symbol: "⏮", id: "prev")
        x += buttonSize + 4

        let playSymbol = nowPlaying?.isPlaying == true ? "⏸" : "▶"
        drawButton(rect: NSRect(x: x, y: buttonY, width: buttonSize + 4, height: buttonSize), symbol: playSymbol, id: "play")
        x += buttonSize + 8

        drawButton(rect: NSRect(x: x, y: buttonY, width: buttonSize, height: buttonSize), symbol: "⏭", id: "next")
        x += buttonSize + 12

        let artSize: CGFloat = 32
        let artY = (playerHeight - artSize) / 2
        drawArtwork(rect: NSRect(x: x, y: artY, width: artSize, height: artSize), rounding: 6)
        x += artSize + 10

        let infoWidth = bounds.width - x - 100
        if let np = nowPlaying {
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: colors.text
            ]
            let artistAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: colors.textSecondary
            ]

            let titleWidth = NSAttributedString(string: np.title, attributes: titleAttrs).size().width
            let artistWidth = NSAttributedString(string: np.artist, attributes: artistAttrs).size().width
            let titleNeedsScroll = titleWidth > infoWidth
            let artistNeedsScroll = artistWidth > infoWidth

            if titleNeedsScroll || artistNeedsScroll {
                startScrollTimer()
                let gap: CGFloat = 50

                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: NSRect(x: x, y: buttonY - 3, width: infoWidth, height: 36)).addClip()

                if titleNeedsScroll {
                    let maxTitleScroll = titleWidth + gap
                    let titleOffset = scrollOffset.truncatingRemainder(dividingBy: maxTitleScroll)
                    let drawTitleX = x - titleOffset
                    NSAttributedString(string: np.title, attributes: titleAttrs).draw(at: NSPoint(x: drawTitleX, y: buttonY - 1))
                    NSAttributedString(string: np.title, attributes: titleAttrs).draw(at: NSPoint(x: drawTitleX + titleWidth + gap, y: buttonY - 1))
                } else {
                    NSAttributedString(string: np.title, attributes: titleAttrs).draw(at: NSPoint(x: x, y: buttonY - 1))
                }

                if artistNeedsScroll {
                    let maxArtistScroll = artistWidth + gap
                    let artistOffset = scrollOffset.truncatingRemainder(dividingBy: maxArtistScroll)
                    let drawArtistX = x - artistOffset
                    NSAttributedString(string: np.artist, attributes: artistAttrs).draw(at: NSPoint(x: drawArtistX, y: buttonY + 15))
                    NSAttributedString(string: np.artist, attributes: artistAttrs).draw(at: NSPoint(x: drawArtistX + artistWidth + gap, y: buttonY + 15))
                } else {
                    NSAttributedString(string: np.artist, attributes: artistAttrs).draw(at: NSPoint(x: x, y: buttonY + 15))
                }

                NSGraphicsContext.restoreGraphicsState()
            } else {
                resetScroll()
                NSAttributedString(string: np.title, attributes: titleAttrs).draw(at: NSPoint(x: x, y: buttonY - 1))
                NSAttributedString(string: np.artist, attributes: artistAttrs).draw(at: NSPoint(x: x, y: buttonY + 15))
            }
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: colors.textTertiary
            ]
            "Not Playing".draw(at: NSPoint(x: x, y: buttonY + 6), withAttributes: attrs)
        }

        let settingsSymbol = isSettingsExpanded ? "▼" : "⚙"
        drawButton(rect: NSRect(x: bounds.width - 96, y: buttonY, width: 28, height: buttonSize), symbol: settingsSymbol, id: "settings")

        let favSymbol = nowPlaying?.isFavorited == true ? "♥" : "♡"
        drawButton(rect: NSRect(x: bounds.width - 64, y: buttonY, width: 28, height: buttonSize), symbol: favSymbol, id: "fav")

        drawButton(rect: NSRect(x: bounds.width - 32, y: buttonY, width: 24, height: buttonSize), symbol: "✕", id: "quit")

        if isSettingsExpanded {
            let dividerY: CGFloat = 50
            colors.buttonBackground.setFill()
            NSRect(x: 12, y: dividerY, width: bounds.width - 24, height: 1).fill()
        }
    }

    private func drawButton(rect: NSRect, symbol: String, id: String) {
        let isHovered = hoveredButton == id
        let bgColor = isHovered ? colors.buttonBackgroundHover : colors.buttonBackground

        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        bgColor.setFill()
        path.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: colors.text
        ]
        let size = symbol.size(withAttributes: attrs)
        let point = NSPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )
        symbol.draw(at: point, withAttributes: attrs)
    }

    private func drawArtwork(rect: NSRect, rounding: CGFloat) {
        let path = NSBezierPath(roundedRect: rect, xRadius: rounding, yRadius: rounding)

        if let image = artworkImage {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            colors.buttonBackground.setFill()
            path.fill()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: rect.width * 0.35),
                .foregroundColor: colors.textTertiary
            ]
            let symbol = "♪"
            let size = symbol.size(withAttributes: attrs)
            symbol.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
        }
    }

    func startScrollTimer() {
        guard scrollTimer == nil else { return }
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.scrollPauseCounter > 0 {
                self.scrollPauseCounter -= 1
            } else {
                self.scrollOffset += self.scrollSpeed
            }
            self.needsDisplay = true
        }
    }

    func resetScroll() {
        scrollTimer?.invalidate()
        scrollTimer = nil
        scrollOffset = 0
        scrollPauseCounter = pauseFrames
    }

    private func truncateString(_ string: String, width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let attributed = NSAttributedString(string: string, attributes: attributes)
        if attributed.size().width <= width {
            return attributed
        }
        var truncated = string
        while truncated.count > 0 {
            truncated.removeLast()
            let test = NSAttributedString(string: truncated + "…", attributes: attributes)
            if test.size().width <= width {
                return test
            }
        }
        return NSAttributedString(string: "…", attributes: attributes)
    }

    private func buttonAt(point: NSPoint) -> String? {
        let buttonSize: CGFloat = 32
        let playerHeight: CGFloat = 50
        let buttonY: CGFloat = (playerHeight - buttonSize) / 2
        var x: CGFloat = 12

        if NSRect(x: x, y: buttonY, width: buttonSize, height: buttonSize).contains(point) { return "prev" }
        x += buttonSize + 4
        if NSRect(x: x, y: buttonY, width: buttonSize + 4, height: buttonSize).contains(point) { return "play" }
        x += buttonSize + 8
        if NSRect(x: x, y: buttonY, width: buttonSize, height: buttonSize).contains(point) { return "next" }
        if NSRect(x: bounds.width - 96, y: buttonY, width: 28, height: buttonSize).contains(point) { return "settings" }
        if NSRect(x: bounds.width - 64, y: buttonY, width: 28, height: buttonSize).contains(point) { return "fav" }
        if NSRect(x: bounds.width - 32, y: buttonY, width: 24, height: buttonSize).contains(point) { return "quit" }

        return nil
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let newHovered = buttonAt(point: point)
        if newHovered != hoveredButton {
            hoveredButton = newHovered
            NSCursor.pointingHand.set()
            needsDisplay = true
        }
        if hoveredButton == nil {
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredButton = nil
        NSCursor.arrow.set()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let playerHeight: CGFloat = 50

        if point.y < playerHeight, let button = buttonAt(point: point) {
            switch button {
            case "prev": onPrevious?()
            case "play": onPlayPause?()
            case "next": onNext?()
            case "settings": onSettingsToggle?()
            case "fav": onFavorite?()
            case "quit": onQuit?()
            default: break
            }
            return
        }

        if let hitView = hitTest(point),
           (hitView is NSButton || hitView is NSSlider || hitView is NSColorWell) {
            super.mouseDown(with: event)
            return
        }

        window?.performDrag(with: event)
    }
}
