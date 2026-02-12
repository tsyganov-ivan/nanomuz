import XCTest
import AppKit

// MARK: - Test Settings Manager

protocol TestSettingsManagerDelegate: AnyObject {
    func testSettingsManager(_ manager: TestSettingsManager, didUpdateOpacity opacity: CGFloat)
    func testSettingsManager(_ manager: TestSettingsManager, didUpdateBackgroundColor color: NSColor)
    func testSettingsManager(_ manager: TestSettingsManager, didUpdateShowInDock enabled: Bool)
    func testSettingsManager(_ manager: TestSettingsManager, didUpdateShowInMenuBar enabled: Bool)
    func testSettingsManager(_ manager: TestSettingsManager, didUpdateAlwaysOnTop enabled: Bool)
    func testSettingsManager(_ manager: TestSettingsManager, didUpdateLastfmEnabled enabled: Bool)
    func testSettingsManager(_ manager: TestSettingsManager, didUpdateAdaptiveColors enabled: Bool)
    func testSettingsManager(_ manager: TestSettingsManager, didUpdateLoggingEnabled enabled: Bool)
    func testSettingsManagerDidResetSettings(_ manager: TestSettingsManager)
}

class TestSettingsManager {
    var config: TestConfig
    weak var delegate: TestSettingsManagerDelegate?
    var lastfmServiceEnabled: Bool = false
    var lastfmServiceReset: Bool = false

    init(config: TestConfig = .defaultConfig) {
        self.config = config
    }

    func updateOpacity(_ opacity: CGFloat) {
        config.backgroundOpacity = opacity
        delegate?.testSettingsManager(self, didUpdateOpacity: opacity)
    }

    func updateBackgroundColor(_ color: NSColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        let hex = String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        config.backgroundColor = hex
        delegate?.testSettingsManager(self, didUpdateBackgroundColor: color)
    }

    func updateShowInDock(_ enabled: Bool) {
        config.showInDock = enabled
        delegate?.testSettingsManager(self, didUpdateShowInDock: enabled)
    }

    func updateShowInMenuBar(_ enabled: Bool) {
        config.showInMenuBar = enabled
        delegate?.testSettingsManager(self, didUpdateShowInMenuBar: enabled)
    }

    func updateAlwaysOnTop(_ enabled: Bool) {
        config.alwaysOnTop = enabled
        delegate?.testSettingsManager(self, didUpdateAlwaysOnTop: enabled)
    }

    func updateLastfmEnabled(_ enabled: Bool) {
        config.lastfmEnabled = enabled
        lastfmServiceEnabled = enabled
        if !enabled {
            lastfmServiceReset = true
        }
        delegate?.testSettingsManager(self, didUpdateLastfmEnabled: enabled)
    }

    func updateAdaptiveColors(_ enabled: Bool) {
        config.adaptiveColors = enabled
        delegate?.testSettingsManager(self, didUpdateAdaptiveColors: enabled)
    }

    func updateLoggingEnabled(_ enabled: Bool) {
        config.loggingEnabled = enabled
        delegate?.testSettingsManager(self, didUpdateLoggingEnabled: enabled)
    }

    func resetSettings() {
        config = TestConfig.defaultConfig
        delegate?.testSettingsManagerDidResetSettings(self)
    }
}

// MARK: - Mock Delegate

class MockSettingsManagerDelegate: TestSettingsManagerDelegate {
    var opacityUpdated: CGFloat?
    var backgroundColorUpdated: NSColor?
    var showInDockUpdated: Bool?
    var showInMenuBarUpdated: Bool?
    var alwaysOnTopUpdated: Bool?
    var lastfmEnabledUpdated: Bool?
    var adaptiveColorsUpdated: Bool?
    var loggingEnabledUpdated: Bool?
    var resetSettingsCalled = false

    func testSettingsManager(_ manager: TestSettingsManager, didUpdateOpacity opacity: CGFloat) {
        opacityUpdated = opacity
    }

    func testSettingsManager(_ manager: TestSettingsManager, didUpdateBackgroundColor color: NSColor) {
        backgroundColorUpdated = color
    }

    func testSettingsManager(_ manager: TestSettingsManager, didUpdateShowInDock enabled: Bool) {
        showInDockUpdated = enabled
    }

    func testSettingsManager(_ manager: TestSettingsManager, didUpdateShowInMenuBar enabled: Bool) {
        showInMenuBarUpdated = enabled
    }

    func testSettingsManager(_ manager: TestSettingsManager, didUpdateAlwaysOnTop enabled: Bool) {
        alwaysOnTopUpdated = enabled
    }

    func testSettingsManager(_ manager: TestSettingsManager, didUpdateLastfmEnabled enabled: Bool) {
        lastfmEnabledUpdated = enabled
    }

    func testSettingsManager(_ manager: TestSettingsManager, didUpdateAdaptiveColors enabled: Bool) {
        adaptiveColorsUpdated = enabled
    }

    func testSettingsManager(_ manager: TestSettingsManager, didUpdateLoggingEnabled enabled: Bool) {
        loggingEnabledUpdated = enabled
    }

    func testSettingsManagerDidResetSettings(_ manager: TestSettingsManager) {
        resetSettingsCalled = true
    }
}

// MARK: - Tests

final class SettingsManagerTests: XCTestCase {
    var manager: TestSettingsManager!
    var delegate: MockSettingsManagerDelegate!

    override func setUp() {
        super.setUp()
        manager = TestSettingsManager()
        delegate = MockSettingsManagerDelegate()
        manager.delegate = delegate
    }

    override func tearDown() {
        manager = nil
        delegate = nil
        super.tearDown()
    }

    func testUpdateOpacityUpdatesConfigAndNotifiesDelegate() {
        let newOpacity: CGFloat = 0.75

        manager.updateOpacity(newOpacity)

        XCTAssertEqual(manager.config.backgroundOpacity, newOpacity)
        XCTAssertEqual(delegate.opacityUpdated, newOpacity)
    }

    func testUpdateBackgroundColorConvertsNSColorToHex() {
        let red = NSColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)

        manager.updateBackgroundColor(red)

        XCTAssertEqual(manager.config.backgroundColor, "FF0000")
        XCTAssertNotNil(delegate.backgroundColorUpdated)
    }

    func testUpdateBackgroundColorConvertsGreenToHex() {
        let green = NSColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)

        manager.updateBackgroundColor(green)

        XCTAssertEqual(manager.config.backgroundColor, "00FF00")
    }

    func testUpdateBackgroundColorConvertsMixedColorToHex() {
        let mixed = NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)

        manager.updateBackgroundColor(mixed)

        XCTAssertEqual(manager.config.backgroundColor, "7F7F7F")
    }

    func testUpdateShowInDockNotifiesDelegate() {
        manager.updateShowInDock(true)

        XCTAssertEqual(manager.config.showInDock, true)
        XCTAssertEqual(delegate.showInDockUpdated, true)

        manager.updateShowInDock(false)

        XCTAssertEqual(manager.config.showInDock, false)
        XCTAssertEqual(delegate.showInDockUpdated, false)
    }

    func testUpdateShowInMenuBarNotifiesDelegate() {
        manager.updateShowInMenuBar(false)

        XCTAssertEqual(manager.config.showInMenuBar, false)
        XCTAssertEqual(delegate.showInMenuBarUpdated, false)

        manager.updateShowInMenuBar(true)

        XCTAssertEqual(manager.config.showInMenuBar, true)
        XCTAssertEqual(delegate.showInMenuBarUpdated, true)
    }

    func testUpdateAlwaysOnTopNotifiesDelegate() {
        manager.updateAlwaysOnTop(false)

        XCTAssertEqual(manager.config.alwaysOnTop, false)
        XCTAssertEqual(delegate.alwaysOnTopUpdated, false)

        manager.updateAlwaysOnTop(true)

        XCTAssertEqual(manager.config.alwaysOnTop, true)
        XCTAssertEqual(delegate.alwaysOnTopUpdated, true)
    }

    func testUpdateLastfmEnabledEnablesScrobbleService() {
        manager.updateLastfmEnabled(true)

        XCTAssertEqual(manager.config.lastfmEnabled, true)
        XCTAssertEqual(manager.lastfmServiceEnabled, true)
        XCTAssertFalse(manager.lastfmServiceReset)
        XCTAssertEqual(delegate.lastfmEnabledUpdated, true)
    }

    func testUpdateLastfmEnabledDisablesAndResetsScrobbleService() {
        manager.updateLastfmEnabled(false)

        XCTAssertEqual(manager.config.lastfmEnabled, false)
        XCTAssertEqual(manager.lastfmServiceEnabled, false)
        XCTAssertTrue(manager.lastfmServiceReset)
        XCTAssertEqual(delegate.lastfmEnabledUpdated, false)
    }

    func testUpdateAdaptiveColorsNotifiesDelegate() {
        manager.updateAdaptiveColors(false)

        XCTAssertEqual(manager.config.adaptiveColors, false)
        XCTAssertEqual(delegate.adaptiveColorsUpdated, false)

        manager.updateAdaptiveColors(true)

        XCTAssertEqual(manager.config.adaptiveColors, true)
        XCTAssertEqual(delegate.adaptiveColorsUpdated, true)
    }

    func testResetSettingsRestoresDefaultsAndNotifiesDelegate() {
        manager.config.backgroundOpacity = 1.0
        manager.config.backgroundColor = "000000"
        manager.config.showInDock = true
        manager.config.alwaysOnTop = false

        manager.resetSettings()

        XCTAssertEqual(manager.config.backgroundOpacity, TestConfig.defaultConfig.backgroundOpacity)
        XCTAssertEqual(manager.config.backgroundColor, TestConfig.defaultConfig.backgroundColor)
        XCTAssertEqual(manager.config.showInDock, TestConfig.defaultConfig.showInDock)
        XCTAssertEqual(manager.config.alwaysOnTop, TestConfig.defaultConfig.alwaysOnTop)
        XCTAssertTrue(delegate.resetSettingsCalled)
    }

    func testUpdateLoggingEnabledNotifiesDelegate() {
        manager.updateLoggingEnabled(true)

        XCTAssertEqual(manager.config.loggingEnabled, true)
        XCTAssertEqual(delegate.loggingEnabledUpdated, true)

        manager.updateLoggingEnabled(false)

        XCTAssertEqual(manager.config.loggingEnabled, false)
        XCTAssertEqual(delegate.loggingEnabledUpdated, false)
    }

    func testDelegateNotCalledWhenNil() {
        manager.delegate = nil

        manager.updateOpacity(0.5)
        manager.updateBackgroundColor(.blue)
        manager.updateShowInDock(true)
        manager.updateShowInMenuBar(false)
        manager.updateAlwaysOnTop(false)
        manager.updateLastfmEnabled(true)
        manager.updateAdaptiveColors(false)
        manager.resetSettings()

        XCTAssertEqual(manager.config.backgroundOpacity, TestConfig.defaultConfig.backgroundOpacity)
    }

    func testInitialConfigUsesDefaults() {
        let newManager = TestSettingsManager()

        XCTAssertEqual(newManager.config.backgroundOpacity, TestConfig.defaultConfig.backgroundOpacity)
        XCTAssertEqual(newManager.config.backgroundColor, TestConfig.defaultConfig.backgroundColor)
        XCTAssertEqual(newManager.config.showInDock, TestConfig.defaultConfig.showInDock)
        XCTAssertEqual(newManager.config.showInMenuBar, TestConfig.defaultConfig.showInMenuBar)
        XCTAssertEqual(newManager.config.alwaysOnTop, TestConfig.defaultConfig.alwaysOnTop)
        XCTAssertEqual(newManager.config.adaptiveColors, TestConfig.defaultConfig.adaptiveColors)
    }

    func testCustomInitialConfig() {
        let customConfig = TestConfig(
            windowX: 200,
            windowY: 200,
            windowWidth: 500,
            backgroundColor: "123456",
            backgroundOpacity: 0.9,
            launchOnLogin: true,
            showInDock: true,
            showInMenuBar: false,
            alwaysOnTop: false,
            loggingEnabled: true,
            lastfmEnabled: false,
            lastfmUsername: "user",
            lastfmSessionKey: "key",
            adaptiveColors: false
        )

        let customManager = TestSettingsManager(config: customConfig)

        XCTAssertEqual(customManager.config.backgroundColor, "123456")
        XCTAssertEqual(customManager.config.backgroundOpacity, 0.9)
        XCTAssertEqual(customManager.config.showInDock, true)
    }
}
