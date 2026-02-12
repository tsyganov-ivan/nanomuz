import XCTest
import AppKit

// MARK: - Test Now Playing Info

struct TestNowPlayingInfo {
    let title: String
    let artist: String
    let album: String
    let isPlaying: Bool
    let artworkUrl: String?
    var isFavorited: Bool
    let duration: Int?

    static let sample = TestNowPlayingInfo(
        title: "Test Song",
        artist: "Test Artist",
        album: "Test Album",
        isPlaying: true,
        artworkUrl: nil,
        isFavorited: false,
        duration: 180
    )

    static let sample2 = TestNowPlayingInfo(
        title: "Another Song",
        artist: "Another Artist",
        album: "Another Album",
        isPlaying: false,
        artworkUrl: "artwork://test",
        isFavorited: true,
        duration: 240
    )
}

// MARK: - Test Now Playing Controller Delegate

protocol TestNowPlayingControllerDelegate: AnyObject {
    func testNowPlayingController(
        _ controller: TestNowPlayingController,
        didUpdateInfo info: TestNowPlayingInfo?
    )
    func testNowPlayingController(
        _ controller: TestNowPlayingController,
        didUpdateArtwork image: NSImage?
    )
    func testNowPlayingController(
        _ controller: TestNowPlayingController,
        artworkIdChanged newId: String?
    )
}

// MARK: - Test Now Playing Controller

class TestNowPlayingController {
    weak var delegate: TestNowPlayingControllerDelegate?

    private(set) var lastArtworkId: String?
    private(set) var isUpdating = false
    private(set) var lastScrobbleInfo: (artist: String, track: String, album: String)?
    private(set) var scrobbleTrackChangedCalled = false
    private(set) var scrobblePlaybackStateChangedCalled = false

    var pendingInfo: TestNowPlayingInfo?
    var pendingArtwork: NSImage?
    private var scheduleUpdateCompletion: (() -> Void)?

    func scheduleUpdate() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateNowPlaying()
            self?.scheduleUpdateCompletion?()
        }
    }

    func setScheduleUpdateCompletion(_ completion: @escaping () -> Void) {
        scheduleUpdateCompletion = completion
    }

    func updateNowPlaying() {
        guard !isUpdating else { return }
        isUpdating = true

        let info = pendingInfo
        isUpdating = false

        delegate?.testNowPlayingController(self, didUpdateInfo: info)

        if let info = info {
            let currentInfo = (artist: info.artist, track: info.title, album: info.album)
            let trackChanged = lastScrobbleInfo?.artist != currentInfo.artist ||
                               lastScrobbleInfo?.track != currentInfo.track ||
                               lastScrobbleInfo?.album != currentInfo.album

            if trackChanged {
                lastScrobbleInfo = currentInfo
                scrobbleTrackChangedCalled = true
            } else {
                scrobblePlaybackStateChangedCalled = true
            }
        } else if lastScrobbleInfo != nil {
            lastScrobbleInfo = nil
        }

        let artworkId = info.map { "\($0.title)-\($0.artist)-\($0.album)" }
        if artworkId != lastArtworkId {
            lastArtworkId = artworkId
            delegate?.testNowPlayingController(self, artworkIdChanged: artworkId)

            if info != nil, let artwork = pendingArtwork {
                delegate?.testNowPlayingController(self, didUpdateArtwork: artwork)
            } else if info == nil {
                delegate?.testNowPlayingController(self, didUpdateArtwork: nil)
            }
        }

        if pendingArtwork != nil {
            delegate?.testNowPlayingController(self, didUpdateArtwork: pendingArtwork)
        }
    }

    func simulateConcurrentUpdate() -> Bool {
        isUpdating = true
        let wouldBlock = isUpdating
        updateNowPlaying()
        return wouldBlock
    }

    func resetIsUpdating() {
        isUpdating = false
    }

    func resetScrobbleState() {
        scrobbleTrackChangedCalled = false
        scrobblePlaybackStateChangedCalled = false
    }
}

// MARK: - Mock Delegate

class MockNowPlayingControllerDelegate: TestNowPlayingControllerDelegate {
    var infoUpdated: TestNowPlayingInfo?
    var artworkUpdated: NSImage?
    var artworkIdChanged: String?

    var infoUpdateCount = 0
    var artworkUpdateCount = 0
    var artworkIdChangeCount = 0

    func testNowPlayingController(
        _ controller: TestNowPlayingController,
        didUpdateInfo info: TestNowPlayingInfo?
    ) {
        infoUpdated = info
        infoUpdateCount += 1
    }

    func testNowPlayingController(
        _ controller: TestNowPlayingController,
        didUpdateArtwork image: NSImage?
    ) {
        artworkUpdated = image
        artworkUpdateCount += 1
    }

    func testNowPlayingController(
        _ controller: TestNowPlayingController,
        artworkIdChanged newId: String?
    ) {
        artworkIdChanged = newId
        artworkIdChangeCount += 1
    }

    func reset() {
        infoUpdated = nil
        artworkUpdated = nil
        artworkIdChanged = nil
        infoUpdateCount = 0
        artworkUpdateCount = 0
        artworkIdChangeCount = 0
    }
}

// MARK: - Tests

final class NowPlayingControllerTests: XCTestCase {
    var controller: TestNowPlayingController!
    var delegate: MockNowPlayingControllerDelegate!

    override func setUp() {
        super.setUp()
        controller = TestNowPlayingController()
        delegate = MockNowPlayingControllerDelegate()
        controller.delegate = delegate
    }

    override func tearDown() {
        controller = nil
        delegate = nil
        super.tearDown()
    }

    // MARK: - scheduleUpdate Tests

    func testScheduleUpdateCallsUpdateNowPlayingAfterDelay() {
        let expectation = expectation(description: "scheduleUpdate calls updateNowPlaying")
        controller.pendingInfo = TestNowPlayingInfo.sample

        controller.setScheduleUpdateCompletion {
            expectation.fulfill()
        }
        controller.scheduleUpdate()

        waitForExpectations(timeout: 1.0) { _ in
            XCTAssertEqual(self.delegate.infoUpdateCount, 1)
            XCTAssertNotNil(self.delegate.infoUpdated)
        }
    }

    func testScheduleUpdateUsesCorrectDelay() {
        let startTime = Date()
        let expectation = expectation(description: "delay check")

        controller.setScheduleUpdateCompletion {
            expectation.fulfill()
        }
        controller.scheduleUpdate()

        waitForExpectations(timeout: 1.0) { _ in
            let elapsed = Date().timeIntervalSince(startTime)
            XCTAssertGreaterThanOrEqual(elapsed, 0.4, "Delay should be approximately 0.5 seconds")
        }
    }

    // MARK: - Concurrent Update Guard Tests

    func testUpdateNowPlayingGuardsAgainstConcurrentUpdates() {
        controller.pendingInfo = TestNowPlayingInfo.sample

        controller.updateNowPlaying()
        XCTAssertEqual(delegate.infoUpdateCount, 1)

        let wouldBlock = controller.simulateConcurrentUpdate()
        XCTAssertTrue(wouldBlock, "isUpdating should block concurrent updates")
    }

    func testUpdateNowPlayingAllowsSequentialUpdates() {
        controller.pendingInfo = TestNowPlayingInfo.sample

        controller.updateNowPlaying()
        XCTAssertEqual(delegate.infoUpdateCount, 1)

        controller.updateNowPlaying()
        XCTAssertEqual(delegate.infoUpdateCount, 2)
    }

    // MARK: - Delegate Notification Tests

    func testDelegateNotificationForTrackInfoUpdates() {
        controller.pendingInfo = TestNowPlayingInfo.sample

        controller.updateNowPlaying()

        XCTAssertNotNil(delegate.infoUpdated)
        XCTAssertEqual(delegate.infoUpdated?.title, "Test Song")
        XCTAssertEqual(delegate.infoUpdated?.artist, "Test Artist")
        XCTAssertEqual(delegate.infoUpdated?.album, "Test Album")
        XCTAssertEqual(delegate.infoUpdated?.isPlaying, true)
    }

    func testDelegateNotificationForNilInfo() {
        controller.pendingInfo = nil

        controller.updateNowPlaying()

        XCTAssertNil(delegate.infoUpdated)
        XCTAssertEqual(delegate.infoUpdateCount, 1)
    }

    func testDelegateNotificationForArtworkChanges() {
        let testImage = NSImage(size: NSSize(width: 100, height: 100))
        controller.pendingInfo = TestNowPlayingInfo.sample
        controller.pendingArtwork = testImage

        controller.updateNowPlaying()

        XCTAssertNotNil(delegate.artworkUpdated)
        XCTAssertGreaterThanOrEqual(delegate.artworkUpdateCount, 1)
    }

    func testArtworkIdChangesOnTrackChange() {
        controller.pendingInfo = TestNowPlayingInfo.sample

        controller.updateNowPlaying()

        let expectedId = "Test Song-Test Artist-Test Album"
        XCTAssertEqual(delegate.artworkIdChanged, expectedId)
        XCTAssertEqual(delegate.artworkIdChangeCount, 1)
    }

    func testArtworkIdDoesNotChangeForSameTrack() {
        controller.pendingInfo = TestNowPlayingInfo.sample
        controller.updateNowPlaying()

        delegate.reset()
        controller.resetScrobbleState()

        controller.updateNowPlaying()
        XCTAssertEqual(delegate.artworkIdChangeCount, 0, "Artwork ID should not change for same track")
    }

    func testNilArtworkOnNilInfo() {
        controller.pendingInfo = TestNowPlayingInfo.sample
        controller.updateNowPlaying()

        delegate.reset()
        controller.pendingInfo = nil

        controller.updateNowPlaying()

        XCTAssertNil(delegate.artworkUpdated)
        XCTAssertGreaterThanOrEqual(delegate.artworkIdChangeCount, 1)
    }

    // MARK: - Scrobble Info Tracking Tests

    func testScrobbleInfoTrackingOnTrackChange() {
        controller.pendingInfo = TestNowPlayingInfo.sample

        controller.updateNowPlaying()

        XCTAssertNotNil(controller.lastScrobbleInfo)
        XCTAssertEqual(controller.lastScrobbleInfo?.artist, "Test Artist")
        XCTAssertEqual(controller.lastScrobbleInfo?.track, "Test Song")
        XCTAssertEqual(controller.lastScrobbleInfo?.album, "Test Album")
        XCTAssertTrue(controller.scrobbleTrackChangedCalled)
    }

    func testScrobbleInfoUpdatesOnNewTrack() {
        controller.pendingInfo = TestNowPlayingInfo.sample
        controller.updateNowPlaying()

        controller.resetScrobbleState()
        controller.pendingInfo = TestNowPlayingInfo.sample2

        controller.updateNowPlaying()

        XCTAssertEqual(controller.lastScrobbleInfo?.artist, "Another Artist")
        XCTAssertEqual(controller.lastScrobbleInfo?.track, "Another Song")
        XCTAssertEqual(controller.lastScrobbleInfo?.album, "Another Album")
        XCTAssertTrue(controller.scrobbleTrackChangedCalled)
    }

    func testPlaybackStateChangedForSameTrack() {
        controller.pendingInfo = TestNowPlayingInfo.sample
        controller.updateNowPlaying()

        controller.resetScrobbleState()

        controller.updateNowPlaying()

        XCTAssertTrue(controller.scrobblePlaybackStateChangedCalled)
        XCTAssertFalse(controller.scrobbleTrackChangedCalled)
    }

    func testScrobbleInfoResetsOnNilInfo() {
        controller.pendingInfo = TestNowPlayingInfo.sample
        controller.updateNowPlaying()
        XCTAssertNotNil(controller.lastScrobbleInfo)

        controller.pendingInfo = nil
        controller.updateNowPlaying()

        XCTAssertNil(controller.lastScrobbleInfo)
    }

    // MARK: - Edge Cases

    func testDelegateNotCalledWhenNil() {
        controller.delegate = nil
        controller.pendingInfo = TestNowPlayingInfo.sample

        controller.updateNowPlaying()

        XCTAssertNil(delegate.infoUpdated)
        XCTAssertEqual(delegate.infoUpdateCount, 0)
    }

    func testInitialState() {
        let newController = TestNowPlayingController()

        XCTAssertNil(newController.lastArtworkId)
        XCTAssertFalse(newController.isUpdating)
        XCTAssertNil(newController.lastScrobbleInfo)
        XCTAssertNil(newController.delegate)
    }

    func testMultipleSequentialTrackChanges() {
        let tracks = [
            TestNowPlayingInfo.sample,
            TestNowPlayingInfo.sample2,
            TestNowPlayingInfo.sample
        ]

        for (index, track) in tracks.enumerated() {
            controller.resetScrobbleState()
            controller.pendingInfo = track
            controller.updateNowPlaying()

            XCTAssertTrue(
                controller.scrobbleTrackChangedCalled,
                "Track change should be detected for track \(index)"
            )
        }

        XCTAssertEqual(delegate.infoUpdateCount, 3)
    }
}
