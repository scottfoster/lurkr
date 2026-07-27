import Foundation

struct Stream: Sendable {
    let userLogin: String
    let title: String
    let gameName: String
    let viewerCount: Int
    let uptime: String
    let thumbnailData: Data?
}

/// Uses decapi.me, a free public proxy in front of Twitch's API. No auth required.
/// Endpoints used:
///   - https://decapi.me/twitch/uptime/<login>       → "Xh Ym" or "<user> is offline" or "User not found"
///   - https://decapi.me/twitch/title/<login>        → stream title (string)
///   - https://decapi.me/twitch/game/<login>         → game name (string)
///   - https://decapi.me/twitch/viewercount/<login>  → integer
actor TwitchAPI {
    private let session: URLSession
    private var networkAttempts: Int = 0
    private var networkFailures: Int = 0
    private(set) var lastCallHadConnectionError: Bool = false

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: cfg)
    }

    func liveStreams(logins: [String]) async -> [Stream] {
        networkAttempts = 0
        networkFailures = 0

        guard !logins.isEmpty else {
            lastCallHadConnectionError = false
            return []
        }
        let result = await withTaskGroup(of: Stream?.self) { group in
            for login in logins {
                group.addTask { await self.fetchIfLive(login: login) }
            }
            var out: [Stream] = []
            for await s in group {
                if let s { out.append(s) }
            }
            return out
        }
        // If >50% of network attempts failed, treat decapi as unreachable.
        let failRate = networkAttempts > 0 ? Double(networkFailures) / Double(networkAttempts) : 0
        lastCallHadConnectionError = networkAttempts > 0 && failRate >= 0.5
        return result
    }

    /// Returns true if a user with this login exists on Twitch.
    /// decapi's `/id/<login>` returns a numeric user ID for real users and
    /// "User not found: <login>" otherwise — `/uptime/` can't distinguish
    /// offline vs. nonexistent (both render as "<login> is offline").
    func userExists(login: String) async -> Bool {
        guard let raw = await fetchText(path: "id/\(login)") else { return false }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(trimmed) != nil
    }

    private func fetchIfLive(login: String) async -> Stream? {
        guard let uptimeRaw = await fetchText(path: "uptime/\(login)") else { return nil }
        let uptime = uptimeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = uptime.lowercased()
        if lower.contains("offline") || lower.contains("not found") || uptime.isEmpty {
            return nil
        }

        async let title = fetchText(path: "title/\(login)")
        async let game = fetchText(path: "game/\(login)")
        async let viewers = fetchText(path: "viewercount/\(login)")
        async let thumb = fetchThumbnail(login: login)

        let titleStr = Self.sanitize(await title)
        let gameStr = Self.sanitize(await game)
        let viewerStr = Self.sanitize(await viewers)
        let viewerCount = Int(viewerStr) ?? 0
        let thumbData = await thumb

        return Stream(
            userLogin: login,
            title: titleStr,
            gameName: gameStr,
            viewerCount: viewerCount,
            uptime: uptime,
            thumbnailData: thumbData
        )
    }

    private func fetchThumbnail(login: String) async -> Data? {
        guard let url = URL(string: "https://static-cdn.jtvnw.net/previews-ttv/live_user_\(login)-160x90.jpg") else { return nil }
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return data
        } catch {
            // Thumbnail failures are common (offline streamers, CDN flakes); don't count against decapi connectivity.
            return nil
        }
    }

    private func fetchText(path: String) async -> String? {
        guard let escaped = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://decapi.me/twitch/\(escaped)") else { return nil }
        networkAttempts += 1
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse else {
                networkFailures += 1
                return nil
            }
            // 5xx = decapi having problems; count as connection failure.
            if http.statusCode >= 500 { networkFailures += 1 }
            guard http.statusCode == 200 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            networkFailures += 1
            return nil
        }
    }

    /// Best-effort "last live date" for an offline streamer.
    /// 1) decapi's `/videos/<login>` gives us the latest VOD URL (no date).
    /// 2) Fetching that VOD page gives us `<meta property="og:video:release_date" content="…Z"/>`.
    /// Returns nil if anything fails or the user has no VODs.
    func lastStreamDate(login: String) async -> Date? {
        guard let videoLine = await fetchText(path: "videos/\(login)") else { return nil }
        let sanitized = Self.sanitize(videoLine)
        guard !sanitized.isEmpty else { return nil }
        guard let vodURL = Self.extractVODURL(from: sanitized) else { return nil }
        guard let html = await fetchURL(vodURL) else { return nil }
        return Self.extractReleaseDate(from: html)
    }

    private func fetchURL(_ url: URL) async -> String? {
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func extractVODURL(from text: String) -> URL? {
        guard let range = text.range(of: #"https://www\.twitch\.tv/videos/\d+"#,
                                     options: .regularExpression) else { return nil }
        return URL(string: String(text[range]))
    }

    private static func extractReleaseDate(from html: String) -> Date? {
        let pattern = #"og:video:release_date"\s+content="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: html) else { return nil }
        let dateStr = String(html[captureRange])
        return ISO8601DateFormatter().date(from: dateStr)
    }

    /// Filters out decapi/Twitch error responses so we don't display them as data.
    private static func sanitize(_ text: String?) -> String {
        guard let text else { return "" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if trimmed.isEmpty { return "" }
        if lower.hasPrefix("sqlstate") { return "" }
        if lower.hasPrefix("[decapi") { return "" }
        if lower.hasPrefix("user not found") { return "" }
        if lower.hasPrefix("no user") { return "" }
        if lower.hasPrefix("unknown user") { return "" }
        if lower.contains("404 page not found") { return "" }
        if lower.contains("integrity constraint") { return "" }
        if lower.contains("410 gone") { return "" }
        if lower.contains("needs to authenticate") { return "" }
        return trimmed
    }
}
