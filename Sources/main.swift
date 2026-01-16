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

// MARK: - Color Extraction

extension NSImage {
    func dominantColor() -> NSColor? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }

        // Resize to small size for faster processing
        let smallSize = 20
        guard let resized = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: smallSize,
            pixelsHigh: smallSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: smallSize * 4,
            bitsPerPixel: 32
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resized)
        bitmap.draw(in: NSRect(x: 0, y: 0, width: smallSize, height: smallSize))
        NSGraphicsContext.restoreGraphicsState()

        var totalR: CGFloat = 0, totalG: CGFloat = 0, totalB: CGFloat = 0
        var count: CGFloat = 0

        for y in 0..<smallSize {
            for x in 0..<smallSize {
                guard let color = resized.colorAt(x: x, y: y) else { continue }
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)

                // Skip very dark and very bright pixels
                let brightness = (r + g + b) / 3
                if brightness > 0.1 && brightness < 0.9 {
                    // Weight by saturation for more vibrant colors
                    let maxC = max(r, g, b), minC = min(r, g, b)
                    let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
                    let weight = 1 + saturation

                    totalR += r * weight
                    totalG += g * weight
                    totalB += b * weight
                    count += weight
                }
            }
        }

        guard count > 0 else { return nil }
        return NSColor(red: totalR / count, green: totalG / count, blue: totalB / count, alpha: 1.0)
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
    let duration: Int?
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
        var duration = info.valueForKey('kMRMediaRemoteNowPlayingInfoDuration');
        if (duration && !duration.isNil()) result.duration = ObjC.unwrap(duration);
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

            let durationValue = dict["duration"] as? Double
            self.isFavoritedAsync { isFav in
                self.cachedInfo = NowPlayingInfo(
                    title: title,
                    artist: artist,
                    album: dict["album"] as? String ?? "",
                    isPlaying: (dict["playbackRate"] as? Double ?? 0) > 0,
                    artworkUrl: artworkUrl,
                    isFavorited: isFav,
                    duration: durationValue.map { Int($0) }
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

        // Try streaming artwork URL first (from MediaRemote)
        if let urlString = info.artworkUrl, let url = URL(string: urlString) {
            do {
                let data = try Data(contentsOf: url)
                cachedArtwork = data
                Logger.shared.log("fetchArtwork: Loaded \(data.count) bytes from URL for '\(info.title)'", key: "artwork_url_\(info.title)")
                return
            } catch {
                Logger.shared.log("fetchArtwork: URL failed for '\(info.title)': \(error.localizedDescription)", key: "artwork_url_fail_\(info.title)")
            }
        }

        // Fallback: get artwork from Music app via AppleScript (for local files)
        Logger.shared.log("fetchArtwork: Trying AppleScript fallback for '\(info.title)'", key: "artwork_as_try_\(info.title)")
        fetchArtworkFromMusicApp()
    }

    private func fetchArtworkFromMusicApp() {
        let tempPath = "/tmp/nanomuz_artwork.tmp"
        let script = """
        tell application "Music"
            try
                set currentTrack to current track
                set artworkCount to count of artworks of currentTrack
                if artworkCount > 0 then
                    set artworkData to raw data of artwork 1 of currentTrack
                    set tempPath to "\(tempPath)"
                    set fileRef to open for access POSIX file tempPath with write permission
                    set eof of fileRef to 0
                    write artworkData to fileRef
                    close access fileRef
                    return tempPath
                end if
            on error errMsg
                return "error:" & errMsg
            end try
        end tell
        return ""
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            let result = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if result == tempPath {
                let fileURL = URL(fileURLWithPath: tempPath)
                let imageData = try Data(contentsOf: fileURL)
                cachedArtwork = imageData
                try? FileManager.default.removeItem(at: fileURL)
                Logger.shared.log("fetchArtwork: Loaded \(imageData.count) bytes from Music app", key: "artwork_as_success")
            } else if result.hasPrefix("error:") {
                Logger.shared.log("fetchArtwork: AppleScript error: \(result)", key: "artwork_as_error")
                cachedArtwork = nil
            } else {
                Logger.shared.log("fetchArtwork: No artwork in Music app (result: \(result))", key: "artwork_as_none")
                cachedArtwork = nil
            }
        } catch {
            Logger.shared.logAlways("fetchArtwork: AppleScript execution failed: \(error.localizedDescription)")
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
    var lastfmEnabled: Bool
    var lastfmUsername: String
    var lastfmSessionKey: String
    var adaptiveColors: Bool

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

// MARK: - Last.fm Session Store

import CommonCrypto

struct LastFMSessionStore {
    static func saveSessionKey(_ sessionKey: String) -> Bool {
        var config = Config.load()
        config.lastfmSessionKey = sessionKey
        config.save()
        return true
    }

    static func loadSessionKey() -> String? {
        let key = Config.load().lastfmSessionKey
        return key.isEmpty ? nil : key
    }

    static func deleteSessionKey() {
        var config = Config.load()
        config.lastfmSessionKey = ""
        config.lastfmUsername = ""
        config.save()
    }
}

// MARK: - Last.fm Client

class LastFMClient {
    static let shared = LastFMClient()

    private let apiKey = "LASTFM_API_KEY_PLACEHOLDER"
    private let apiSecret = "LASTFM_API_SECRET_PLACEHOLDER"
    private let apiBaseURL = "https://ws.audioscrobbler.com/2.0/"
    private let requestQueue = DispatchQueue(label: "com.nanomuz.lastfm.client", qos: .userInitiated)

    private init() {}

    func generateSignature(params: [String: String]) -> String {
        let sortedKeys = params.keys.sorted()
        var signatureString = ""
        for key in sortedKeys {
            signatureString += key + (params[key] ?? "")
        }
        signatureString += apiSecret
        return md5(signatureString)
    }

    private func md5(_ string: String) -> String {
        let data = Data(string.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_MD5(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    func getToken(completion: @escaping (String?) -> Void) {
        var params: [String: String] = ["method": "auth.getToken", "api_key": apiKey]
        params["api_sig"] = generateSignature(params: params)
        params["format"] = "json"
        performGET(params: params) { result in
            completion((result?["token"] as? String))
        }
    }

    func getAuthorizationURL(token: String) -> URL? {
        URL(string: "https://www.last.fm/api/auth/?api_key=\(apiKey)&token=\(token)")
    }

    func getSession(token: String, completion: @escaping (String?, String?) -> Void) {
        var params: [String: String] = ["method": "auth.getSession", "api_key": apiKey, "token": token]
        params["api_sig"] = generateSignature(params: params)
        params["format"] = "json"
        performGET(params: params) { result in
            if let session = result?["session"] as? [String: Any],
               let key = session["key"] as? String,
               let name = session["name"] as? String {
                completion(key, name)
            } else {
                completion(nil, nil)
            }
        }
    }

    func updateNowPlaying(artist: String, track: String, album: String?, duration: Int?, sessionKey: String, completion: @escaping (Bool) -> Void) {
        var params: [String: String] = ["method": "track.updateNowPlaying", "api_key": apiKey, "sk": sessionKey, "artist": artist, "track": track]
        if let album = album, !album.isEmpty { params["album"] = album }
        if let duration = duration, duration > 0 { params["duration"] = String(duration) }
        params["api_sig"] = generateSignature(params: params)
        params["format"] = "json"
        performPOST(params: params) { completion($0 != nil) }
    }

    func scrobble(artist: String, track: String, album: String?, timestamp: Int, sessionKey: String, completion: @escaping (Bool) -> Void) {
        var params: [String: String] = ["method": "track.scrobble", "api_key": apiKey, "sk": sessionKey, "artist": artist, "track": track, "timestamp": String(timestamp)]
        if let album = album, !album.isEmpty { params["album"] = album }
        params["api_sig"] = generateSignature(params: params)
        params["format"] = "json"
        performPOST(params: params) { completion($0 != nil) }
    }

    private func performGET(params: [String: String], completion: @escaping ([String: Any]?) -> Void) {
        requestQueue.async {
            var urlComponents = URLComponents(string: self.apiBaseURL)!
            urlComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
            guard let url = urlComponents.url else { completion(nil); return }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 30
            URLSession.shared.dataTask(with: request) { data, _, error in
                guard error == nil, let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["error"] == nil else { completion(nil); return }
                completion(json)
            }.resume()
        }
    }

    private func performPOST(params: [String: String], completion: @escaping ([String: Any]?) -> Void) {
        requestQueue.async {
            guard let url = URL(string: self.apiBaseURL) else { completion(nil); return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 30
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            request.httpBody = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").data(using: .utf8)
            URLSession.shared.dataTask(with: request) { data, _, error in
                if let error = error {
                    Logger.shared.logAlways("Last.fm API error: \(error.localizedDescription)")
                    completion(nil); return
                }
                guard let data = data else { Logger.shared.logAlways("Last.fm API: No data"); completion(nil); return }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    Logger.shared.logAlways("Last.fm API: Invalid JSON - \(String(data: data, encoding: .utf8) ?? "?")")
                    completion(nil); return
                }
                if let errorCode = json["error"], let errorMsg = json["message"] {
                    Logger.shared.logAlways("Last.fm API error \(errorCode): \(errorMsg)")
                    completion(nil); return
                }
                completion(json)
            }.resume()
        }
    }
}

// MARK: - Last.fm Auth Service

class LastFMAuthService {
    static let shared = LastFMAuthService()
    private var pendingToken: String?
    private var authTimer: Timer?

    var isAuthenticated: Bool { LastFMSessionStore.loadSessionKey() != nil }
    var sessionKey: String? { LastFMSessionStore.loadSessionKey() }

    private init() {}

    func startAuthentication(completion: @escaping (Bool, String?) -> Void) {
        LastFMClient.shared.getToken { [weak self] token in
            guard let self = self, let token = token else {
                DispatchQueue.main.async { completion(false, nil) }
                return
            }
            self.pendingToken = token
            guard let url = LastFMClient.shared.getAuthorizationURL(token: token) else {
                DispatchQueue.main.async { completion(false, nil) }
                return
            }
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
                Logger.shared.logAlways("Last.fm: Opened browser for authorization")
            }
            self.startPollingForSession(completion: completion)
        }
    }

    private func startPollingForSession(completion: @escaping (Bool, String?) -> Void) {
        var attempts = 0
        DispatchQueue.main.async { [weak self] in
            self?.authTimer?.invalidate()
            self?.authTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self = self, let token = self.pendingToken else {
                timer.invalidate()
                DispatchQueue.main.async { completion(false, nil) }
                return
            }
            attempts += 1
            if attempts >= 60 {
                timer.invalidate()
                self.pendingToken = nil
                Logger.shared.logAlways("Last.fm: Authentication timed out")
                DispatchQueue.main.async { completion(false, nil) }
                return
            }
            LastFMClient.shared.getSession(token: token) { sessionKey, username in
                if let sessionKey = sessionKey, let username = username {
                    timer.invalidate()
                    self.pendingToken = nil
                    if LastFMSessionStore.saveSessionKey(sessionKey) {
                        Logger.shared.logAlways("Last.fm: Successfully authenticated as \(username)")
                        DispatchQueue.main.async { completion(true, username) }
                    } else {
                        DispatchQueue.main.async { completion(false, nil) }
                    }
                }
            }
            }
        }
    }

    func logout() {
        authTimer?.invalidate()
        authTimer = nil
        pendingToken = nil
        LastFMSessionStore.deleteSessionKey()
        Logger.shared.logAlways("Last.fm: Logged out")
    }
}

// MARK: - Last.fm Scrobble Service

class LastFMScrobbleService {
    static let shared = LastFMScrobbleService()

    private struct PlaybackSession {
        let track: String, artist: String, album: String, startedAt: Date
        var lastResumedAt: Date?, accumulatedPlaySeconds: Double, scrobbled: Bool, nowPlayingSent: Bool, durationSeconds: Int?
        var uniqueKey: String { "\(artist)|\(track)|\(album)|\(Int(startedAt.timeIntervalSince1970))" }
    }

    private var currentSession: PlaybackSession?
    private var recentScrobbles: [String] = []
    private var lastNowPlayingAt: Date?
    var enabled: Bool = true

    private init() {}

    func trackChanged(artist: String, track: String, album: String, isPlaying: Bool, durationSeconds: Int? = nil) {
        guard enabled else { Logger.shared.logAlways("Last.fm: Scrobbling disabled"); return }
        guard !artist.isEmpty, !track.isEmpty else { Logger.shared.logAlways("Last.fm: Empty artist/track"); return }
        guard LastFMAuthService.shared.isAuthenticated else { Logger.shared.logAlways("Last.fm: Not authenticated"); return }
        if let session = currentSession, session.artist == artist, session.track == track, session.album == album {
            if isPlaying { resumePlayback() } else { pausePlayback() }
            return
        }
        scrobbleIfNeeded()
        let now = Date()
        currentSession = PlaybackSession(track: track, artist: artist, album: album, startedAt: now, lastResumedAt: isPlaying ? now : nil, accumulatedPlaySeconds: 0, scrobbled: false, nowPlayingSent: false, durationSeconds: durationSeconds)
        Logger.shared.logAlways("Last.fm: New track session - \(artist) - \(track) (duration: \(durationSeconds.map { "\($0)s" } ?? "unknown"), isPlaying: \(isPlaying))")
        if isPlaying { sendNowPlaying() } else { Logger.shared.logAlways("Last.fm: Not playing, skip Now Playing") }
    }

    func playbackStateChanged(isPlaying: Bool) {
        guard enabled, currentSession != nil else { return }
        if isPlaying { resumePlayback() } else { pausePlayback() }
    }

    private func resumePlayback() {
        guard var session = currentSession, session.lastResumedAt == nil else { return }
        session.lastResumedAt = Date()
        currentSession = session
        if lastNowPlayingAt == nil || Date().timeIntervalSince(lastNowPlayingAt!) >= 15 { sendNowPlaying() }
    }

    private func pausePlayback() {
        guard var session = currentSession, let lastResumed = session.lastResumedAt else { return }
        session.accumulatedPlaySeconds += Date().timeIntervalSince(lastResumed)
        session.lastResumedAt = nil
        currentSession = session
        checkAndScrobble()
    }

    func tick() {
        guard enabled, var session = currentSession, let lastResumed = session.lastResumedAt else { return }
        let totalPlayed = session.accumulatedPlaySeconds + Date().timeIntervalSince(lastResumed)
        if shouldScrobble(session: session, totalPlayed: totalPlayed), !session.scrobbled {
            session.accumulatedPlaySeconds = totalPlayed
            session.lastResumedAt = Date()
            session.scrobbled = true
            currentSession = session
            performScrobble(session: session)
        }
    }

    private func sendNowPlaying() {
        guard let session = currentSession, let sessionKey = LastFMAuthService.shared.sessionKey else { return }
        lastNowPlayingAt = Date()
        LastFMClient.shared.updateNowPlaying(artist: session.artist, track: session.track, album: session.album.isEmpty ? nil : session.album, duration: session.durationSeconds, sessionKey: sessionKey) { success in
            Logger.shared.logAlways("Last.fm: Now playing \(success ? "sent" : "FAILED") - \(session.artist) - \(session.track)")
        }
    }

    private func scrobbleIfNeeded() {
        guard let session = currentSession else { return }
        var totalPlayed = session.accumulatedPlaySeconds
        if let lastResumed = session.lastResumedAt { totalPlayed += Date().timeIntervalSince(lastResumed) }
        if shouldScrobble(session: session, totalPlayed: totalPlayed), !session.scrobbled { performScrobble(session: session) }
    }

    private func checkAndScrobble() {
        guard let session = currentSession, !session.scrobbled, shouldScrobble(session: session, totalPlayed: session.accumulatedPlaySeconds) else { return }
        performScrobble(session: session)
    }

    private func shouldScrobble(session: PlaybackSession, totalPlayed: Double) -> Bool {
        guard let duration = session.durationSeconds, duration >= 30 else { return totalPlayed >= 240 }
        return totalPlayed >= min(Double(duration) * 0.5, 240)
    }

    private func performScrobble(session: PlaybackSession) {
        guard !recentScrobbles.contains(session.uniqueKey), let sessionKey = LastFMAuthService.shared.sessionKey else { return }
        recentScrobbles.append(session.uniqueKey)
        if recentScrobbles.count > 100 { recentScrobbles.removeFirst() }
        if var s = currentSession, s.uniqueKey == session.uniqueKey { s.scrobbled = true; currentSession = s }
        LastFMClient.shared.scrobble(artist: session.artist, track: session.track, album: session.album.isEmpty ? nil : session.album, timestamp: Int(session.startedAt.timeIntervalSince1970), sessionKey: sessionKey) { success in
            Logger.shared.logAlways("Last.fm: \(success ? "Scrobbled" : "Failed to scrobble") \(session.artist) - \(session.track)")
        }
    }

    func reset() { currentSession = nil; lastNowPlayingAt = nil }
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
    let baseColor: NSColor
    let background: NSColor
    let text: NSColor
    let textSecondary: NSColor
    let textTertiary: NSColor
    let buttonBackground: NSColor
    let buttonBackgroundHover: NSColor

    init(baseColor: NSColor, opacity: CGFloat) {
        self.baseColor = baseColor
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
    var onLastfmEnabledChange: ((Bool) -> Void)?
    var onLastfmConnect: (() -> Void)?
    var onLastfmDisconnect: (() -> Void)?
    var onAdaptiveColorsChange: ((Bool) -> Void)?

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
    private var lastfmHeaderLabel: NSTextField?
    private var lastfmEnabledCheckbox: NSButton?
    private var lastfmEnabledLabel: NSTextField?
    private var lastfmConnectButton: NSButton?
    private var adaptiveColorsCheckbox: NSButton?
    private var adaptiveColorsLabel: NSTextField?
    private var separator1: NSBox?
    private var separator2: NSBox?

    // Marquee animation
    private var scrollOffset: CGFloat = 0
    private var scrollTimer: Timer?
    private var scrollPauseCounter: Int = 0
    private let scrollSpeed: CGFloat = 0.5
    private let pauseFrames: Int = 60  // 2 seconds at 30 FPS

    static let settingsPanelHeight: CGFloat = 160

    var lastfmUsername: String = ""
    var lastfmConnected: Bool = false

    override var isFlipped: Bool { true }

    func setupSettingsControls(opacity: CGFloat, color: NSColor, launchOnLogin: Bool, showInDock: Bool, showInMenuBar: Bool, alwaysOnTop: Bool, lastfmEnabled: Bool = true, lastfmConnected: Bool = false, lastfmUsername: String = "", adaptiveColors: Bool = true) {
        self.lastfmUsername = lastfmUsername
        self.lastfmConnected = lastfmConnected
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
        launchOnLoginLabel = NSTextField(labelWithString: "Launch at login")
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
        alwaysOnTopLabel = NSTextField(labelWithString: "Always on top")
        alwaysOnTopLabel?.font = NSFont.systemFont(ofSize: 11)
        addSubview(alwaysOnTopLabel!)

        lastfmEnabledCheckbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(lastfmEnabledChanged))
        lastfmEnabledCheckbox?.state = lastfmEnabled ? .on : .off
        addSubview(lastfmEnabledCheckbox!)
        lastfmEnabledLabel = NSTextField(labelWithString: "Scrobble")
        lastfmEnabledLabel?.font = NSFont.systemFont(ofSize: 11)
        addSubview(lastfmEnabledLabel!)

        lastfmHeaderLabel = NSTextField(labelWithString: lastfmConnected ? "Last.FM as \(lastfmUsername)" : "Last.FM")
        lastfmHeaderLabel?.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        addSubview(lastfmHeaderLabel!)

        lastfmConnectButton = NSButton(title: lastfmConnected ? "Disconnect" : "Connect", target: self, action: #selector(lastfmConnectClicked))
        lastfmConnectButton?.bezelStyle = .rounded
        lastfmConnectButton?.font = NSFont.systemFont(ofSize: 11)
        addSubview(lastfmConnectButton!)

        adaptiveColorsCheckbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(adaptiveColorsChanged))
        adaptiveColorsCheckbox?.state = adaptiveColors ? .on : .off
        addSubview(adaptiveColorsCheckbox!)
        adaptiveColorsLabel = NSTextField(labelWithString: "Adaptive")
        adaptiveColorsLabel?.font = NSFont.systemFont(ofSize: 11)
        addSubview(adaptiveColorsLabel!)

        // Disable color picker when adaptive mode is on
        colorWell?.isEnabled = !adaptiveColors

        // Separators
        separator1 = NSBox()
        separator1?.boxType = .custom
        separator1?.borderWidth = 0
        addSubview(separator1!)
        separator2 = NSBox()
        separator2?.boxType = .custom
        separator2?.borderWidth = 0
        addSubview(separator2!)

        updateSettingsColors()
        updateSettingsControlsVisibility()
    }

    func updateLastfmStatus(connected: Bool, username: String) {
        self.lastfmConnected = connected
        self.lastfmUsername = username
        lastfmHeaderLabel?.stringValue = connected ? "Last.FM as \(username)" : "Last.FM"
        let title = connected ? "Disconnect" : "Connect"
        lastfmConnectButton?.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: colors.textSecondary,
            .font: NSFont.systemFont(ofSize: 11)
        ])
        setNeedsDisplay(bounds)
    }

    func updateLastfmEnabled(_ enabled: Bool) {
        lastfmEnabledCheckbox?.state = enabled ? .on : .off
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
        lastfmEnabledCheckbox?.isHidden = hidden
        lastfmEnabledLabel?.isHidden = hidden
        lastfmHeaderLabel?.isHidden = hidden
        lastfmConnectButton?.isHidden = hidden
        adaptiveColorsCheckbox?.isHidden = hidden
        adaptiveColorsLabel?.isHidden = hidden
        separator1?.isHidden = hidden
        separator2?.isHidden = hidden
    }

    func updateSettingsControlsLayout() {
        guard isSettingsExpanded else { return }
        let padding: CGFloat = 12
        let checkboxSize: CGFloat = 16
        let gap: CGFloat = 4
        let labelHeight: CGFloat = 16

        let baseY = bounds.height - PlayerView.settingsPanelHeight
        let row1Y = baseY + 16
        let sep1Y = baseY + 38
        let row2Y = baseY + 50
        let row2bY = baseY + 70
        let sep2Y = baseY + 92
        let row3Y = baseY + 104
        let row3bY = baseY + 128

        // Row 1: Appearance (Opacity, Color, Adaptive)
        opacityLabel?.frame = NSRect(x: padding, y: row1Y, width: 52, height: labelHeight)
        opacitySlider?.frame = NSRect(x: 64, y: row1Y, width: 100, height: labelHeight)
        colorWell?.frame = NSRect(x: 172, y: row1Y - 4, width: 44, height: 24)
        let adaptiveX: CGFloat = 224
        adaptiveColorsCheckbox?.frame = NSRect(x: adaptiveX, y: row1Y, width: checkboxSize, height: checkboxSize)
        adaptiveColorsLabel?.frame = NSRect(x: adaptiveX + checkboxSize + gap, y: row1Y, width: 70, height: labelHeight)

        separator1?.frame = NSRect(x: padding, y: sep1Y, width: bounds.width - padding * 2, height: 1)

        // Row 2: Window behavior (Always on top, Dock, Menu Bar, Launch at login)
        let col1: CGFloat = padding
        let col2: CGFloat = 200

        alwaysOnTopCheckbox?.frame = NSRect(x: col1, y: row2Y, width: checkboxSize, height: checkboxSize)
        alwaysOnTopLabel?.frame = NSRect(x: col1 + checkboxSize + gap, y: row2Y, width: 80, height: labelHeight)
        showInDockCheckbox?.frame = NSRect(x: col2, y: row2Y, width: checkboxSize, height: checkboxSize)
        showInDockLabel?.frame = NSRect(x: col2 + checkboxSize + gap, y: row2Y, width: 35, height: labelHeight)
        showInMenuBarCheckbox?.frame = NSRect(x: col1, y: row2bY, width: checkboxSize, height: checkboxSize)
        showInMenuBarLabel?.frame = NSRect(x: col1 + checkboxSize + gap, y: row2bY, width: 60, height: labelHeight)
        launchOnLoginCheckbox?.frame = NSRect(x: col2, y: row2bY, width: checkboxSize, height: checkboxSize)
        launchOnLoginLabel?.frame = NSRect(x: col2 + checkboxSize + gap, y: row2bY, width: 90, height: labelHeight)

        separator2?.frame = NSRect(x: padding, y: sep2Y, width: bounds.width - padding * 2, height: 1)

        // Row 3: Last.fm (Header, Connect button, Scrobble checkbox)
        lastfmHeaderLabel?.frame = NSRect(x: padding, y: row3Y, width: bounds.width - padding * 2, height: labelHeight)
        lastfmConnectButton?.frame = NSRect(x: padding, y: row3bY - 2, width: 80, height: 22)
        lastfmEnabledCheckbox?.frame = NSRect(x: col2, y: row3bY, width: checkboxSize, height: checkboxSize)
        lastfmEnabledLabel?.frame = NSRect(x: col2 + checkboxSize + gap, y: row3bY, width: 60, height: labelHeight)
    }

    func updateSettingsColors() {
        opacityLabel?.textColor = colors.textSecondary
        launchOnLoginLabel?.textColor = colors.textSecondary
        showInDockLabel?.textColor = colors.textSecondary
        showInMenuBarLabel?.textColor = colors.textSecondary
        alwaysOnTopLabel?.textColor = colors.textSecondary
        launchOnLoginCheckbox?.contentTintColor = colors.textSecondary
        showInDockCheckbox?.contentTintColor = colors.textSecondary
        showInMenuBarCheckbox?.contentTintColor = colors.textSecondary
        alwaysOnTopCheckbox?.contentTintColor = colors.textSecondary
        lastfmHeaderLabel?.textColor = colors.textSecondary
        if let button = lastfmConnectButton {
            let title = button.title
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .foregroundColor: colors.textSecondary,
                .font: NSFont.systemFont(ofSize: 11)
            ])
        }
        lastfmEnabledLabel?.textColor = colors.textSecondary
        lastfmEnabledCheckbox?.contentTintColor = colors.textSecondary
        adaptiveColorsLabel?.textColor = colors.textSecondary
        adaptiveColorsCheckbox?.contentTintColor = colors.text
        separator1?.fillColor = colors.buttonBackground
        separator2?.fillColor = colors.buttonBackground
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

    @objc private func lastfmEnabledChanged() {
        onLastfmEnabledChange?(lastfmEnabledCheckbox?.state == .on)
    }

    @objc private func lastfmConnectClicked() {
        if lastfmConnected { onLastfmDisconnect?() } else { onLastfmConnect?() }
    }

    @objc private func adaptiveColorsChanged() {
        let enabled = adaptiveColorsCheckbox?.state == .on
        colorWell?.isEnabled = !enabled
        onAdaptiveColorsChange?(enabled)
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
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
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
        let playerHeight: CGFloat = 50

        // First check custom drawn buttons in player area
        if point.y < playerHeight, let button = buttonAt(point: point) {
            switch button {
            case "prev": onPrevious?()
            case "play": onPlayPause?()
            case "next": onNext?()
            case "settings": onSettingsToggle?()
            case "fav": onFavorite?()
            case "quit": onQuit?()
            default: break
            }
            return
        }

        // Let interactive controls handle their own clicks
        if let hitView = hitTest(point),
           (hitView is NSButton || hitView is NSSlider || hitView is NSColorWell) {
            super.mouseDown(with: event)
            return
        }

        window?.performDrag(with: event)
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

        // Listen for Music.app track changes (event-driven, low energy)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(musicPlayerInfoChanged),
            name: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil
        )

        // Fallback timer for scrobble tick and edge cases (every 3 seconds)
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
            // Restore saved color
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
                self.config = Config.load()  // Reload to get the saved session key
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
        // Keep current base color (adaptive or manual)
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
        // Immediate update when Music.app sends track change notification
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

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
