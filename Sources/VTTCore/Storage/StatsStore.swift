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

    public init(initialStats: DictationStats = DictationStats()) {
        self.stats = initialStats
    }

    public func recordSession(mode: DictationMode, audioDuration: Double, wordCount: Int) {
        lock.lock()
        defer { lock.unlock() }

        stats.totalRecordings += 1
        switch mode {
        case .direct:
            stats.totalDirectRecordings += 1
        case .refined:
            stats.totalRefinedRecordings += 1
        }
        stats.totalAudioSeconds += audioDuration
        stats.totalWordsDelivered += wordCount
    }

    public var currentStats: DictationStats {
        lock.lock()
        defer { lock.unlock() }
        return stats
    }
}
