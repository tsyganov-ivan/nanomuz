import AppKit

class NowPlayingController: NowPlayingControllerProtocol {
    weak var delegate: NowPlayingControllerDelegate?

    private(set) var lastArtworkId: String?
    private(set) var isUpdating = false

    private var updateTimer: Timer?
    private var lastScrobbleInfo: (artist: String, track: String, album: String)?

    func startUpdates() {
        updateNowPlaying()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(musicPlayerInfoChanged),
            name: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil
        )

        updateTimer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.updateNowPlaying()
        }
        if let timer = updateTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stopUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
        DistributedNotificationCenter.default().removeObserver(self)
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
                self.delegate?.nowPlayingController(self, didUpdateInfo: info)

                if let info = info {
                    let currentInfo = (artist: info.artist, track: info.title, album: info.album)
                    let trackChanged = self.lastScrobbleInfo?.artist != currentInfo.artist ||
                                       self.lastScrobbleInfo?.track != currentInfo.track ||
                                       self.lastScrobbleInfo?.album != currentInfo.album

                    if trackChanged {
                        self.lastScrobbleInfo = currentInfo
                        LastFMScrobbleService.shared.trackChanged(
                            artist: info.artist,
                            track: info.title,
                            album: info.album,
                            isPlaying: info.isPlaying,
                            durationSeconds: info.duration
                        )
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
                    self.delegate?.nowPlayingController(self, artworkIdChanged: artworkId)
                    MediaController.shared.cachedArtwork = nil

                    if info != nil {
                        MediaController.shared.fetchArtwork { [weak self] in
                            DispatchQueue.main.async {
                                guard let self = self else { return }
                                if let data = MediaController.shared.cachedArtwork,
                                   let image = NSImage(data: data) {
                                    self.delegate?.nowPlayingController(self, didUpdateArtwork: image)
                                }
                            }
                        }
                    } else {
                        self.delegate?.nowPlayingController(self, didUpdateArtwork: nil)
                    }
                }

            }
        }
    }

    @objc private func musicPlayerInfoChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateNowPlaying()
        }
    }

    deinit {
        stopUpdates()
    }
}
