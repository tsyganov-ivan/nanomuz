import AppKit

// MARK: - Settings Manager

protocol SettingsManagerProtocol: AnyObject {
    var config: Config { get }

    func updateOpacity(_ opacity: CGFloat)
    func updateBackgroundColor(_ color: NSColor)
    func updateLaunchOnLogin(_ enabled: Bool)
    func updateShowInDock(_ enabled: Bool)
    func updateShowInMenuBar(_ enabled: Bool)
    func updateAlwaysOnTop(_ enabled: Bool)
    func updateLastfmEnabled(_ enabled: Bool)
    func updateAdaptiveColors(_ enabled: Bool)
    func updateLoggingEnabled(_ enabled: Bool)
    func resetSettings()
    func saveWindowPosition(x: CGFloat, y: CGFloat)
    func saveWindowWidth(_ width: CGFloat)
    func saveLastfmUsername(_ username: String)
    func reloadConfig()
}

protocol SettingsManagerDelegate: AnyObject {
    func settingsManager(_ manager: SettingsManagerProtocol, didUpdateOpacity opacity: CGFloat)
    func settingsManager(_ manager: SettingsManagerProtocol, didUpdateBackgroundColor color: NSColor)
    func settingsManager(_ manager: SettingsManagerProtocol, didUpdateShowInDock enabled: Bool)
    func settingsManager(_ manager: SettingsManagerProtocol, didUpdateShowInMenuBar enabled: Bool)
    func settingsManager(_ manager: SettingsManagerProtocol, didUpdateAlwaysOnTop enabled: Bool)
    func settingsManager(_ manager: SettingsManagerProtocol, didUpdateLastfmEnabled enabled: Bool)
    func settingsManager(_ manager: SettingsManagerProtocol, didUpdateAdaptiveColors enabled: Bool)
    func settingsManager(_ manager: SettingsManagerProtocol, didUpdateLoggingEnabled enabled: Bool)
    func settingsManagerDidResetSettings(_ manager: SettingsManagerProtocol)
}

// MARK: - Menu Bar Manager

protocol MenuBarManagerProtocol: AnyObject {
    var statusItem: NSStatusItem? { get }

    func setup()
    func teardown()
    func updateAlwaysOnTopState(_ enabled: Bool)
    func updateScrobblingState(_ enabled: Bool)
    func updateLoggingState(_ enabled: Bool)
    func updateLastfmConnectionState(connected: Bool)
}

protocol MenuBarManagerDelegate: AnyObject {
    func menuBarManagerDidToggleAlwaysOnTop(_ manager: MenuBarManagerProtocol)
    func menuBarManagerDidToggleScrobbling(_ manager: MenuBarManagerProtocol)
    func menuBarManagerDidToggleLogging(_ manager: MenuBarManagerProtocol)
    func menuBarManagerDidRequestConnectLastfm(_ manager: MenuBarManagerProtocol)
    func menuBarManagerDidRequestDisconnectLastfm(_ manager: MenuBarManagerProtocol)
    func menuBarManagerDidRequestShowLogFile(_ manager: MenuBarManagerProtocol)
    func menuBarManagerDidRequestShowAbout(_ manager: MenuBarManagerProtocol)
    func menuBarManagerDidRequestResetSettings(_ manager: MenuBarManagerProtocol)
    func menuBarManagerDidRequestQuit(_ manager: MenuBarManagerProtocol)
}

// MARK: - Window Manager

protocol WindowManagerProtocol: AnyObject {
    var window: NSWindow! { get }

    func setup(with playerView: PlayerView, config: Config)
    func toggleSettingsPanel(isExpanded: Bool, playerView: PlayerView)
    func updateWindowLevel(_ level: NSWindow.Level)
    func setWindowPosition(x: CGFloat, y: CGFloat)
    func setWindowWidth(_ width: CGFloat)
}

protocol WindowManagerDelegate: AnyObject {
    func windowManager(_ manager: WindowManagerProtocol, didMoveWindow frame: NSRect)
    func windowManager(_ manager: WindowManagerProtocol, didResizeWindow frame: NSRect)
}

// MARK: - Now Playing Controller

protocol NowPlayingControllerProtocol: AnyObject {
    var lastArtworkId: String? { get }
    var isUpdating: Bool { get }

    func startUpdates()
    func stopUpdates()
    func scheduleUpdate()
    func updateNowPlaying()
}

protocol NowPlayingControllerDelegate: AnyObject {
    func nowPlayingController(_ controller: NowPlayingControllerProtocol, didUpdateInfo info: NowPlayingInfo?)
    func nowPlayingController(_ controller: NowPlayingControllerProtocol, didUpdateArtwork image: NSImage?)
    func nowPlayingController(_ controller: NowPlayingControllerProtocol, artworkIdChanged newId: String?)
}
