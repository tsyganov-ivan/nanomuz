import XCTest
import CommonCrypto

// Standalone implementation of signature generation for testing
func generateLastFMSignature(params: [String: String], apiSecret: String) -> String {
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

// Standalone playback session for testing state machine logic
struct TestPlaybackSession {
    let track: String
    let artist: String
    let album: String
    let startedAt: Date
    var lastResumedAt: Date?
    var accumulatedPlaySeconds: Double
    var scrobbled: Bool
    var durationSeconds: Int?

    var uniqueKey: String {
        "\(artist)|\(track)|\(album)|\(Int(startedAt.timeIntervalSince1970))"
    }
}

func shouldScrobble(session: TestPlaybackSession, totalPlayed: Double) -> Bool {
    guard let duration = session.durationSeconds, duration >= 30 else {
        return totalPlayed >= 240
    }
    let threshold = min(Double(duration) * 0.5, 240)
    return totalPlayed >= threshold
}

final class LastFMSignatureTests: XCTestCase {

    func testSignatureGenerationBasic() {
        let params: [String: String] = [
            "method": "auth.getToken",
            "api_key": "testkey123"
        ]
        let secret = "testsecret456"

        let signature = generateLastFMSignature(params: params, apiSecret: secret)

        // Verify the signature format (32 hex characters)
        XCTAssertEqual(signature.count, 32)
        XCTAssertTrue(signature.allSatisfy { $0.isHexDigit })
    }

    func testSignatureGenerationWithKnownValues() {
        // Known test case: signature should be deterministic
        let params: [String: String] = [
            "method": "track.scrobble",
            "api_key": "abc123",
            "artist": "Test Artist",
            "track": "Test Track",
            "timestamp": "1234567890",
            "sk": "session123"
        ]
        let secret = "secretkey"

        let signature1 = generateLastFMSignature(params: params, apiSecret: secret)
        let signature2 = generateLastFMSignature(params: params, apiSecret: secret)

        XCTAssertEqual(signature1, signature2, "Signature should be deterministic")
    }

    func testSignatureParameterOrdering() {
        // Parameters should be sorted alphabetically
        let params1: [String: String] = [
            "z_param": "last",
            "a_param": "first",
            "m_param": "middle"
        ]
        let params2: [String: String] = [
            "a_param": "first",
            "m_param": "middle",
            "z_param": "last"
        ]

        let sig1 = generateLastFMSignature(params: params1, apiSecret: "secret")
        let sig2 = generateLastFMSignature(params: params2, apiSecret: "secret")

        XCTAssertEqual(sig1, sig2, "Parameter order should not affect signature")
    }

    func testEmptyParameters() {
        let params: [String: String] = [:]
        let signature = generateLastFMSignature(params: params, apiSecret: "secret")

        XCTAssertEqual(signature.count, 32)
        XCTAssertTrue(signature.allSatisfy { $0.isHexDigit })
    }

    func testSpecialCharactersInValues() {
        let params: [String: String] = [
            "artist": "AC/DC",
            "track": "Back in Black (Live)"
        ]

        let signature = generateLastFMSignature(params: params, apiSecret: "secret")

        XCTAssertEqual(signature.count, 32)
    }

    func testUnicodeCharacters() {
        let params: [String: String] = [
            "artist": "Björk",
            "track": "Jóga"
        ]

        let signature = generateLastFMSignature(params: params, apiSecret: "secret")

        XCTAssertEqual(signature.count, 32)
    }
}

final class LastFMScrobbleStateMachineTests: XCTestCase {

    func testScrobbleRuleShortTrack() {
        // Tracks under 30 seconds should require 240 seconds of play
        var session = TestPlaybackSession(
            track: "Short Intro",
            artist: "Test",
            album: "Test Album",
            startedAt: Date(),
            lastResumedAt: nil,
            accumulatedPlaySeconds: 0,
            scrobbled: false,
            durationSeconds: 20 // Under 30 seconds
        )

        session.accumulatedPlaySeconds = 100
        XCTAssertFalse(shouldScrobble(session: session, totalPlayed: 100))

        session.accumulatedPlaySeconds = 240
        XCTAssertTrue(shouldScrobble(session: session, totalPlayed: 240))
    }

    func testScrobbleRuleNormalTrack() {
        // Normal track: scrobble at 50% or 4 minutes
        var session = TestPlaybackSession(
            track: "Normal Song",
            artist: "Test",
            album: "Test Album",
            startedAt: Date(),
            lastResumedAt: nil,
            accumulatedPlaySeconds: 0,
            scrobbled: false,
            durationSeconds: 180 // 3 minutes
        )

        // 50% of 180 = 90 seconds
        session.accumulatedPlaySeconds = 80
        XCTAssertFalse(shouldScrobble(session: session, totalPlayed: 80))

        session.accumulatedPlaySeconds = 90
        XCTAssertTrue(shouldScrobble(session: session, totalPlayed: 90))
    }

    func testScrobbleRuleLongTrack() {
        // Long track: cap at 4 minutes regardless of duration
        var session = TestPlaybackSession(
            track: "Epic Symphony",
            artist: "Test",
            album: "Test Album",
            startedAt: Date(),
            lastResumedAt: nil,
            accumulatedPlaySeconds: 0,
            scrobbled: false,
            durationSeconds: 600 // 10 minutes
        )

        // 50% of 600 = 300, but cap is 240
        session.accumulatedPlaySeconds = 230
        XCTAssertFalse(shouldScrobble(session: session, totalPlayed: 230))

        session.accumulatedPlaySeconds = 240
        XCTAssertTrue(shouldScrobble(session: session, totalPlayed: 240))
    }

    func testScrobbleRuleExactly30Seconds() {
        // Track exactly 30 seconds should use 50% rule
        var session = TestPlaybackSession(
            track: "Short Song",
            artist: "Test",
            album: "Test Album",
            startedAt: Date(),
            lastResumedAt: nil,
            accumulatedPlaySeconds: 0,
            scrobbled: false,
            durationSeconds: 30
        )

        session.accumulatedPlaySeconds = 14
        XCTAssertFalse(shouldScrobble(session: session, totalPlayed: 14))

        session.accumulatedPlaySeconds = 15
        XCTAssertTrue(shouldScrobble(session: session, totalPlayed: 15))
    }

    func testScrobbleRuleUnknownDuration() {
        // Unknown duration should fall back to 240 seconds
        var session = TestPlaybackSession(
            track: "Unknown Duration",
            artist: "Test",
            album: "Test Album",
            startedAt: Date(),
            lastResumedAt: nil,
            accumulatedPlaySeconds: 0,
            scrobbled: false,
            durationSeconds: nil
        )

        session.accumulatedPlaySeconds = 200
        XCTAssertFalse(shouldScrobble(session: session, totalPlayed: 200))

        session.accumulatedPlaySeconds = 240
        XCTAssertTrue(shouldScrobble(session: session, totalPlayed: 240))
    }

    func testUniqueKeyGeneration() {
        let timestamp = Date(timeIntervalSince1970: 1704067200) // 2024-01-01 00:00:00 UTC

        let session = TestPlaybackSession(
            track: "Test Track",
            artist: "Test Artist",
            album: "Test Album",
            startedAt: timestamp,
            lastResumedAt: nil,
            accumulatedPlaySeconds: 0,
            scrobbled: false,
            durationSeconds: 180
        )

        XCTAssertEqual(session.uniqueKey, "Test Artist|Test Track|Test Album|1704067200")
    }

    func testDuplicateSessionDetection() {
        let timestamp = Date()

        let session1 = TestPlaybackSession(
            track: "Same Track",
            artist: "Same Artist",
            album: "Same Album",
            startedAt: timestamp,
            lastResumedAt: nil,
            accumulatedPlaySeconds: 0,
            scrobbled: false,
            durationSeconds: 180
        )

        let session2 = TestPlaybackSession(
            track: "Same Track",
            artist: "Same Artist",
            album: "Same Album",
            startedAt: timestamp,
            lastResumedAt: nil,
            accumulatedPlaySeconds: 0,
            scrobbled: false,
            durationSeconds: 180
        )

        XCTAssertEqual(session1.uniqueKey, session2.uniqueKey)
    }

    func testDifferentTracksHaveDifferentKeys() {
        let timestamp = Date()

        let session1 = TestPlaybackSession(
            track: "Track 1",
            artist: "Artist",
            album: "Album",
            startedAt: timestamp,
            lastResumedAt: nil,
            accumulatedPlaySeconds: 0,
            scrobbled: false,
            durationSeconds: 180
        )

        let session2 = TestPlaybackSession(
            track: "Track 2",
            artist: "Artist",
            album: "Album",
            startedAt: timestamp,
            lastResumedAt: nil,
            accumulatedPlaySeconds: 0,
            scrobbled: false,
            durationSeconds: 180
        )

        XCTAssertNotEqual(session1.uniqueKey, session2.uniqueKey)
    }

    func testAccumulatedPlayTimeWithPauses() {
        var session = TestPlaybackSession(
            track: "Test",
            artist: "Test",
            album: "Test",
            startedAt: Date(),
            lastResumedAt: Date(),
            accumulatedPlaySeconds: 0,
            scrobbled: false,
            durationSeconds: 180
        )

        // Simulate play for 30 seconds
        session.accumulatedPlaySeconds = 30
        session.lastResumedAt = nil // Paused

        // Resume and play for 30 more
        session.lastResumedAt = Date()
        session.accumulatedPlaySeconds = 60

        // Total 60 seconds played
        XCTAssertFalse(shouldScrobble(session: session, totalPlayed: 60))

        // Play 30 more to reach 90 (50% of 180)
        session.accumulatedPlaySeconds = 90
        XCTAssertTrue(shouldScrobble(session: session, totalPlayed: 90))
    }
}
