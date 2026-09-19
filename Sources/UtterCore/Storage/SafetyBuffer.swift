import Foundation

public final class SafetyBuffer: @unchecked Sendable {
    private let lock = NSLock()
    public let capacity: Int
    private var buffer: [Transcript] = []
    private let database: HistoryDatabase?

    public static var defaultDatabaseURL: URL? {
        HistoryDatabase.defaultDatabaseURL
    }

    public static var defaultFileURL: URL? {
        defaultDatabaseURL
    }

    public init(capacity: Int = 100, database: HistoryDatabase? = nil, fileURL: URL? = nil) {
        self.capacity = max(1, capacity)
        if let database {
            self.database = database
        } else if let fileURL {
            self.database = try? HistoryDatabase(fileURL: fileURL, safetyBufferCapacity: self.capacity)
        } else {
            self.database = nil
        }

        if let database = self.database {
            if let records = try? database.loadSafetyBufferRecords() {
                self.buffer = records.prefix(self.capacity).map { $0.makeTranscript() }
            }
        }
    }

    public var historyDatabase: HistoryDatabase? {
        database
    }

    public func recordRaw(_ transcript: Transcript) {
        lock.lock()
        buffer.insert(transcript, at: 0)
        if buffer.count > capacity {
            buffer.removeLast()
        }
        lock.unlock()

        if let database {
            try? database.insertSafetyBufferRecord(transcript: transcript, status: "recorded")
        }
    }

    public func updateRefined(id: UUID, refinedText: String) {
        lock.lock()
        if let index = buffer.firstIndex(where: { $0.id == id }) {
            var item = buffer[index]
            item.refinedText = refinedText
            buffer[index] = item
        }
        lock.unlock()

        if let database {
            try? database.updateRefinedText(id: id, refinedText: refinedText)
        }
    }

    public var lastTranscript: Transcript? {
        lock.lock()
        defer { lock.unlock() }
        return buffer.first
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    public var allItems: [Transcript] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    public func clear() {
        lock.lock()
        buffer.removeAll()
        lock.unlock()

        if let database {
            try? database.clearSafetyBuffer()
        }
    }
}
