import Foundation

public final class SafetyBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var buffer: [Transcript] = []

    public init(capacity: Int = 10) {
        self.capacity = max(1, capacity)
    }

    public func recordRaw(_ transcript: Transcript) {
        lock.lock()
        defer { lock.unlock() }

        buffer.insert(transcript, at: 0)
        if buffer.count > capacity {
            buffer.removeLast()
        }
    }

    public func updateRefined(id: UUID, refinedText: String) {
        lock.lock()
        defer { lock.unlock() }

        if let index = buffer.firstIndex(where: { $0.id == id }) {
            var item = buffer[index]
            item.refinedText = refinedText
            buffer[index] = item
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
        defer { lock.unlock() }
        buffer.removeAll()
    }
}
