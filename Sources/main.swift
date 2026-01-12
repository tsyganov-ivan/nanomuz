import AppKit
import Foundation

// MARK: - Logger

class Logger {
    static let shared = Logger()
    var enabled = false

    private var lastMessages: [String: Date] = [:]
    private let dedupeInterval: TimeInterval = 5.0
    private let maxEntries = 100
    private var fileHandle: FileHandle?

    static var logFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Nanomuz")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("nanomuz.log")
    }

    private init() {}

    func log(_ message: String, key: String? = nil) {
        guard enabled else { return }

        let dedupeKey = key ?? message
        let now = Date()

        if let lastTime = lastMessages[dedupeKey],
           now.timeIntervalSince(lastTime) < dedupeInterval {
            return
        }

        lastMessages[dedupeKey] = now
        cleanupIfNeeded()

        write(message)
    }

    func logAlways(_ message: String) {
        guard enabled else { return }
        write(message)
    }

    private func write(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        if fileHandle == nil {
            FileManager.default.createFile(atPath: Self.logFileURL.path, contents: nil)
            fileHandle = try? FileHandle(forWritingTo: Self.logFileURL)
            fileHandle?.seekToEndOfFile()
        }

        if let data = line.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }

    private func cleanupIfNeeded() {
        guard lastMessages.count > maxEntries else { return }
        let cutoff = Date().addingTimeInterval(-dedupeInterval * 2)
        lastMessages = lastMessages.filter { $0.value > cutoff }
    }

    func deleteLogFile() {
        fileHandle?.closeFile()
        fileHandle = nil
        try? FileManager.default.removeItem(at: Self.logFileURL)
    }
}

// MARK: - Media Controller

struct NowPlayingInfo {
    let title: String
    let artist: String
    let album: String
    let isPlaying: Bool
    let artworkUrl: String?
    var isFavorited: Bool
}

class MediaController {
    static let shared = MediaController()

    var cachedArtwork: Data?
    var cachedInfo: NowPlayingInfo?

    private let scriptQueue = DispatchQueue(label: "com.nanomuz.scripts", qos: .userInitiated)

    private init() {}

    // JXA script for track info (MRNowPlayingRequest - works on macOS 15.4+)
    private let jxaScript = """
    ObjC.import('AppKit');
    var bundle = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework');
    bundle.load;
    var MRNowPlayingRequest = $.NSClassFromString('MRNowPlayingRequest');
    var item = MRNowPlayingRequest.localNowPlayingItem;
    if (!item) { JSON.stringify(null); }
    else {
        var info = item.nowPlayingInfo;
        var result = {};
        var title = info.valueForKey('kMRMediaRemoteNowPlayingInfoTitle');
        if (title && !title.isNil()) result.title = ObjC.unwrap(title);
        var artist = info.valueForKey('kMRMediaRemoteNowPlayingInfoArtist');
        if (artist && !artist.isNil()) result.artist = ObjC.unwrap(artist);
        var album = info.valueForKey('kMRMediaRemoteNowPlayingInfoAlbum');
        if (album && !album.isNil()) result.album = ObjC.unwrap(album);
        var rate = info.valueForKey('kMRMediaRemoteNowPlayingInfoPlaybackRate');
        if (rate && !rate.isNil()) result.playbackRate = ObjC.unwrap(rate);
        var artworkId = info.valueForKey('kMRMediaRemoteNowPlayingInfoArtworkIdentifier');
        if (artworkId && !artworkId.isNil()) result.artworkId = ObjC.unwrap(artworkId);
        JSON.stringify(result);
    }
    """

    func fetchFromMediaRemote(completion: @escaping () -> Void) {
        runJXAAsync(jxaScript) { [weak self] jsonStr in
            guard let self = self else {
                completion()
                return
            }

            guard let jsonStr = jsonStr,
                  !jsonStr.isEmpty,
                  jsonStr != "null" else {
                Logger.shared.log("MediaRemote: No data from JXA", key: "no_jxa_data")
                self.cachedInfo = nil
                self.cachedArtwork = nil
                completion()
                return
            }

            guard let data = jsonStr.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let title = dict["title"] as? String else {
                Logger.shared.log("MediaRemote: Failed to parse JSON: \(jsonStr.prefix(100))", key: "json_parse_error")
                self.cachedInfo = nil
                self.cachedArtwork = nil
                completion()
                return
            }

            let oldTitle = self.cachedInfo?.title
            let artist = dict["artist"] as? String ?? ""
            let artworkUrl = dict["artworkId"] as? String

            self.isFavoritedAsync { isFav in
                self.cachedInfo = NowPlayingInfo(
                    title: title,
                    artist: artist,
                    album: dict["album"] as? String ?? "",
                    isPlaying: (dict["playbackRate"] as? Double ?? 0) > 0,
                    artworkUrl: artworkUrl,
                    isFavorited: isFav
                )

                if oldTitle != title {
                    Logger.shared.logAlways("Track changed: \(artist) - \(title)")
                    if let url = artworkUrl {
                        Logger.shared.logAlways("Artwork URL: \(url)")
                    } else {
                        Logger.shared.logAlways("Artwork URL: nil")
                    }
                }
                completion()
            }
        }
    }

    func fetchArtwork() {
        guard let info = cachedInfo else {
            Logger.shared.log("fetchArtwork: No track info", key: "no_track_info")
            cachedArtwork = nil
            return
        }

        guard let urlString = info.artworkUrl else {
            Logger.shared.log("fetchArtwork: No artwork URL for '\(info.title)'", key: "no_artwork_url_\(info.title)")
            cachedArtwork = nil
            return
        }

        guard let url = URL(string: urlString) else {
            Logger.shared.logAlways("fetchArtwork: Invalid URL: \(urlString)")
            cachedArtwork = nil
            return
        }

        do {
            let data = try Data(contentsOf: url)
            cachedArtwork = data
            Logger.shared.log("fetchArtwork: Loaded \(data.count) bytes for '\(info.title)'", key: "artwork_loaded_\(info.title)")
        } catch {
            Logger.shared.logAlways("fetchArtwork: Failed to load from \(urlString): \(error.localizedDescription)")
            cachedArtwork = nil
        }
    }

    func playPause(completion: (() -> Void)? = nil) {
        runAppleScriptAsync("tell application \"Music\" to playpause") { _ in
            completion?()
        }
    }

    func nextTrack(completion: (() -> Void)? = nil) {
        runAppleScriptAsync("tell application \"Music\" to next track") { _ in
            completion?()
        }
    }

    func previousTrack(completion: (() -> Void)? = nil) {
        runAppleScriptAsync("tell application \"Music\" to previous track") { _ in
            completion?()
        }
    }

    func isFavoritedAsync(completion: @escaping (Bool) -> Void) {
        runAppleScriptAsync("tell application \"Music\" to get favorited of current track") { result in
            completion(result == "true")
        }
    }

    func toggleFavorite(completion: (() -> Void)? = nil) {
        isFavoritedAsync { [weak self] current in
            self?.runAppleScriptAsync("tell application \"Music\" to set favorited of current track to \(current ? "false" : "true")") { _ in
                if var info = self?.cachedInfo {
                    info.isFavorited = !current
                    self?.cachedInfo = info
                }
                completion?()
            }
        }
    }

    private func runJXAAsync(_ script: String, completion: @escaping (String?) -> Void) {
        scriptQueue.async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-l", "JavaScript", "-e", script]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                completion(result)
            } catch {
                completion(nil)
            }
        }
    }

    private func runAppleScriptAsync(_ script: String, completion: ((String?) -> Void)? = nil) {
        scriptQueue.async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                completion?(result)
            } catch {
                completion?(nil)
            }
        }
    }
}

// MARK: - Config

struct Config: Codable {
    var windowX: CGFloat
    var windowY: CGFloat
    var windowWidth: CGFloat
    var backgroundColor: String
    var backgroundOpacity: CGFloat
    var launchOnLogin: Bool
    var showInDock: Bool
    var showInMenuBar: Bool
    var alwaysOnTop: Bool
    var loggingEnabled: Bool

    static let defaultConfig = Config(
        windowX: 100,
        windowY: 100,
        windowWidth: 400,
        backgroundColor: "657A91",
        backgroundOpacity: 0.47,
        launchOnLogin: false,
        showInDock: false,
        showInMenuBar: true,
        alwaysOnTop: true,
        loggingEnabled: false
    )
    static let minWidth: CGFloat = 300
    static let maxWidth: CGFloat = 800

    static var configURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Nanomuz")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return defaultConfig
        }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Config.configURL)
        }
    }
}

// MARK: - Launch Agent

struct LaunchAgent {
    static let label = "com.nanomuz"

    static var plistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func install() {
        let executablePath = ProcessInfo.processInfo.arguments[0]
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executablePath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        """
        try? plist.write(to: plistURL, atomically: true, encoding: .utf8)
    }

    static func uninstall() {
        try? FileManager.default.removeItem(at: plistURL)
    }
}

// MARK: - Color Helpers

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (30, 30, 30)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1.0
        )
    }

    var luminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    var isLight: Bool {
        luminance > 0.5
    }
}

struct DynamicColors {
    let background: NSColor
    let text: NSColor
    let textSecondary: NSColor
    let textTertiary: NSColor
    let buttonBackground: NSColor
    let buttonBackgroundHover: NSColor

    init(baseColor: NSColor, opacity: CGFloat) {
        background = baseColor.withAlphaComponent(opacity)

        if baseColor.isLight {
            text = NSColor.black.withAlphaComponent(0.9)
            textSecondary = NSColor.black.withAlphaComponent(0.6)
            textTertiary = NSColor.black.withAlphaComponent(0.4)
            buttonBackground = NSColor.black.withAlphaComponent(0.08)
            buttonBackgroundHover = NSColor.black.withAlphaComponent(0.15)
        } else {
            text = NSColor.white.withAlphaComponent(0.95)
            textSecondary = NSColor.white.withAlphaComponent(0.6)
            textTertiary = NSColor.white.withAlphaComponent(0.4)
            buttonBackground = NSColor.white.withAlphaComponent(0.08)
            buttonBackgroundHover = NSColor.white.withAlphaComponent(0.15)
        }
    }
}

// MARK: - Player View

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

    // Marquee animation
    private var scrollOffset: CGFloat = 0
    private var scrollTimer: Timer?
    private var scrollPauseCounter: Int = 0
    private let scrollSpeed: CGFloat = 0.5
    private let pauseFrames: Int = 120

    static let settingsPanelHeight: CGFloat = 70

    override var isFlipped: Bool { true }

    func setupSettingsControls(opacity: CGFloat, color: NSColor, launchOnLogin: Bool, showInDock: Bool, showInMenuBar: Bool, alwaysOnTop: Bool) {
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
        launchOnLoginLabel = NSTextField(labelWithString: "Launch on Login")
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
        alwaysOnTopLabel = NSTextField(labelWithString: "Always on Top")
        alwaysOnTopLabel?.font = NSFont.systemFont(ofSize: 11)
        addSubview(alwaysOnTopLabel!)

        updateSettingsColors()

        updateSettingsControlsVisibility()
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
    }

    func updateSettingsControlsLayout() {
        guard isSettingsExpanded else { return }
        let row1Y = bounds.height - PlayerView.settingsPanelHeight + 8
        let row2Y = row1Y + 26

        opacityLabel?.frame = NSRect(x: 12, y: row1Y, width: 50, height: 20)
        opacitySlider?.frame = NSRect(x: 62, y: row1Y, width: 100, height: 20)
        colorWell?.frame = NSRect(x: 170, y: row1Y - 2, width: 44, height: 24)
        launchOnLoginCheckbox?.frame = NSRect(x: 224, y: row1Y, width: 18, height: 20)
        launchOnLoginLabel?.frame = NSRect(x: 242, y: row1Y, width: 100, height: 20)

        showInDockCheckbox?.frame = NSRect(x: 12, y: row2Y, width: 18, height: 20)
        showInDockLabel?.frame = NSRect(x: 30, y: row2Y, width: 40, height: 20)
        showInMenuBarCheckbox?.frame = NSRect(x: 75, y: row2Y, width: 18, height: 20)
        showInMenuBarLabel?.frame = NSRect(x: 93, y: row2Y, width: 65, height: 20)
        alwaysOnTopCheckbox?.frame = NSRect(x: 163, y: row2Y, width: 18, height: 20)
        alwaysOnTopLabel?.frame = NSRect(x: 181, y: row2Y, width: 90, height: 20)
    }

    func updateSettingsColors() {
        opacityLabel?.textColor = colors.textSecondary
        launchOnLoginLabel?.textColor = colors.text
        showInDockLabel?.textColor = colors.text
        showInMenuBarLabel?.textColor = colors.text
        alwaysOnTopLabel?.textColor = colors.text
        launchOnLoginCheckbox?.contentTintColor = colors.text
        showInDockCheckbox?.contentTintColor = colors.text
        showInMenuBarCheckbox?.contentTintColor = colors.text
        alwaysOnTopCheckbox?.contentTintColor = colors.text
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

        // Prev button
        drawButton(rect: NSRect(x: x, y: buttonY, width: buttonSize, height: buttonSize), symbol: "⏮", id: "prev")
        x += buttonSize + 4

        // Play/Pause button
        let playSymbol = nowPlaying?.isPlaying == true ? "⏸" : "▶"
        drawButton(rect: NSRect(x: x, y: buttonY, width: buttonSize + 4, height: buttonSize), symbol: playSymbol, id: "play")
        x += buttonSize + 8

        // Next button
        drawButton(rect: NSRect(x: x, y: buttonY, width: buttonSize, height: buttonSize), symbol: "⏭", id: "next")
        x += buttonSize + 12

        // Artwork
        let artSize: CGFloat = 32
        let artY = (playerHeight - artSize) / 2
        drawArtwork(rect: NSRect(x: x, y: artY, width: artSize, height: artSize), rounding: 6)
        x += artSize + 10

        // Track info
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

                // Title - scroll only if needed
                if titleNeedsScroll {
                    let maxTitleScroll = titleWidth + gap
                    let titleOffset = scrollOffset.truncatingRemainder(dividingBy: maxTitleScroll)
                    let drawTitleX = x - titleOffset
                    NSAttributedString(string: np.title, attributes: titleAttrs).draw(at: NSPoint(x: drawTitleX, y: buttonY - 1))
                    NSAttributedString(string: np.title, attributes: titleAttrs).draw(at: NSPoint(x: drawTitleX + titleWidth + gap, y: buttonY - 1))
                } else {
                    NSAttributedString(string: np.title, attributes: titleAttrs).draw(at: NSPoint(x: x, y: buttonY - 1))
                }

                // Artist - scroll only if needed
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

        // Settings button
        let settingsSymbol = isSettingsExpanded ? "▼" : "⚙"
        drawButton(rect: NSRect(x: bounds.width - 96, y: buttonY, width: 28, height: buttonSize), symbol: settingsSymbol, id: "settings")

        // Favorite button
        let favSymbol = nowPlaying?.isFavorited == true ? "♥" : "♡"
        drawButton(rect: NSRect(x: bounds.width - 64, y: buttonY, width: 28, height: buttonSize), symbol: favSymbol, id: "fav")

        // Quit button
        drawButton(rect: NSRect(x: bounds.width - 32, y: buttonY, width: 24, height: buttonSize), symbol: "✕", id: "quit")

        // Settings panel divider
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
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
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
        if let button = buttonAt(point: point) {
            switch button {
            case "prev": onPrevious?()
            case "play": onPlayPause?()
            case "next": onNext?()
            case "settings": onSettingsToggle?()
            case "fav": onFavorite?()
            case "quit": onQuit?()
            default: break
            }
        } else {
            window?.performDrag(with: event)
        }
    }
}

// MARK: - App Delegate

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
        playerView.setupSettingsControls(
            opacity: config.backgroundOpacity,
            color: NSColor(hex: config.backgroundColor),
            launchOnLogin: config.launchOnLogin,
            showInDock: config.showInDock,
            showInMenuBar: config.showInMenuBar,
            alwaysOnTop: config.alwaysOnTop
        )

        window.contentView = playerView
        window.makeKeyAndOrderFront(nil)

        updateNowPlaying()
        updateTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
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
            baseColor: NSColor(hex: config.backgroundColor),
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

    func updateNowPlaying() {
        guard !isUpdating else { return }
        isUpdating = true

        MediaController.shared.fetchFromMediaRemote { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isUpdating = false

                let info = MediaController.shared.cachedInfo
                self.playerView.nowPlaying = info

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
                                    self?.playerView.setNeedsDisplay(self?.playerView.bounds ?? .zero)
                                }
                            }
                        }
                    }
                }

                if let data = MediaController.shared.cachedArtwork, self.playerView.artworkImage == nil {
                    if let image = NSImage(data: data) {
                        self.playerView.artworkImage = image
                    }
                }

                self.playerView.setNeedsDisplay(self.playerView.bounds)
            }
        }
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

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
