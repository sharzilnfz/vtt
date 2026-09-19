import Foundation

public struct DictationStats: Codable, Sendable, Equatable {
    public var totalRecordings: Int
    public var totalDirectRecordings: Int
    public var totalRefinedRecordings: Int
    public var totalAudioSeconds: Double
    public var totalWordsDelivered: Int

    public init(
        totalRecordings: Int = 0,
        totalDirectRecordings: Int = 0,
        totalRefinedRecordings: Int = 0,
        totalAudioSeconds: Double = 0.0,
        totalWordsDelivered: Int = 0
    ) {
        self.totalRecordings = totalRecordings
        self.totalDirectRecordings = totalDirectRecordings
        self.totalRefinedRecordings = totalRefinedRecordings
        self.totalAudioSeconds = totalAudioSeconds
        self.totalWordsDelivered = totalWordsDelivered
    }
}

public final class StatsStore: @unchecked Sendable {
    private let lock = NSLock()
    private var stats: DictationStats
    private let database: HistoryDatabase?

    public static var defaultDatabaseURL: URL? {
        HistoryDatabase.defaultDatabaseURL
    }

    public static var defaultFileURL: URL? {
        defaultDatabaseURL
    }

    public init(initialStats: DictationStats? = nil, database: HistoryDatabase? = nil, fileURL: URL? = nil) {
        if let database {
            self.database = database
        } else if let fileURL {
            self.database = try? HistoryDatabase(fileURL: fileURL)
        } else {
            self.database = nil
        }

        var loaded = initialStats ?? DictationStats()
        if let database = self.database {
            if let dbStats = try? database.loadLifetimeStats(), dbStats.totalRecordings > 0 {
                loaded = dbStats
            }
        }
        self.stats = loaded
    }

    public var historyDatabase: HistoryDatabase? {
        database
    }

    public func recordSession(mode: DictationMode, audioDuration: Double, wordCount: Int) {
        lock.lock()
        stats.totalRecordings += 1
        switch mode {
        case .direct:
            stats.totalDirectRecordings += 1
        case .refined:
            stats.totalRefinedRecordings += 1
        }
        stats.totalAudioSeconds += audioDuration
        stats.totalWordsDelivered += wordCount
        lock.unlock()

        if let database {
            try? database.recordSession(
                date: Date(),
                mode: mode,
                audioDurationSeconds: audioDuration,
                wordCount: wordCount
            )
        }
    }

    public var currentStats: DictationStats {
        lock.lock()
        defer { lock.unlock() }
        return stats
    }
}
