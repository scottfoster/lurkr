import Foundation

enum StreamStatus: Sendable {
    case live(Stream)
    case offline
    case unknown
}

struct LiveStatusTracker {
    private var lastKnown: [String: StreamStatus] = [:]

    var streams: [Stream] {
        lastKnown.values.compactMap { status in
            if case .live(let stream) = status { return stream }
            return nil
        }
    }

    mutating func update(_ statuses: [String: StreamStatus], favorites: Set<String>) -> [Stream] {
        lastKnown = lastKnown.filter { favorites.contains($0.key) }
        var newlyLive: [Stream] = []
        for (login, status) in statuses where favorites.contains(login) {
            switch status {
            case .live(let stream):
                // The first successful observation establishes a quiet baseline.
                if case .offline = lastKnown[login] { newlyLive.append(stream) }
                lastKnown[login] = status
            case .offline:
                lastKnown[login] = status
            case .unknown:
                break
            }
        }
        return newlyLive
    }
}
