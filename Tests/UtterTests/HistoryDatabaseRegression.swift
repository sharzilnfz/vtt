import Foundation
import UtterCore

private func dbCheck(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw NSError(domain: "HistoryDatabaseRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

func runHistoryDatabaseRegressions() throws {
    // 1. Default database URL verification
    guard let defaultURL = HistoryDatabase.defaultDatabaseURL else {
        throw NSError(domain: "HistoryDatabaseRegression", code: 2, userInfo: [NSLocalizedDescriptionKey: "defaultDatabaseURL must not be nil"])
    }
    try dbCheck(defaultURL.path.contains("Library/Application Support/utter/history.db"), "Default database path must end in Library/Application Support/utter/history.db")

    // 2. Open disk database, verify WAL mode and file creation
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("utter-db-test-\(UUID().uuidString)")
    let fileURL = tempDir.appendingPathComponent("history.db")
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let diskDB = try HistoryDatabase(fileURL: fileURL)
    try dbCheck(diskDB.currentJournalMode?.lowercased() == "wal", "Disk database must enable WAL mode")
    diskDB.close()
    try dbCheck(diskDB.isClosed, "Database should report closed after close()")

    // 3. In-memory database testing
    let db = try HistoryDatabase.inMemory(safetyBufferCapacity: 10)

    // Table 1: Rolling 10 records eviction
    var insertedIDs: [UUID] = []
    let baseTime = Date(timeIntervalSince1970: 1_000_000)
    for i in 1...15 {
        let id = UUID()
        insertedIDs.append(id)
        let record = SafetyBufferRecord(
            id: id,
            timestamp: baseTime.addingTimeInterval(Double(i)),
            rawText: "Raw speech \(i)",
            refinedText: i % 2 == 0 ? "Refined speech \(i)" : nil,
            mode: i % 2 == 0 ? .refined : .direct,
            status: "recorded"
        )
        try db.insertSafetyBufferRecord(record)
    }

    let records = try db.loadSafetyBufferRecords()
    try dbCheck(records.count == 10, "Safety buffer must strictly maintain rolling capacity of 10")
    try dbCheck(records[0].rawText == "Raw speech 15", "Records must be sorted by timestamp DESC")
    try dbCheck(records[9].rawText == "Raw speech 6", "Oldest kept record should be speech 6 (1 to 5 evicted)")

    // Update refined text
    let targetID = records[0].id
    try db.updateRefinedText(id: targetID, refinedText: "Updated speech 15 refined.")
    let updatedRecord = try db.loadSafetyBufferRecord(id: targetID)
    try dbCheck(updatedRecord?.refinedText == "Updated speech 15 refined.", "Refined text must be updated")

    // Clear safety buffer
    try db.clearSafetyBuffer()
    let clearedRecords = try db.loadSafetyBufferRecords()
    try dbCheck(clearedRecords.isEmpty, "Safety buffer must be empty after clearSafetyBuffer()")

    // Table 2: Daily Aggregates & Lifetime Stats
    let day1 = "2026-09-18"
    let day2 = "2026-09-19"

    // Day 1: 1 direct session (10 words, 2000 ms), 1 refined session (25 words, 4000 ms)
    try db.recordSession(dateString: day1, mode: "direct", wordCount: 10, durationMs: 2000)
    try db.recordSession(dateString: day1, mode: "refined", wordCount: 25, durationMs: 4000)

    // Day 2: 2 direct sessions (15 words 3000ms, 20 words 2500ms), 1 refined session (30 words 5500ms)
    try db.recordSession(dateString: day2, mode: "direct", wordCount: 15, durationMs: 3000)
    try db.recordSession(dateString: day2, mode: "direct", wordCount: 20, durationMs: 2500)
    try db.recordSession(dateString: day2, mode: "refined", wordCount: 30, durationMs: 5500)

    let aggregates = try db.loadDailyAggregates()
    try dbCheck(aggregates.count == 4, "Should have 4 aggregate rows (2 days * 2 modes each)")

    let stats = try db.loadLifetimeStats()
    // Total recordings: 1 + 1 + 2 + 1 = 5
    try dbCheck(stats.totalRecordings == 5, "Total recordings should be 5, got \(stats.totalRecordings)")
    // Total direct: 1 + 2 = 3
    try dbCheck(stats.totalDirectRecordings == 3, "Total direct recordings should be 3, got \(stats.totalDirectRecordings)")
    // Total refined: 1 + 1 = 2
    try dbCheck(stats.totalRefinedRecordings == 2, "Total refined recordings should be 2, got \(stats.totalRefinedRecordings)")
    // Total duration: 2000 + 4000 + 3000 + 2500 + 5500 = 17000 ms = 17.0s
    try dbCheck(abs(stats.totalAudioSeconds - 17.0) < 0.001, "Total audio seconds should be 17.0, got \(stats.totalAudioSeconds)")
    // Total words: 10 + 25 + 15 + 20 + 30 = 100
    try dbCheck(stats.totalWordsDelivered == 100, "Total words delivered should be 100, got \(stats.totalWordsDelivered)")

    // Clear daily aggregates
    try db.clearDailyAggregates()
    let clearedStats = try db.loadLifetimeStats()
    try dbCheck(clearedStats.totalRecordings == 0, "Lifetime stats should reset to 0 after clearDailyAggregates()")
    try dbCheck(clearedStats.totalWordsDelivered == 0, "Total words should be 0")
}

func runHistoryDatabaseConcurrencyRegressions() async throws {
    let db = try HistoryDatabase.inMemory(safetyBufferCapacity: 10)

    try await withThrowingTaskGroup(of: Void.self) { group in
        for i in 0..<20 {
            group.addTask {
                let id = UUID()
                try db.insertSafetyBufferRecord(
                    id: id,
                    timestamp: Date(),
                    rawText: "Concurrent \(i)",
                    mode: i % 2 == 0 ? .direct : .refined,
                    status: "recorded"
                )
                try db.recordSession(
                    mode: i % 2 == 0 ? .direct : .refined,
                    audioDurationSeconds: 1.5,
                    wordCount: 10
                )
                _ = try db.loadLifetimeStats()
                _ = try db.loadSafetyBufferRecords()
            }
        }
        try await group.waitForAll()
    }

    let records = try db.loadSafetyBufferRecords()
    try dbCheck(records.count <= 10, "Safety buffer rolling capacity must be preserved under concurrent writes")
    let stats = try db.loadLifetimeStats()
    try dbCheck(stats.totalRecordings == 20, "Total recordings must equal 20 under concurrent writes")
}
