import XCTest
@testable import Lurkr

final class LiveStatusTests: XCTestCase {
    private let stream = Stream(userLogin: "streamer", title: "", gameName: "", viewerCount: 0, uptime: "1 hour", thumbnailData: nil)
    private let favorites: Set<String> = ["streamer"]

    func testOnlyConfirmedOfflineToLiveTransitionsNotify() {
        var tracker = LiveStatusTracker()
        XCTAssertTrue(tracker.update(["streamer": .live(stream)], favorites: favorites).isEmpty)
        XCTAssertTrue(tracker.update(["streamer": .live(stream)], favorites: favorites).isEmpty)
        XCTAssertTrue(tracker.update(["streamer": .offline], favorites: favorites).isEmpty)
        XCTAssertEqual(tracker.update(["streamer": .live(stream)], favorites: favorites).map(\.userLogin), ["streamer"])
        XCTAssertTrue(tracker.update(["streamer": .live(stream)], favorites: favorites).isEmpty)
    }

    func testOutageRecoveryDoesNotInventAGoLiveTransition() {
        var tracker = LiveStatusTracker()
        _ = tracker.update(["streamer": .live(stream)], favorites: favorites)
        XCTAssertTrue(tracker.update(["streamer": .unknown], favorites: favorites).isEmpty)
        XCTAssertEqual(tracker.streams.map(\.userLogin), ["streamer"])
        XCTAssertEqual(tracker.streams.first?.uptime, stream.uptime)
        XCTAssertTrue(tracker.update(["streamer": .live(stream)], favorites: favorites).isEmpty)
    }

    func testFailedInitialCheckDoesNotLoseQuietBaseline() {
        var tracker = LiveStatusTracker()
        _ = tracker.update(["streamer": .unknown], favorites: favorites)
        XCTAssertTrue(tracker.update(["streamer": .live(stream)], favorites: favorites).isEmpty)
    }

    func testOfflineThenOutageThenLiveStillNotifies() {
        var tracker = LiveStatusTracker()
        _ = tracker.update(["streamer": .offline], favorites: favorites)
        _ = tracker.update(["streamer": .unknown], favorites: favorites)
        XCTAssertEqual(tracker.update(["streamer": .live(stream)], favorites: favorites).count, 1)
    }

    func testRemovedFavoritesDoNotNotifyAndReaddingStartsFresh() {
        var tracker = LiveStatusTracker()
        _ = tracker.update(["streamer": .offline], favorites: favorites)
        XCTAssertTrue(tracker.update(["streamer": .live(stream)], favorites: []).isEmpty)
        XCTAssertTrue(tracker.streams.isEmpty)
        XCTAssertTrue(tracker.update(["streamer": .live(stream)], favorites: favorites).isEmpty)
        _ = tracker.update([:], favorites: [])
        XCTAssertTrue(tracker.streams.isEmpty)
    }
}
