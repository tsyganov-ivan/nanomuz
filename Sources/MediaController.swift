import Foundation

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

    private var _cachedArtwork: Data?
    private let artworkLock = NSLock()
    var cachedArtwork: Data? {
        get {
            artworkLock.lock()
            defer { artworkLock.unlock() }
            return _cachedArtwork
        }
        set {
            artworkLock.lock()
            defer { artworkLock.unlock() }
            _cachedArtwork = newValue
        }
    }

    private var _cachedInfo: NowPlayingInfo?
    private let infoLock = NSLock()
    var cachedInfo: NowPlayingInfo? {
        get {
            infoLock.lock()
            defer { infoLock.unlock() }
            return _cachedInfo
        }
        set {
            infoLock.lock()
            defer { infoLock.unlock() }
            _cachedInfo = newValue
        }
    }

    private let scriptQueue = DispatchQueue(label: "com.nanomuz.scripts", qos: .userInitiated)
    private let artworkQueue = DispatchQueue(label: "com.nanomuz.artwork", qos: .userInitiated)

    private var _currentArtworkRequestId: UUID?
    private let requestIdLock = NSLock()
    private var currentArtworkRequestId: UUID? {
        get {
            requestIdLock.lock()
            defer { requestIdLock.unlock() }
            return _currentArtworkRequestId
        }
        set {
            requestIdLock.lock()
            defer { requestIdLock.unlock() }
            _currentArtworkRequestId = newValue
        }
    }

    private init() {}

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

    func fetchArtwork(completion: @escaping () -> Void) {
        let requestId = UUID()
        currentArtworkRequestId = requestId

        guard let info = cachedInfo else {
            Logger.shared.log("fetchArtwork: No track info", key: "no_track_info")
            cachedArtwork = nil
            completion()
            return
        }

        if let urlString = info.artworkUrl, let url = URL(string: urlString) {
            fetchArtworkFromURL(url: url, requestId: requestId, title: info.title) { [weak self] data in
                guard let self = self else {
                    completion()
                    return
                }

                if self.currentArtworkRequestId != requestId {
                    Logger.shared.log("fetchArtwork: Stale request ignored", key: "artwork_stale")
                    completion()
                    return
                }

                if let data = data {
                    self.cachedArtwork = data
                    Logger.shared.log("fetchArtwork: Loaded \(data.count) bytes from URL for '\(info.title)'", key: "artwork_url_\(info.title)")
                    completion()
                } else {
                    Logger.shared.log("fetchArtwork: Trying AppleScript fallback for '\(info.title)'", key: "artwork_as_try_\(info.title)")
                    self.fetchArtworkFromMusicApp(requestId: requestId, completion: completion)
                }
            }
        } else {
            Logger.shared.log("fetchArtwork: Trying AppleScript fallback for '\(info.title)'", key: "artwork_as_try_\(info.title)")
            fetchArtworkFromMusicApp(requestId: requestId, completion: completion)
        }
    }

    private func fetchArtworkFromURL(url: URL, requestId: UUID, title: String, completion: @escaping (Data?) -> Void) {
        artworkQueue.async {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30

            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else {
                    completion(nil)
                    return
                }

                if self.currentArtworkRequestId != requestId {
                    Logger.shared.log("fetchArtworkFromURL: Stale request ignored", key: "artwork_url_stale")
                    completion(nil)
                    return
                }

                if let error = error {
                    Logger.shared.log("fetchArtworkFromURL: Failed for '\(title)': \(error.localizedDescription)", key: "artwork_url_fail_\(title)")
                    completion(nil)
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    Logger.shared.log("fetchArtworkFromURL: HTTP \(httpResponse.statusCode) for '\(title)'", key: "artwork_url_http_\(title)")
                    completion(nil)
                    return
                }

                completion(data)
            }.resume()
        }
    }

    private func fetchArtworkFromMusicApp(requestId: UUID, completion: @escaping () -> Void) {
        scriptQueue.async { [weak self] in
            guard let self = self else {
                completion()
                return
            }

            if self.currentArtworkRequestId != requestId {
                Logger.shared.log("fetchArtworkFromMusicApp: Stale request ignored", key: "artwork_as_stale")
                completion()
                return
            }

            let tempPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("nanomuz_artwork_\(UUID().uuidString).tmp")
                .path
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

                if self.currentArtworkRequestId != requestId {
                    Logger.shared.log("fetchArtworkFromMusicApp: Stale request after AppleScript", key: "artwork_as_stale_post")
                    completion()
                    return
                }

                let output = pipe.fileHandleForReading.readDataToEndOfFile()
                let result = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if result == tempPath {
                    let fileURL = URL(fileURLWithPath: tempPath)
                    let imageData = try Data(contentsOf: fileURL)
                    self.cachedArtwork = imageData
                    try? FileManager.default.removeItem(at: fileURL)
                    Logger.shared.log("fetchArtwork: Loaded \(imageData.count) bytes from Music app", key: "artwork_as_success")
                } else if result.hasPrefix("error:") {
                    Logger.shared.log("fetchArtwork: AppleScript error: \(result)", key: "artwork_as_error")
                    self.cachedArtwork = nil
                    try? FileManager.default.removeItem(atPath: tempPath)
                } else {
                    Logger.shared.log("fetchArtwork: No artwork in Music app (result: \(result))", key: "artwork_as_none")
                    self.cachedArtwork = nil
                    try? FileManager.default.removeItem(atPath: tempPath)
                }
            } catch {
                Logger.shared.logAlways("fetchArtwork: AppleScript execution failed: \(error.localizedDescription)")
                self.cachedArtwork = nil
                try? FileManager.default.removeItem(atPath: tempPath)
            }

            completion()
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
        guard var info = cachedInfo else {
            completion?()
            return
        }
        let newState = !info.isFavorited
        info.isFavorited = newState
        cachedInfo = info
        completion?()
        runAppleScriptAsync("tell application \"Music\" to set favorited of current track to \(newState)") { _ in }
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
