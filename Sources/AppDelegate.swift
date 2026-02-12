import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var playerView: PlayerView!

    private let settingsManager = SettingsManager()
    private let menuBarManager = MenuBarManager()
    private let windowManager = WindowManager()
    private let nowPlayingController = NowPlayingController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        settingsManager.delegate = self
        menuBarManager.delegate = self
        windowManager.delegate = self
        nowPlayingController.delegate = self

        let config = settingsManager.config
        Logger.shared.enabled = config.loggingEnabled

        updateDockVisibility(config.showInDock)

        if config.showInMenuBar {
            menuBarManager.setup()
            menuBarManager.updateAlwaysOnTopState(config.alwaysOnTop)
            menuBarManager.updateScrobblingState(config.lastfmEnabled)
            menuBarManager.updateLoggingState(config.loggingEnabled)
            menuBarManager.updateLastfmConnectionState(connected: LastFMAuthService.shared.isAuthenticated)
        }

        let size = NSSize(width: config.windowWidth, height: WindowManager.playerHeight)
        playerView = PlayerView(frame: NSRect(origin: .zero, size: size))
        playerView.colors = DynamicColors(
            baseColor: NSColor(hex: config.backgroundColor),
            opacity: config.backgroundOpacity
        )

        setupPlayerViewCallbacks()

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

        windowManager.setup(with: playerView, config: config)
        nowPlayingController.startUpdates()
    }

    private func setupPlayerViewCallbacks() {
        playerView.onFavorite = { [weak self] in
            MediaController.shared.toggleFavorite {
                DispatchQueue.main.async { self?.nowPlayingController.scheduleUpdate() }
            }
        }
        playerView.onPlayPause = { [weak self] in
            MediaController.shared.playPause {
                DispatchQueue.main.async { self?.nowPlayingController.scheduleUpdate() }
            }
        }
        playerView.onNext = { [weak self] in
            MediaController.shared.nextTrack {
                DispatchQueue.main.async { self?.nowPlayingController.scheduleUpdate() }
            }
        }
        playerView.onPrevious = { [weak self] in
            MediaController.shared.previousTrack {
                DispatchQueue.main.async { self?.nowPlayingController.scheduleUpdate() }
            }
        }
        playerView.onQuit = { [weak self] in self?.confirmQuit() }
        playerView.onSettingsToggle = { [weak self] in self?.toggleSettings() }
        playerView.onOpacityChange = { [weak self] opacity in self?.settingsManager.updateOpacity(opacity) }
        playerView.onColorChange = { [weak self] color in self?.settingsManager.updateBackgroundColor(color) }
        playerView.onLaunchOnLoginChange = { [weak self] enabled in self?.settingsManager.updateLaunchOnLogin(enabled) }
        playerView.onShowInDockChange = { [weak self] enabled in self?.settingsManager.updateShowInDock(enabled) }
        playerView.onShowInMenuBarChange = { [weak self] enabled in self?.settingsManager.updateShowInMenuBar(enabled) }
        playerView.onAlwaysOnTopChange = { [weak self] enabled in self?.settingsManager.updateAlwaysOnTop(enabled) }
        playerView.onLastfmEnabledChange = { [weak self] enabled in self?.settingsManager.updateLastfmEnabled(enabled) }
        playerView.onLastfmConnect = { [weak self] in self?.connectLastfm() }
        playerView.onLastfmDisconnect = { [weak self] in self?.disconnectLastfm() }
        playerView.onAdaptiveColorsChange = { [weak self] enabled in self?.settingsManager.updateAdaptiveColors(enabled) }
    }

    private func updateDockVisibility(_ show: Bool) {
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }

    private func toggleSettings() {
        playerView.isSettingsExpanded.toggle()
        playerView.updateSettingsControlsVisibility()
        windowManager.toggleSettingsPanel(isExpanded: playerView.isSettingsExpanded, playerView: playerView)
        playerView.updateSettingsControlsLayout()
        playerView.setNeedsDisplay(playerView.bounds)
    }

    private func confirmQuit() {
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

    private func connectLastfm() {
        Logger.shared.logAlways("Last.fm: Starting authentication...")
        LastFMAuthService.shared.startAuthentication { [weak self] success, username in
            guard let self = self else { return }
            if success, let username = username {
                self.settingsManager.reloadConfig()
                self.settingsManager.saveLastfmUsername(username)
                self.playerView.updateLastfmStatus(connected: true, username: username)
                self.menuBarManager.updateLastfmConnectionState(connected: true)
            } else {
                let alert = NSAlert()
                alert.messageText = "Last.fm Authentication Failed"
                alert.informativeText = "Could not authenticate with Last.fm. Please try again."
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    private func disconnectLastfm() {
        LastFMAuthService.shared.logout()
        LastFMScrobbleService.shared.reset()
        settingsManager.saveLastfmUsername("")
        playerView.updateLastfmStatus(connected: false, username: "")
        menuBarManager.updateLastfmConnectionState(connected: false)
    }

    private func applyAdaptiveColor(from image: NSImage) {
        guard settingsManager.config.adaptiveColors,
              let dominantColor = image.dominantColor() else { return }
        playerView.colors = DynamicColors(
            baseColor: dominantColor,
            opacity: settingsManager.config.backgroundOpacity
        )
        playerView.updateSettingsColors()
        playerView.needsDisplay = true
    }

    private func showAbout() {
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// MARK: - SettingsManagerDelegate

extension AppDelegate: SettingsManagerDelegate {
    func settingsManager(_ manager: SettingsManagerProtocol, didUpdateOpacity opacity: CGFloat) {
        playerView.colors = DynamicColors(
            baseColor: playerView.colors.baseColor,
            opacity: opacity
        )
        playerView.updateSettingsColors()
        playerView.setNeedsDisplay(playerView.bounds)
    }

    func settingsManager(_ manager: SettingsManagerProtocol, didUpdateBackgroundColor color: NSColor) {
        playerView.colors = DynamicColors(
            baseColor: color,
            opacity: settingsManager.config.backgroundOpacity
        )
        playerView.updateSettingsColors()
        playerView.setNeedsDisplay(playerView.bounds)
    }

    func settingsManager(_ manager: SettingsManagerProtocol, didUpdateShowInDock enabled: Bool) {
        updateDockVisibility(enabled)
    }

    func settingsManager(_ manager: SettingsManagerProtocol, didUpdateShowInMenuBar enabled: Bool) {
        if enabled {
            menuBarManager.setup()
            let config = settingsManager.config
            menuBarManager.updateAlwaysOnTopState(config.alwaysOnTop)
            menuBarManager.updateScrobblingState(config.lastfmEnabled)
            menuBarManager.updateLoggingState(config.loggingEnabled)
            menuBarManager.updateLastfmConnectionState(connected: LastFMAuthService.shared.isAuthenticated)
        } else {
            menuBarManager.teardown()
        }
    }

    func settingsManager(_ manager: SettingsManagerProtocol, didUpdateAlwaysOnTop enabled: Bool) {
        windowManager.updateWindowLevel(enabled ? .floating : .normal)
        menuBarManager.updateAlwaysOnTopState(enabled)
    }

    func settingsManager(_ manager: SettingsManagerProtocol, didUpdateLastfmEnabled enabled: Bool) {
        menuBarManager.updateScrobblingState(enabled)
        playerView.updateLastfmEnabled(enabled)
    }

    func settingsManager(_ manager: SettingsManagerProtocol, didUpdateAdaptiveColors enabled: Bool) {
        if enabled, let image = playerView.artworkImage {
            applyAdaptiveColor(from: image)
        } else if !enabled {
            playerView.colors = DynamicColors(
                baseColor: NSColor(hex: settingsManager.config.backgroundColor),
                opacity: settingsManager.config.backgroundOpacity
            )
            playerView.updateSettingsColors()
            playerView.needsDisplay = true
        }
    }

    func settingsManager(_ manager: SettingsManagerProtocol, didUpdateLoggingEnabled enabled: Bool) {
        menuBarManager.updateLoggingState(enabled)
    }

    func settingsManagerDidResetSettings(_ manager: SettingsManagerProtocol) {
        let config = settingsManager.config

        updateDockVisibility(config.showInDock)

        if config.showInMenuBar {
            menuBarManager.setup()
        } else {
            menuBarManager.teardown()
        }

        windowManager.updateWindowLevel(config.alwaysOnTop ? .floating : .normal)
        menuBarManager.updateAlwaysOnTopState(config.alwaysOnTop)
        menuBarManager.updateScrobblingState(config.lastfmEnabled)
        menuBarManager.updateLoggingState(config.loggingEnabled)
        menuBarManager.updateLastfmConnectionState(connected: LastFMAuthService.shared.isAuthenticated)

        playerView.colors = DynamicColors(
            baseColor: NSColor(hex: config.backgroundColor),
            opacity: config.backgroundOpacity
        )
        playerView.updateSettingsColors()
        playerView.setNeedsDisplay(playerView.bounds)

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

        windowManager.setWindowPosition(x: config.windowX, y: config.windowY)
        windowManager.setWindowWidth(config.windowWidth)
    }
}

// MARK: - MenuBarManagerDelegate

extension AppDelegate: MenuBarManagerDelegate {
    func menuBarManagerDidToggleAlwaysOnTop(_ manager: MenuBarManagerProtocol) {
        settingsManager.updateAlwaysOnTop(!settingsManager.config.alwaysOnTop)
    }

    func menuBarManagerDidToggleScrobbling(_ manager: MenuBarManagerProtocol) {
        settingsManager.updateLastfmEnabled(!settingsManager.config.lastfmEnabled)
    }

    func menuBarManagerDidToggleLogging(_ manager: MenuBarManagerProtocol) {
        settingsManager.updateLoggingEnabled(!settingsManager.config.loggingEnabled)
    }

    func menuBarManagerDidRequestConnectLastfm(_ manager: MenuBarManagerProtocol) {
        connectLastfm()
    }

    func menuBarManagerDidRequestDisconnectLastfm(_ manager: MenuBarManagerProtocol) {
        disconnectLastfm()
    }

    func menuBarManagerDidRequestShowLogFile(_ manager: MenuBarManagerProtocol) {
        NSWorkspace.shared.selectFile(Logger.logFileURL.path, inFileViewerRootedAtPath: "")
    }

    func menuBarManagerDidRequestShowAbout(_ manager: MenuBarManagerProtocol) {
        showAbout()
    }

    func menuBarManagerDidRequestResetSettings(_ manager: MenuBarManagerProtocol) {
        settingsManager.resetSettings()
    }

    func menuBarManagerDidRequestQuit(_ manager: MenuBarManagerProtocol) {
        NSApp.terminate(nil)
    }
}

// MARK: - WindowManagerDelegate

extension AppDelegate: WindowManagerDelegate {
    func windowManager(_ manager: WindowManagerProtocol, didMoveWindow frame: NSRect) {
        settingsManager.saveWindowPosition(x: frame.origin.x, y: frame.origin.y)
    }

    func windowManager(_ manager: WindowManagerProtocol, didResizeWindow frame: NSRect) {
        settingsManager.saveWindowWidth(frame.width)
        playerView.frame = NSRect(origin: .zero, size: frame.size)
        playerView.resetScroll()
        playerView.setNeedsDisplay(playerView.bounds)
    }
}

// MARK: - NowPlayingControllerDelegate

extension AppDelegate: NowPlayingControllerDelegate {
    func nowPlayingController(_ controller: NowPlayingControllerProtocol, didUpdateInfo info: NowPlayingInfo?) {
        playerView.nowPlaying = info
        playerView.setNeedsDisplay(playerView.bounds)
    }

    func nowPlayingController(_ controller: NowPlayingControllerProtocol, didUpdateArtwork image: NSImage?) {
        playerView.artworkImage = image
        if let image = image {
            applyAdaptiveColor(from: image)
        }
        playerView.setNeedsDisplay(playerView.bounds)
    }

    func nowPlayingController(_ controller: NowPlayingControllerProtocol, artworkIdChanged newId: String?) {
        playerView.artworkImage = nil
    }
}
