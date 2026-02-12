import XCTest

struct TestConfig: Codable {
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

    static let defaultConfig = TestConfig(
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
}

final class ConfigTests: XCTestCase {

    func testDefaultConfigValues() {
        let config = TestConfig.defaultConfig

        XCTAssertEqual(config.windowX, 100)
        XCTAssertEqual(config.windowY, 100)
        XCTAssertEqual(config.windowWidth, 400)
        XCTAssertEqual(config.backgroundColor, "657A91")
        XCTAssertEqual(config.backgroundOpacity, 0.47)
        XCTAssertFalse(config.launchOnLogin)
        XCTAssertFalse(config.showInDock)
        XCTAssertTrue(config.showInMenuBar)
        XCTAssertTrue(config.alwaysOnTop)
        XCTAssertFalse(config.loggingEnabled)
        XCTAssertTrue(config.lastfmEnabled)
        XCTAssertEqual(config.lastfmUsername, "")
        XCTAssertEqual(config.lastfmSessionKey, "")
        XCTAssertTrue(config.adaptiveColors)
    }

    func testConfigEncodeDecode() throws {
        let original = TestConfig(
            windowX: 200,
            windowY: 300,
            windowWidth: 500,
            backgroundColor: "FF0000",
            backgroundOpacity: 0.8,
            launchOnLogin: true,
            showInDock: true,
            showInMenuBar: false,
            alwaysOnTop: false,
            loggingEnabled: true,
            lastfmEnabled: false,
            lastfmUsername: "testuser",
            lastfmSessionKey: "testsession",
            adaptiveColors: false
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TestConfig.self, from: data)

        XCTAssertEqual(decoded.windowX, original.windowX)
        XCTAssertEqual(decoded.windowY, original.windowY)
        XCTAssertEqual(decoded.windowWidth, original.windowWidth)
        XCTAssertEqual(decoded.backgroundColor, original.backgroundColor)
        XCTAssertEqual(decoded.backgroundOpacity, original.backgroundOpacity)
        XCTAssertEqual(decoded.launchOnLogin, original.launchOnLogin)
        XCTAssertEqual(decoded.showInDock, original.showInDock)
        XCTAssertEqual(decoded.showInMenuBar, original.showInMenuBar)
        XCTAssertEqual(decoded.alwaysOnTop, original.alwaysOnTop)
        XCTAssertEqual(decoded.loggingEnabled, original.loggingEnabled)
        XCTAssertEqual(decoded.lastfmEnabled, original.lastfmEnabled)
        XCTAssertEqual(decoded.lastfmUsername, original.lastfmUsername)
        XCTAssertEqual(decoded.lastfmSessionKey, original.lastfmSessionKey)
        XCTAssertEqual(decoded.adaptiveColors, original.adaptiveColors)
    }

    func testConfigDecodeWithMissingOptionalFields() throws {
        let json = """
        {
            "windowX": 100,
            "windowY": 100,
            "windowWidth": 400,
            "backgroundColor": "657A91",
            "backgroundOpacity": 0.47,
            "launchOnLogin": false,
            "showInDock": false,
            "showInMenuBar": true,
            "alwaysOnTop": true
        }
        """
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        let config = try decoder.decode(TestConfig.self, from: data)

        XCTAssertFalse(config.loggingEnabled)
        XCTAssertFalse(config.lastfmEnabled)
        XCTAssertEqual(config.lastfmUsername, "")
        XCTAssertEqual(config.lastfmSessionKey, "")
        XCTAssertTrue(config.adaptiveColors)
    }

    func testConfigMinMaxWidthConstants() {
        XCTAssertEqual(TestConfig.minWidth, 300)
        XCTAssertEqual(TestConfig.maxWidth, 800)
        XCTAssertLessThan(TestConfig.minWidth, TestConfig.maxWidth)
    }

    func testConfigBackgroundColorValidation() {
        let config = TestConfig.defaultConfig
        XCTAssertEqual(config.backgroundColor.count, 6)
        XCTAssertTrue(config.backgroundColor.allSatisfy { $0.isHexDigit })
    }

    func testConfigOpacityRange() {
        let config = TestConfig.defaultConfig
        XCTAssertGreaterThanOrEqual(config.backgroundOpacity, 0)
        XCTAssertLessThanOrEqual(config.backgroundOpacity, 1)
    }
}
