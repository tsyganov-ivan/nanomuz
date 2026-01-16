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

    var cachedArtwork: Data?
    var cachedInfo: NowPlayingInfo?

    private let scriptQueue = DispatchQueue(label: "com.nanomuz.scripts", qos: .userInitiated)

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

    func fetchArtwork() {
        guard let info = cachedInfo else {
            Logger.shared.log("fetchArtwork: No track info", key: "no_track_info")
            cachedArtwork = nil
            return
        }

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
