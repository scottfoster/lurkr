import Foundation

enum Browser: String, Codable, CaseIterable {
    case safari, chrome, firefox

    var appPath: String {
        switch self {
        case .safari:  return "/Applications/Safari.app"
        case .chrome:  return "/Applications/Google Chrome.app"
        case .firefox: return "/Applications/Firefox.app"
        }
    }

    var displayName: String {
        switch self {
        case .safari:  return "Safari"
        case .chrome:  return "Chrome"
        case .firefox: return "Firefox"
        }
    }
}

struct Config: Codable {
    var favorites: [String] = []
    var lastSeenLive: [String: Date] = [:]
    var pollIntervalSeconds: Int = 60
    var notificationsEnabled: Bool = true
    var browser: Browser = .safari

    init() {}

    // Custom decoder so configs from older versions (without these keys) keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        favorites = (try? c.decodeIfPresent([String].self, forKey: .favorites)) ?? []
        lastSeenLive = (try? c.decodeIfPresent([String: Date].self, forKey: .lastSeenLive)) ?? [:]
        pollIntervalSeconds = (try? c.decodeIfPresent(Int.self, forKey: .pollIntervalSeconds)) ?? 60
        notificationsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled)) ?? true
        browser = (try? c.decodeIfPresent(Browser.self, forKey: .browser)) ?? .safari
    }

    static var fileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".config/lurkr", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("config.json")

        if !FileManager.default.fileExists(atPath: file.path) {
            let oldFile = home.appendingPathComponent(".config/twitch-menu/config.json")
            if FileManager.default.fileExists(atPath: oldFile.path) {
                try? FileManager.default.moveItem(at: oldFile, to: file)
                try? FileManager.default.removeItem(at: home.appendingPathComponent(".config/twitch-menu"))
            }
        }
        return file
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: fileURL),
              let cfg = try? loadDecoder().decode(Config.self, from: data) else {
            return Config()
        }
        return cfg
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(self) {
            try? data.write(to: Config.fileURL)
        }
    }

    static func loadDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
