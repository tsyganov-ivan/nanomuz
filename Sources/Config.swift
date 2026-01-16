import Foundation

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
    var lastfmEnabled: Bool
    var lastfmUsername: String
    var lastfmSessionKey: String
    var adaptiveColors: Bool

    init(windowX: CGFloat, windowY: CGFloat, windowWidth: CGFloat, backgroundColor: String,
         backgroundOpacity: CGFloat, launchOnLogin: Bool, showInDock: Bool, showInMenuBar: Bool,
         alwaysOnTop: Bool, loggingEnabled: Bool, lastfmEnabled: Bool, lastfmUsername: String,
         lastfmSessionKey: String, adaptiveColors: Bool) {
        self.windowX = windowX
        self.windowY = windowY
        self.windowWidth = windowWidth
        self.backgroundColor = backgroundColor
        self.backgroundOpacity = backgroundOpacity
        self.launchOnLogin = launchOnLogin
        self.showInDock = showInDock
        self.showInMenuBar = showInMenuBar
        self.alwaysOnTop = alwaysOnTop
        self.loggingEnabled = loggingEnabled
        self.lastfmEnabled = lastfmEnabled
        self.lastfmUsername = lastfmUsername
        self.lastfmSessionKey = lastfmSessionKey
        self.adaptiveColors = adaptiveColors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windowX = try container.decode(CGFloat.self, forKey: .windowX)
        windowY = try container.decode(CGFloat.self, forKey: .windowY)
        windowWidth = try container.decode(CGFloat.self, forKey: .windowWidth)
        backgroundColor = try container.decode(String.self, forKey: .backgroundColor)
        backgroundOpacity = try container.decode(CGFloat.self, forKey: .backgroundOpacity)
        launchOnLogin = try container.decode(Bool.self, forKey: .launchOnLogin)
        showInDock = try container.decode(Bool.self, forKey: .showInDock)
        showInMenuBar = try container.decode(Bool.self, forKey: .showInMenuBar)
        alwaysOnTop = try container.decode(Bool.self, forKey: .alwaysOnTop)
        loggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .loggingEnabled) ?? false
        lastfmEnabled = try container.decodeIfPresent(Bool.self, forKey: .lastfmEnabled) ?? false
        lastfmUsername = try container.decodeIfPresent(String.self, forKey: .lastfmUsername) ?? ""
        lastfmSessionKey = try container.decodeIfPresent(String.self, forKey: .lastfmSessionKey) ?? ""
        adaptiveColors = try container.decodeIfPresent(Bool.self, forKey: .adaptiveColors) ?? true
    }

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
        loggingEnabled: false,
        lastfmEnabled: true,
        lastfmUsername: "",
        lastfmSessionKey: "",
        adaptiveColors: true
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
