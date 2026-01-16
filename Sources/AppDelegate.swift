import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var playerView: PlayerView!
    var config: Config!
    var updateTimer: Timer?
    var lastArtworkId: String?
    var statusItem: NSStatusItem?
    var isUpdating = false

    static let playerHeight: CGFloat = 50

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = Config.load()
        Logger.shared.enabled = config.loggingEnabled

        updateDockVisibility(config.showInDock)
        if config.showInMenuBar {
            setupStatusItem()
        }

        let size = NSSize(width: config.windowWidth, height: AppDelegate.playerHeight)
        let frame = NSRect(x: config.windowX, y: config.windowY, width: size.width, height: size.height)

        window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = config.alwaysOnTop ? .floating : .normal
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.delegate = self

        window.minSize = NSSize(width: Config.minWidth, height: AppDelegate.playerHeight)
        window.maxSize = NSSize(width: Config.maxWidth, height: AppDelegate.playerHeight)

        playerView = PlayerView(frame: NSRect(origin: .zero, size: size))
        playerView.colors = DynamicColors(
            baseColor: NSColor(hex: config.backgroundColor),
            opacity: config.backgroundOpacity
        )
        playerView.onFavorite = { [weak self] in
            MediaController.shared.toggleFavorite {
                DispatchQueue.main.async { self?.scheduleUpdate() }
            }
        }
        playerView.onPlayPause = { [weak self] in
            MediaController.shared.playPause {
                DispatchQueue.main.async { self?.scheduleUpdate() }
            }
        }
        playerView.onNext = { [weak self] in
            MediaController.shared.nextTrack {
                DispatchQueue.main.async { self?.scheduleUpdate() }
            }
        }
        playerView.onPrevious = { [weak self] in
            MediaController.shared.previousTrack {
                DispatchQueue.main.async { self?.scheduleUpdate() }
            }
        }
        playerView.onQuit = { [weak self] in self?.confirmQuit() }
        playerView.onSettingsToggle = { [weak self] in self?.toggleSettings() }
        playerView.onOpacityChange = { [weak self] opacity in self?.updateOpacity(opacity) }
        playerView.onColorChange = { [weak self] color in self?.updateBackgroundColor(color) }
        playerView.onLaunchOnLoginChange = { [weak self] enabled in self?.updateLaunchOnLogin(enabled) }
        playerView.onShowInDockChange = { [weak self] enabled in self?.updateShowInDock(enabled) }
        playerView.onShowInMenuBarChange = { [weak self] enabled in self?.updateShowInMenuBar(enabled) }
        playerView.onAlwaysOnTopChange = { [weak self] enabled in self?.updateAlwaysOnTop(enabled) }
        playerView.onLastfmEnabledChange = { [weak self] enabled in self?.updateLastfmEnabled(enabled) }
        playerView.onLastfmConnect = { [weak self] in self?.connectLastfm() }
        playerView.onLastfmDisconnect = { [weak self] in self?.disconnectLastfm() }
        playerView.onAdaptiveColorsChange = { [weak self] enabled in self?.updateAdaptiveColors(enabled) }

        let lastfmConnected = LastFMAuthService.shared.isAuthenticated
        playerView.setupSettingsControls(
            opacity: config.backgroundOpacity,
            color: NSColor(hex: config.backgroundColor),
            launchOnLogin: config.launchOnLogin,
            showInDock: config.showInDock,
            showInMenuBar: config.showInMenuBar,
            alwaysOnTop: config.alwaysOnTop,
            lastfmEnabled: config.lastfmEnabled,
            lastfmConnected: lastfmConnected,
            lastfmUsername: config.lastfmUsername,
            adaptiveColors: config.adaptiveColors
        )
        LastFMScrobbleService.shared.enabled = config.lastfmEnabled

        window.contentView = playerView
        window.makeKeyAndOrderFront(nil)

        updateNowPlaying()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(musicPlayerInfoChanged),
            name: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil
        )

        updateTimer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.updateNowPlaying()
        }
        RunLoop.main.add(updateTimer!, forMode: .common)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove),
            name: NSWindow.didMoveNotification,
            object: window
        )
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let icon = NSApp.applicationIconImage?.copy() as? NSImage
            icon?.size = NSSize(width: 18, height: 18)
            button.image = icon
        }

        let menu = NSMenu()
        let alwaysOnTopItem = NSMenuItem(title: "Always on Top", action: #selector(toggleAlwaysOnTop), keyEquivalent: "")
        alwaysOnTopItem.state = config.alwaysOnTop ? .on : .off
        menu.addItem(alwaysOnTopItem)
        menu.addItem(NSMenuItem.separator())

        let scrobbleItem = NSMenuItem(title: "Scrobbling", action: #selector(toggleScrobbling), keyEquivalent: "")
        scrobbleItem.state = config.lastfmEnabled ? .on : .off
        menu.addItem(scrobbleItem)

        let lastfmConnected = LastFMAuthService.shared.isAuthenticated
        let lastfmItem = NSMenuItem(title: lastfmConnected ? "Last.fm: Connected" : "Last.fm: Not Connected", action: nil, keyEquivalent: "")
        let lastfmSubmenu = NSMenu()
        let connectItem = NSMenuItem(title: "Connect", action: #selector(menuConnectLastfm), keyEquivalent: "")
        connectItem.isHidden = lastfmConnected
        lastfmSubmenu.addItem(connectItem)
        let disconnectItem = NSMenuItem(title: "Disconnect", action: #selector(menuDisconnectLastfm), keyEquivalent: "")
        disconnectItem.isHidden = !lastfmConnected
        lastfmSubmenu.addItem(disconnectItem)
        lastfmItem.submenu = lastfmSubmenu
        menu.addItem(lastfmItem)

        menu.addItem(NSMenuItem.separator())
        let loggingItem = NSMenuItem(title: "Enable Logging", action: #selector(toggleLogging), keyEquivalent: "")
        loggingItem.state = config.loggingEnabled ? .on : .off
        menu.addItem(loggingItem)
        menu.addItem(NSMenuItem(title: "Show Log File", action: #selector(showLogFile), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Reset Settings", action: #selector(resetSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "About Nanomuz", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func toggleAlwaysOnTop() {
        updateAlwaysOnTop(!config.alwaysOnTop)
    }

    @objc func toggleScrobbling() {
        updateLastfmEnabled(!config.lastfmEnabled)
        playerView.updateLastfmEnabled(config.lastfmEnabled)
    }

    @objc func menuConnectLastfm() { connectLastfm() }
    @objc func menuDisconnectLastfm() { disconnectLastfm() }

    @objc func toggleLogging() {
        config.loggingEnabled.toggle()
        config.save()
        Logger.shared.enabled = config.loggingEnabled

        if let menu = statusItem?.menu,
           let item = menu.items.first(where: { $0.title == "Enable Logging" }) {
            item.state = config.loggingEnabled ? .on : .off
        }

        if config.loggingEnabled {
            Logger.shared.logAlways("Logging enabled")
        } else {
            Logger.shared.deleteLogFile()
        }
    }

    @objc func showLogFile() {
        NSWorkspace.shared.selectFile(Logger.logFileURL.path, inFileViewerRootedAtPath: "")
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Nanomuz"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        alert.informativeText = "Version \(version)\n\nA tiny floating music widget for macOS"
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage

        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "GitHub")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if let url = URL(string: "https://github.com/tsyganov-ivan/nanomuz") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc func resetSettings() {
        config = Config.defaultConfig
        config.save()

        updateDockVisibility(config.showInDock)
        updateShowInMenuBar(config.showInMenuBar)
        updateAlwaysOnTop(config.alwaysOnTop)
        Logger.shared.enabled = config.loggingEnabled

        if let menu = statusItem?.menu {
            if let item = menu.items.first(where: { $0.title == "Enable Logging" }) {
                item.state = config.loggingEnabled ? .on : .off
            }
        }

        if config.launchOnLogin {
            LaunchAgent.install()
        } else {
            LaunchAgent.uninstall()
        }

        playerView.colors = DynamicColors(
            baseColor: NSColor(hex: config.backgroundColor),
            opacity: config.backgroundOpacity
        )
        playerView.updateSettingsColors()
        playerView.setNeedsDisplay(playerView.bounds)

        window.setFrameOrigin(NSPoint(x: config.windowX, y: config.windowY))
        var frame = window.frame
        frame.size.width = config.windowWidth
        window.setFrame(frame, display: true)
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    func updateDockVisibility(_ show: Bool) {
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }

    func updateShowInDock(_ enabled: Bool) {
        config.showInDock = enabled
        config.save()
        updateDockVisibility(enabled)
    }

    func updateShowInMenuBar(_ enabled: Bool) {
        config.showInMenuBar = enabled
        config.save()
        if enabled {
            if statusItem == nil {
                setupStatusItem()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }

    func updateAlwaysOnTop(_ enabled: Bool) {
        config.alwaysOnTop = enabled
        config.save()
        window.level = enabled ? .floating : .normal
        if let menu = statusItem?.menu,
           let item = menu.item(withTitle: "Always on Top") {
            item.state = enabled ? .on : .off
        }
    }

    func updateLastfmEnabled(_ enabled: Bool) {
        config.lastfmEnabled = enabled
        config.save()
        LastFMScrobbleService.shared.enabled = enabled
        if !enabled { LastFMScrobbleService.shared.reset() }
        updateLastfmMenuItems()
        Logger.shared.logAlways("Last.fm: Scrobbling \(enabled ? "enabled" : "disabled")")
    }

    func updateAdaptiveColors(_ enabled: Bool) {
        config.adaptiveColors = enabled
        config.save()
        if enabled, let image = playerView.artworkImage {
            applyAdaptiveColor(from: image)
        } else if !enabled {
            playerView.colors = DynamicColors(
                baseColor: NSColor(hex: config.backgroundColor),
                opacity: config.backgroundOpacity
            )
            playerView.updateSettingsColors()
            playerView.needsDisplay = true
        }
    }

    func applyAdaptiveColor(from image: NSImage) {
        guard config.adaptiveColors, let dominantColor = image.dominantColor() else { return }
        playerView.colors = DynamicColors(
            baseColor: dominantColor,
            opacity: config.backgroundOpacity
        )
        playerView.updateSettingsColors()
        playerView.needsDisplay = true
    }

    func connectLastfm() {
        Logger.shared.logAlways("Last.fm: Starting authentication...")
        LastFMAuthService.shared.startAuthentication { [weak self] success, username in
            guard let self = self else { return }
            if success, let username = username {
                self.config = Config.load()
                self.config.lastfmUsername = username
                self.config.save()
                self.playerView.updateLastfmStatus(connected: true, username: username)
                self.updateLastfmMenuItems()
            } else {
                let alert = NSAlert()
                alert.messageText = "Last.fm Authentication Failed"
                alert.informativeText = "Could not authenticate with Last.fm. Please try again."
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    func disconnectLastfm() {
        LastFMAuthService.shared.logout()
        LastFMScrobbleService.shared.reset()
        config.lastfmUsername = ""
        config.save()
        playerView.updateLastfmStatus(connected: false, username: "")
        updateLastfmMenuItems()
    }

    func updateLastfmMenuItems() {
        guard let menu = statusItem?.menu else { return }
        if let item = menu.item(withTitle: "Last.fm: Connected") ?? menu.item(withTitle: "Last.fm: Not Connected") {
            let connected = LastFMAuthService.shared.isAuthenticated
            item.title = connected ? "Last.fm: Connected" : "Last.fm: Not Connected"
            if let submenu = item.submenu {
                submenu.item(withTitle: "Connect")?.isHidden = connected
                submenu.item(withTitle: "Disconnect")?.isHidden = !connected
            }
        }
        if let scrobbleItem = menu.item(withTitle: "Scrobbling") {
            scrobbleItem.state = config.lastfmEnabled ? .on : .off
        }
    }

    func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = "Quit Nanomuz?"
        alert.informativeText = "Are you sure you want to quit?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "No")

        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    func toggleSettings() {
        playerView.isSettingsExpanded.toggle()
        playerView.updateSettingsControlsVisibility()

        let newHeight = playerView.isSettingsExpanded
            ? AppDelegate.playerHeight + PlayerView.settingsPanelHeight
            : AppDelegate.playerHeight

        var frame = window.frame
        let heightDiff = newHeight - frame.height
        frame.size.height = newHeight
        frame.origin.y -= heightDiff

        window.minSize = NSSize(width: Config.minWidth, height: newHeight)
        window.maxSize = NSSize(width: Config.maxWidth, height: newHeight)
        window.setFrame(frame, display: true, animate: true)

        playerView.frame = NSRect(origin: .zero, size: frame.size)
        playerView.updateSettingsControlsLayout()
        playerView.setNeedsDisplay(playerView.bounds)
    }

    func updateOpacity(_ opacity: CGFloat) {
        config.backgroundOpacity = opacity
        config.save()
        playerView.colors = DynamicColors(
            baseColor: playerView.colors.baseColor,
            opacity: opacity
        )
        playerView.updateSettingsColors()
        playerView.setNeedsDisplay(playerView.bounds)
    }

    func updateBackgroundColor(_ color: NSColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        let hex = String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        config.backgroundColor = hex
        config.save()
        playerView.colors = DynamicColors(
            baseColor: color,
            opacity: config.backgroundOpacity
        )
        playerView.updateSettingsColors()
        playerView.setNeedsDisplay(playerView.bounds)
    }

    func updateLaunchOnLogin(_ enabled: Bool) {
        config.launchOnLogin = enabled
        config.save()
        if enabled {
            LaunchAgent.install()
        } else {
            LaunchAgent.uninstall()
        }
    }

    func scheduleUpdate() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateNowPlaying()
        }
    }

    var lastScrobbleInfo: (artist: String, track: String, album: String)?

    func updateNowPlaying() {
        guard !isUpdating else { return }
        isUpdating = true

        MediaController.shared.fetchFromMediaRemote { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isUpdating = false

                let info = MediaController.shared.cachedInfo
                self.playerView.nowPlaying = info

                if let info = info {
                    let currentInfo = (artist: info.artist, track: info.title, album: info.album)
                    let trackChanged = self.lastScrobbleInfo?.artist != currentInfo.artist ||
                                       self.lastScrobbleInfo?.track != currentInfo.track ||
                                       self.lastScrobbleInfo?.album != currentInfo.album
                    if trackChanged {
                        self.lastScrobbleInfo = currentInfo
                        LastFMScrobbleService.shared.trackChanged(artist: info.artist, track: info.title, album: info.album, isPlaying: info.isPlaying, durationSeconds: info.duration)
                    } else {
                        LastFMScrobbleService.shared.playbackStateChanged(isPlaying: info.isPlaying)
                    }
                    LastFMScrobbleService.shared.tick()
                } else if self.lastScrobbleInfo != nil {
                    self.lastScrobbleInfo = nil
                    LastFMScrobbleService.shared.reset()
                }

                let artworkId = info.map { "\($0.title)-\($0.artist)-\($0.album)" }
                if artworkId != self.lastArtworkId {
                    self.lastArtworkId = artworkId
                    self.playerView.artworkImage = nil
                    MediaController.shared.cachedArtwork = nil

                    if info != nil {
                        DispatchQueue.global(qos: .userInitiated).async {
                            MediaController.shared.fetchArtwork()
                            DispatchQueue.main.async { [weak self] in
                                if let data = MediaController.shared.cachedArtwork,
                                   let image = NSImage(data: data) {
                                    self?.playerView.artworkImage = image
                                    self?.applyAdaptiveColor(from: image)
                                    self?.playerView.setNeedsDisplay(self?.playerView.bounds ?? .zero)
                                }
                            }
                        }
                    }
                }

                if let data = MediaController.shared.cachedArtwork, self.playerView.artworkImage == nil {
                    if let image = NSImage(data: data) {
                        self.playerView.artworkImage = image
                        self.applyAdaptiveColor(from: image)
                    }
                }

                self.playerView.setNeedsDisplay(self.playerView.bounds)
            }
        }
    }

    @objc func musicPlayerInfoChanged(_ notification: Notification) {
        updateNowPlaying()
    }

    @objc func windowDidMove(_ notification: Notification) {
        config.windowX = window.frame.origin.x
        config.windowY = window.frame.origin.y
        config.save()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let fixedHeight = playerView.isSettingsExpanded
            ? AppDelegate.playerHeight + PlayerView.settingsPanelHeight
            : AppDelegate.playerHeight
        return NSSize(width: frameSize.width, height: fixedHeight)
    }

    func windowDidResize(_ notification: Notification) {
        config.windowWidth = window.frame.width
        config.save()
        playerView.frame = NSRect(origin: .zero, size: window.frame.size)
        playerView.resetScroll()
        playerView.setNeedsDisplay(playerView.bounds)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
