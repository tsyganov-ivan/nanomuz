import AppKit

class SettingsManager: SettingsManagerProtocol {
    private(set) var config: Config
    weak var delegate: SettingsManagerDelegate?

    init() {
        config = Config.load()
    }

    // MARK: - Settings Updates

    func updateOpacity(_ opacity: CGFloat) {
        config.backgroundOpacity = opacity
        config.save()
        delegate?.settingsManager(self, didUpdateOpacity: opacity)
    }

    func updateBackgroundColor(_ color: NSColor) {
        guard let rgbColor = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) else {
            Logger.shared.log("updateBackgroundColor: Failed to convert color to RGB", key: "color_convert_fail")
            delegate?.settingsManager(self, didUpdateBackgroundColor: color)
            return
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let hex = String(format: "%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
        config.backgroundColor = hex
        config.save()
        delegate?.settingsManager(self, didUpdateBackgroundColor: color)
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

    func updateShowInDock(_ enabled: Bool) {
        config.showInDock = enabled
        config.save()
        delegate?.settingsManager(self, didUpdateShowInDock: enabled)
    }

    func updateShowInMenuBar(_ enabled: Bool) {
        config.showInMenuBar = enabled
        config.save()
        delegate?.settingsManager(self, didUpdateShowInMenuBar: enabled)
    }

    func updateAlwaysOnTop(_ enabled: Bool) {
        config.alwaysOnTop = enabled
        config.save()
        delegate?.settingsManager(self, didUpdateAlwaysOnTop: enabled)
    }

    func updateLastfmEnabled(_ enabled: Bool) {
        config.lastfmEnabled = enabled
        config.save()
        LastFMScrobbleService.shared.enabled = enabled
        if !enabled {
            LastFMScrobbleService.shared.reset()
        }
        Logger.shared.logAlways("Last.fm: Scrobbling \(enabled ? "enabled" : "disabled")")
        delegate?.settingsManager(self, didUpdateLastfmEnabled: enabled)
    }

    func updateAdaptiveColors(_ enabled: Bool) {
        config.adaptiveColors = enabled
        config.save()
        delegate?.settingsManager(self, didUpdateAdaptiveColors: enabled)
    }

    func updateLoggingEnabled(_ enabled: Bool) {
        config.loggingEnabled = enabled
        config.save()
        Logger.shared.enabled = enabled
        if enabled {
            Logger.shared.logAlways("Logging enabled")
        } else {
            Logger.shared.deleteLogFile()
        }
        delegate?.settingsManager(self, didUpdateLoggingEnabled: enabled)
    }

    // MARK: - Reset

    func resetSettings() {
        config = Config.defaultConfig
        config.save()

        Logger.shared.enabled = config.loggingEnabled

        if config.launchOnLogin {
            LaunchAgent.install()
        } else {
            LaunchAgent.uninstall()
        }

        delegate?.settingsManagerDidResetSettings(self)
    }

    // MARK: - Window State

    func saveWindowPosition(x: CGFloat, y: CGFloat) {
        config.windowX = x
        config.windowY = y
        config.save()
    }

    func saveWindowWidth(_ width: CGFloat) {
        config.windowWidth = width
        config.save()
    }

    // MARK: - Configuration Persistence

    func saveLastfmUsername(_ username: String) {
        config.lastfmUsername = username
        config.save()
    }

    func reloadConfig() {
        config = Config.load()
    }
}
