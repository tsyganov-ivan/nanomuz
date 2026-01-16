import AppKit
import CommonCrypto

// MARK: - Last.fm Session Store

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

    private let apiKey = Secrets.lastfmApiKey
    private let apiSecret = Secrets.lastfmApiSecret
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
