import AppKit

class WindowManager: NSObject, WindowManagerProtocol, NSWindowDelegate {
    private(set) var window: NSWindow!
    weak var delegate: WindowManagerDelegate?

    static let playerHeight: CGFloat = 50

    func setup(with playerView: PlayerView, config: Config) {
        let size = NSSize(width: config.windowWidth, height: WindowManager.playerHeight)
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

        window.minSize = NSSize(width: Config.minWidth, height: WindowManager.playerHeight)
        window.maxSize = NSSize(width: Config.maxWidth, height: WindowManager.playerHeight)

        window.contentView = playerView
        window.makeKeyAndOrderFront(nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: window
        )
    }

    func toggleSettingsPanel(isExpanded: Bool, playerView: PlayerView) {
        let newHeight = isExpanded
            ? WindowManager.playerHeight + PlayerView.settingsPanelHeight
            : WindowManager.playerHeight

        var frame = window.frame
        let heightDiff = newHeight - frame.height
        frame.size.height = newHeight
        frame.origin.y -= heightDiff

        window.minSize = NSSize(width: Config.minWidth, height: newHeight)
        window.maxSize = NSSize(width: Config.maxWidth, height: newHeight)
        window.setFrame(frame, display: true, animate: true)

        playerView.frame = NSRect(origin: .zero, size: frame.size)
    }

    func updateWindowLevel(_ level: NSWindow.Level) {
        window.level = level
    }

    func setWindowPosition(x: CGFloat, y: CGFloat) {
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func setWindowWidth(_ width: CGFloat) {
        var frame = window.frame
        frame.size.width = width
        window.setFrame(frame, display: true)
    }

    // MARK: - NSWindowDelegate

    @objc func windowDidMove(_ notification: Notification) {
        delegate?.windowManager(self, didMoveWindow: window.frame)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let currentHeight = window.frame.height
        return NSSize(width: frameSize.width, height: currentHeight)
    }

    func windowDidResize(_ notification: Notification) {
        delegate?.windowManager(self, didResizeWindow: window.frame)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
