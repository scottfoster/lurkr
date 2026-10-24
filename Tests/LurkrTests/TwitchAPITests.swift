import XCTest
@testable import Lurkr

final class TwitchAPITests: XCTestCase {
    private func api(responses: [String: StubResponse]) -> TwitchAPI {
        StubURLProtocol.configure(responses)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return TwitchAPI(session: URLSession(configuration: config))
    }

    func testOnlyValidUptimeResponsesAreLive() async {
        let uptimes = ["0 seconds", "1 minute, 2 seconds", "2 hours, 53 minutes, 33 seconds",
                       "1 day, 3 hours, 5 minutes, 0 seconds", "1 week, 2 days", "2 months, 3 weeks", "1 year, 1 month"]
        let responses = Dictionary(uniqueKeysWithValues: uptimes.enumerated().map {
            ("/twitch/uptime/user\($0.offset)", StubResponse.http(200, $0.element))
        })
        let result = await api(responses: responses).liveStreams(logins: uptimes.indices.map { "user\($0)" })
        XCTAssertEqual(result.count, uptimes.count)
        for status in result.values {
            guard case .live(let stream) = status else { return XCTFail("Valid uptime must be live") }
            // Missing metadata or thumbnails must not erase a confirmed live status.
            XCTAssertEqual(stream.title, "")
            XCTAssertEqual(stream.viewerCount, 0)
        }
    }

    func testOfflineIsDistinctFromFailedAndMalformedChecks() async {
        let api = api(responses: [
            "/twitch/uptime/offline": .http(200, " Offline is offline.\n"),
            "/twitch/uptime/servererror": .http(503, "Unavailable"),
            "/twitch/uptime/ratelimited": .http(429, "Rate limited"),
            "/twitch/uptime/transport": .failure,
            "/twitch/uptime/proxyerror": .http(200, "[decapi] needs to authenticate"),
            "/twitch/uptime/html": .http(200, "<html>Error</html>"),
            "/twitch/uptime/empty": .http(200, ""),
            "/twitch/uptime/notfound": .http(200, "User not found: notfound"),
        ])
        let unknown = ["servererror", "ratelimited", "transport", "proxyerror", "html", "empty", "notfound"]
        let result = await api.liveStreams(logins: ["offline"] + unknown)
        guard case .offline = result["offline"] else { return XCTFail("Expected confirmed offline") }
        for login in unknown {
            guard case .unknown = result[login] else { return XCTFail("\(login) is unknown, not offline or live") }
        }
    }

    func testPartialFailuresKeepOtherStatusesAndNormalizeDuplicateLogins() async {
        let result = await api(responses: [
            "/twitch/uptime/live": .http(200, "1 hour"),
            "/twitch/title/live": .http(200, "Playing chess"),
            "/twitch/game/live": .http(200, "Chess"),
            "/twitch/viewercount/live": .http(200, "1900"),
            "/twitch/uptime/offline": .http(200, "offline is offline"),
            "/twitch/uptime/unknown": .failure,
        ]).liveStreams(logins: ["LIVE", "live", "offline", "unknown"])
        XCTAssertEqual(result.count, 3)
        guard case .live(let stream) = result["live"] else { return XCTFail("Live result lost") }
        XCTAssertEqual(stream.gameName, "Chess")
        XCTAssertEqual(stream.viewerCount, 1900)
        guard case .offline = result["offline"] else { return XCTFail("Offline result lost") }
        guard case .unknown = result["unknown"] else { return XCTFail("Unknown result lost") }
    }
}

private enum StubResponse {
    case http(Int, String)
    case failure
}

private final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responses: [String: StubResponse] = [:]

    static func configure(_ responses: [String: StubResponse]) {
        lock.lock()
        defer { lock.unlock() }
        self.responses = responses
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock()
        let response = Self.responses[url.path] ?? .http(404, "")
        Self.lock.unlock()
        switch response {
        case .failure:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .http(let code, let body):
            let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
