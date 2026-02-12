import AppKit

class MenuBarManager: NSObject, MenuBarManagerProtocol {
    private(set) var statusItem: NSStatusItem?
    weak var delegate: MenuBarManagerDelegate?

    private var alwaysOnTopItem: NSMenuItem?
    private var scrobbleItem: NSMenuItem?
    private var loggingItem: NSMenuItem?
    private var lastfmItem: NSMenuItem?
    private var connectItem: NSMenuItem?
    private var disconnectItem: NSMenuItem?

    func setup() {
        guard statusItem == nil else { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let icon = NSApp.applicationIconImage?.copy() as? NSImage
            icon?.size = NSSize(width: 18, height: 18)
            button.image = icon
        }

        let menu = NSMenu()

        let alwaysOnTop = NSMenuItem(title: "Always on Top", action: #selector(toggleAlwaysOnTop), keyEquivalent: "")
        alwaysOnTop.target = self
        alwaysOnTopItem = alwaysOnTop
        menu.addItem(alwaysOnTop)
        menu.addItem(NSMenuItem.separator())

        let scrobble = NSMenuItem(title: "Scrobbling", action: #selector(toggleScrobbling), keyEquivalent: "")
        scrobble.target = self
        scrobbleItem = scrobble
        menu.addItem(scrobble)

        let lastfm = NSMenuItem(title: "Last.fm: Not Connected", action: nil, keyEquivalent: "")
        lastfmItem = lastfm
        let lastfmSubmenu = NSMenu()
        let connect = NSMenuItem(title: "Connect", action: #selector(connectLastfm), keyEquivalent: "")
        connect.target = self
        connectItem = connect
        lastfmSubmenu.addItem(connect)
        let disconnect = NSMenuItem(title: "Disconnect", action: #selector(disconnectLastfm), keyEquivalent: "")
        disconnect.target = self
        disconnect.isHidden = true
        disconnectItem = disconnect
        lastfmSubmenu.addItem(disconnect)
        lastfm.submenu = lastfmSubmenu
        menu.addItem(lastfm)

        menu.addItem(NSMenuItem.separator())

        let logging = NSMenuItem(title: "Enable Logging", action: #selector(toggleLogging), keyEquivalent: "")
        logging.target = self
        loggingItem = logging
        menu.addItem(logging)

        let showLogItem = NSMenuItem(title: "Show Log File", action: #selector(showLogFile), keyEquivalent: "")
        showLogItem.target = self
        menu.addItem(showLogItem)

        menu.addItem(NSMenuItem.separator())

        let resetItem = NSMenuItem(title: "Reset Settings", action: #selector(resetSettings), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About Nanomuz", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    func teardown() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        alwaysOnTopItem = nil
        scrobbleItem = nil
        loggingItem = nil
        lastfmItem = nil
        connectItem = nil
        disconnectItem = nil
    }

    func updateAlwaysOnTopState(_ enabled: Bool) {
        alwaysOnTopItem?.state = enabled ? .on : .off
    }

    func updateScrobblingState(_ enabled: Bool) {
        scrobbleItem?.state = enabled ? .on : .off
    }

    func updateLoggingState(_ enabled: Bool) {
        loggingItem?.state = enabled ? .on : .off
    }

    func updateLastfmConnectionState(connected: Bool) {
        lastfmItem?.title = connected ? "Last.fm: Connected" : "Last.fm: Not Connected"
        connectItem?.isHidden = connected
        disconnectItem?.isHidden = !connected
    }

    // MARK: - Menu Actions

    @objc private func toggleAlwaysOnTop() {
        delegate?.menuBarManagerDidToggleAlwaysOnTop(self)
    }

    @objc private func toggleScrobbling() {
        delegate?.menuBarManagerDidToggleScrobbling(self)
    }

    @objc private func toggleLogging() {
        delegate?.menuBarManagerDidToggleLogging(self)
    }

    @objc private func connectLastfm() {
        delegate?.menuBarManagerDidRequestConnectLastfm(self)
    }

    @objc private func disconnectLastfm() {
        delegate?.menuBarManagerDidRequestDisconnectLastfm(self)
    }

    @objc private func showLogFile() {
        delegate?.menuBarManagerDidRequestShowLogFile(self)
    }

    @objc private func showAbout() {
        delegate?.menuBarManagerDidRequestShowAbout(self)
    }

    @objc private func resetSettings() {
        delegate?.menuBarManagerDidRequestResetSettings(self)
    }

    @objc private func quitApp() {
        delegate?.menuBarManagerDidRequestQuit(self)
    }
}
