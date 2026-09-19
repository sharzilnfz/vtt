import Foundation
import SQLite3

public struct SafetyBufferRecord: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let rawText: String
    public var refinedText: String?
    public let mode: String
    public let status: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        rawText: String,
        refinedText: String? = nil,
        mode: String,
        status: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rawText = rawText
        self.refinedText = refinedText
        self.mode = mode
        self.status = status
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        rawText: String,
        refinedText: String? = nil,
        mode: DictationMode,
        status: String
    ) {
        self.init(
            id: id,
            timestamp: timestamp,
            rawText: rawText,
            refinedText: refinedText,
            mode: mode.rawValue,
            status: status
        )
    }

    public init(transcript: Transcript, status: String = "recorded") {
        self.init(
            id: transcript.id,
            timestamp: transcript.createdAt,
            rawText: transcript.rawText,
            refinedText: transcript.refinedText,
            mode: transcript.mode.rawValue,
            status: status
        )
    }

    public var dictationMode: DictationMode? {
        DictationMode(rawValue: mode)
    }

    public func makeTranscript(durationSeconds: Double = 0) -> Transcript {
        Transcript(
            id: id,
            rawText: rawText,
            refinedText: refinedText,
            mode: dictationMode ?? .direct,
            durationSeconds: durationSeconds,
            targetApplication: nil,
            createdAt: timestamp
        )
    }
}

public struct DailyAggregateRecord: Sendable, Equatable {
    public let date: String
    public let mode: String
    public let wordCount: Int
    public let durationMs: Int
    public let sessionCount: Int

    public init(
        date: String,
        mode: String,
        wordCount: Int,
        durationMs: Int,
        sessionCount: Int
    ) {
        self.date = date
        self.mode = mode
        self.wordCount = wordCount
        self.durationMs = durationMs
        self.sessionCount = sessionCount
    }
}

public enum HistoryDatabaseError: Error, LocalizedError, Sendable {
    case openFailed(code: Int32, message: String)
    case executeFailed(code: Int32, message: String, sql: String)
    case prepareFailed(code: Int32, message: String, sql: String)
    case stepFailed(code: Int32, message: String, sql: String)
    case databaseClosed
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .openFailed(let code, let message):
            return "Failed to open database (code \(code)): \(message)"
        case .executeFailed(let code, let message, let sql):
            return "Failed to execute SQL '\(sql)' (code \(code)): \(message)"
        case .prepareFailed(let code, let message, let sql):
            return "Failed to prepare SQL '\(sql)' (code \(code)): \(message)"
        case .stepFailed(let code, let message, let sql):
            return "Failed to step SQL '\(sql)' (code \(code)): \(message)"
        case .databaseClosed:
            return "Database connection is closed"
        case .invalidURL:
            return "Invalid database file URL"
        }
    }
}

public final class HistoryDatabase: @unchecked Sendable {
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let lock = NSLock()
    private var db: OpaquePointer?
    public let safetyBufferCapacity: Int

    public static var defaultDatabaseURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent("utter", isDirectory: true).appendingPathComponent("history.db")
    }

    public static func inMemory(safetyBufferCapacity: Int = 100) throws -> HistoryDatabase {
        try HistoryDatabase(fileURL: nil, safetyBufferCapacity: safetyBufferCapacity)
    }

    public init(fileURL: URL? = HistoryDatabase.defaultDatabaseURL, safetyBufferCapacity: Int = 100) throws {
        self.safetyBufferCapacity = max(1, safetyBufferCapacity)

        let path: String
        if let fileURL {
            let directory = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            path = fileURL.path
        } else {
            path = ":memory:"
        }

        var dbPointer: OpaquePointer?
        let openFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let openStatus = sqlite3_open_v2(path, &dbPointer, openFlags, nil)
        guard openStatus == SQLITE_OK, let dbPointer else {
            let msg = dbPointer.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unable to allocate SQLite database"
            if let dbPointer { sqlite3_close(dbPointer) }
            throw HistoryDatabaseError.openFailed(code: openStatus, message: msg)
        }

        self.db = dbPointer

        sqlite3_busy_timeout(dbPointer, 5000)

        try executeLocked("PRAGMA journal_mode = WAL;")

        try initializeSchemaLocked()
    }

    deinit {
        lock.lock()
        if let db {
            sqlite3_close(db)
        }
        lock.unlock()
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    public var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return db == nil
    }

    public var currentJournalMode: String? {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA journal_mode;", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) {
            return String(cString: text)
        }
        return nil
    }

    public static func formatDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    // MARK: - Table 1: Safety Buffer

    public func insertSafetyBufferRecord(_ record: SafetyBufferRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { throw HistoryDatabaseError.databaseClosed }

        try executeTransactionLocked {
            let insertSQL = """
            INSERT INTO safety_buffer (id, timestamp, raw_text, refined_text, mode, status)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                timestamp = excluded.timestamp,
                raw_text = excluded.raw_text,
                refined_text = excluded.refined_text,
                mode = excluded.mode,
                status = excluded.status;
            """
            let insertStmt = try prepareLocked(insertSQL)
            defer { sqlite3_finalize(insertStmt) }

            sqlite3_bind_text(insertStmt, 1, record.id.uuidString, -1, Self.sqliteTransient)
            sqlite3_bind_double(insertStmt, 2, record.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(insertStmt, 3, record.rawText, -1, Self.sqliteTransient)
            if let refinedText = record.refinedText {
                sqlite3_bind_text(insertStmt, 4, refinedText, -1, Self.sqliteTransient)
            } else {
                sqlite3_bind_null(insertStmt, 4)
            }
            sqlite3_bind_text(insertStmt, 5, record.mode, -1, Self.sqliteTransient)
            sqlite3_bind_text(insertStmt, 6, record.status, -1, Self.sqliteTransient)

            let insertRc = sqlite3_step(insertStmt)
            guard insertRc == SQLITE_DONE else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw HistoryDatabaseError.stepFailed(code: insertRc, message: msg, sql: insertSQL)
            }

            let pruneSQL = """
            DELETE FROM safety_buffer
            WHERE id NOT IN (
                SELECT id FROM safety_buffer
                ORDER BY timestamp DESC, rowid DESC
                LIMIT ?
            );
            """
            let pruneStmt = try prepareLocked(pruneSQL)
            defer { sqlite3_finalize(pruneStmt) }

            sqlite3_bind_int(pruneStmt, 1, Int32(self.safetyBufferCapacity))
            let pruneRc = sqlite3_step(pruneStmt)
            guard pruneRc == SQLITE_DONE else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw HistoryDatabaseError.stepFailed(code: pruneRc, message: msg, sql: pruneSQL)
            }
        }
    }

    public func insertSafetyBufferRecord(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        rawText: String,
        refinedText: String? = nil,
        mode: String,
        status: String
    ) throws {
        let record = SafetyBufferRecord(
            id: id,
            timestamp: timestamp,
            rawText: rawText,
            refinedText: refinedText,
            mode: mode,
            status: status
        )
        try insertSafetyBufferRecord(record)
    }

    public func insertSafetyBufferRecord(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        rawText: String,
        refinedText: String? = nil,
        mode: DictationMode,
        status: String
    ) throws {
        let record = SafetyBufferRecord(
            id: id,
            timestamp: timestamp,
            rawText: rawText,
            refinedText: refinedText,
            mode: mode,
            status: status
        )
        try insertSafetyBufferRecord(record)
    }

    public func insertSafetyBufferRecord(transcript: Transcript, status: String = "recorded") throws {
        let record = SafetyBufferRecord(transcript: transcript, status: status)
        try insertSafetyBufferRecord(record)
    }

    public func loadSafetyBufferRecords() throws -> [SafetyBufferRecord] {
        lock.lock()
        defer { lock.unlock() }
        guard db != nil else { throw HistoryDatabaseError.databaseClosed }

        let sql = """
        SELECT id, timestamp, raw_text, refined_text, mode, status
        FROM safety_buffer
        ORDER BY timestamp DESC, rowid DESC;
        """
        let stmt = try prepareLocked(sql)
        defer { sqlite3_finalize(stmt) }

        var results: [SafetyBufferRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idString = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
                  let id = UUID(uuidString: idString) else {
                continue
            }
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            let rawText = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let refinedText: String?
            if sqlite3_column_type(stmt, 3) != SQLITE_NULL, let text = sqlite3_column_text(stmt, 3) {
                refinedText = String(cString: text)
            } else {
                refinedText = nil
            }
            let mode = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
            let status = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""

            results.append(SafetyBufferRecord(
                id: id,
                timestamp: timestamp,
                rawText: rawText,
                refinedText: refinedText,
                mode: mode,
                status: status
            ))
        }
        return results
    }

    public func loadSafetyBufferRecord(id: UUID) throws -> SafetyBufferRecord? {
        lock.lock()
        defer { lock.unlock() }
        guard db != nil else { throw HistoryDatabaseError.databaseClosed }

        let sql = """
        SELECT id, timestamp, raw_text, refined_text, mode, status
        FROM safety_buffer
        WHERE id = ?
        LIMIT 1;
        """
        let stmt = try prepareLocked(sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id.uuidString, -1, Self.sqliteTransient)
        if sqlite3_step(stmt) == SQLITE_ROW {
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            let rawText = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let refinedText: String?
            if sqlite3_column_type(stmt, 3) != SQLITE_NULL, let text = sqlite3_column_text(stmt, 3) {
                refinedText = String(cString: text)
            } else {
                refinedText = nil
            }
            let mode = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
            let status = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""

            return SafetyBufferRecord(
                id: id,
                timestamp: timestamp,
                rawText: rawText,
                refinedText: refinedText,
                mode: mode,
                status: status
            )
        }
        return nil
    }

    public func updateRefinedText(id: UUID, refinedText: String) throws {
        try updateRefinedText(idString: id.uuidString, refinedText: refinedText)
    }

    public func updateRefinedText(idString: String, refinedText: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { throw HistoryDatabaseError.databaseClosed }

        let sql = "UPDATE safety_buffer SET refined_text = ? WHERE id = ?;"
        let stmt = try prepareLocked(sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, refinedText, -1, Self.sqliteTransient)
        sqlite3_bind_text(stmt, 2, idString, -1, Self.sqliteTransient)

        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw HistoryDatabaseError.stepFailed(code: rc, message: msg, sql: sql)
        }
    }

    public func updateStatus(id: UUID, status: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { throw HistoryDatabaseError.databaseClosed }

        let sql = "UPDATE safety_buffer SET status = ? WHERE id = ?;"
        let stmt = try prepareLocked(sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, status, -1, Self.sqliteTransient)
        sqlite3_bind_text(stmt, 2, id.uuidString, -1, Self.sqliteTransient)

        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw HistoryDatabaseError.stepFailed(code: rc, message: msg, sql: sql)
        }
    }

    public func clearSafetyBuffer() throws {
        lock.lock()
        defer { lock.unlock() }
        try executeLocked("DELETE FROM safety_buffer;")
    }

    // MARK: - Table 2: Daily Aggregates

    public func recordSession(
        date: Date = Date(),
        mode: DictationMode,
        wordCount: Int,
        durationMs: Int
    ) throws {
        let dateString = Self.formatDate(date)
        try recordSession(
            dateString: dateString,
            mode: mode.rawValue,
            wordCount: wordCount,
            durationMs: durationMs
        )
    }

    public func recordSession(
        date: Date = Date(),
        mode: DictationMode,
        audioDurationSeconds: Double,
        wordCount: Int
    ) throws {
        let ms = Int(round(max(0, audioDurationSeconds) * 1000.0))
        try recordSession(
            date: date,
            mode: mode,
            wordCount: wordCount,
            durationMs: ms
        )
    }

    public func recordSession(
        dateString: String,
        mode: String,
        wordCount: Int,
        durationMs: Int
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { throw HistoryDatabaseError.databaseClosed }

        let sql = """
        INSERT INTO daily_aggregates (date, mode, word_count, duration_ms, session_count)
        VALUES (?, ?, ?, ?, 1)
        ON CONFLICT(date, mode) DO UPDATE SET
            word_count = daily_aggregates.word_count + excluded.word_count,
            duration_ms = daily_aggregates.duration_ms + excluded.duration_ms,
            session_count = daily_aggregates.session_count + 1;
        """
        let stmt = try prepareLocked(sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, dateString, -1, Self.sqliteTransient)
        sqlite3_bind_text(stmt, 2, mode, -1, Self.sqliteTransient)
        sqlite3_bind_int64(stmt, 3, Int64(max(0, wordCount)))
        sqlite3_bind_int64(stmt, 4, Int64(max(0, durationMs)))

        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw HistoryDatabaseError.stepFailed(code: rc, message: msg, sql: sql)
        }
    }

    public func loadLifetimeStats() throws -> DictationStats {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { throw HistoryDatabaseError.databaseClosed }

        let sql = """
        SELECT
            COALESCE(SUM(session_count), 0) AS total_sessions,
            COALESCE(SUM(CASE WHEN mode = 'direct' THEN session_count ELSE 0 END), 0) AS direct_sessions,
            COALESCE(SUM(CASE WHEN mode = 'refined' THEN session_count ELSE 0 END), 0) AS refined_sessions,
            COALESCE(SUM(duration_ms), 0) AS total_duration_ms,
            COALESCE(SUM(word_count), 0) AS total_words
        FROM daily_aggregates;
        """
        let stmt = try prepareLocked(sql)
        defer { sqlite3_finalize(stmt) }

        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_ROW else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw HistoryDatabaseError.stepFailed(code: rc, message: msg, sql: sql)
        }

        let totalSessions = Int(sqlite3_column_int64(stmt, 0))
        let directSessions = Int(sqlite3_column_int64(stmt, 1))
        let refinedSessions = Int(sqlite3_column_int64(stmt, 2))
        let totalMs = sqlite3_column_int64(stmt, 3)
        let totalSeconds = Double(totalMs) / 1000.0
        let totalWords = Int(sqlite3_column_int64(stmt, 4))

        return DictationStats(
            totalRecordings: totalSessions,
            totalDirectRecordings: directSessions,
            totalRefinedRecordings: refinedSessions,
            totalAudioSeconds: totalSeconds,
            totalWordsDelivered: totalWords
        )
    }

    public func loadDailyAggregates() throws -> [DailyAggregateRecord] {
        lock.lock()
        defer { lock.unlock() }
        guard db != nil else { throw HistoryDatabaseError.databaseClosed }

        let sql = """
        SELECT date, mode, word_count, duration_ms, session_count
        FROM daily_aggregates
        ORDER BY date DESC, mode ASC;
        """
        let stmt = try prepareLocked(sql)
        defer { sqlite3_finalize(stmt) }

        var records: [DailyAggregateRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let date = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let mode = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let wordCount = Int(sqlite3_column_int64(stmt, 2))
            let durationMs = Int(sqlite3_column_int64(stmt, 3))
            let sessionCount = Int(sqlite3_column_int64(stmt, 4))
            records.append(DailyAggregateRecord(
                date: date,
                mode: mode,
                wordCount: wordCount,
                durationMs: durationMs,
                sessionCount: sessionCount
            ))
        }
        return records
    }

    public func clearDailyAggregates() throws {
        lock.lock()
        defer { lock.unlock() }
        try executeLocked("DELETE FROM daily_aggregates;")
    }

    public func resetAll() throws {
        lock.lock()
        defer { lock.unlock() }
        try executeTransactionLocked {
            try executeLocked("DELETE FROM safety_buffer;")
            try executeLocked("DELETE FROM daily_aggregates;")
        }
    }

    // MARK: - Internal SQLite Helpers

    private func initializeSchemaLocked() throws {
        let schemaSQL = """
        CREATE TABLE IF NOT EXISTS safety_buffer (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            raw_text TEXT NOT NULL,
            refined_text TEXT,
            mode TEXT NOT NULL,
            status TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_safety_buffer_timestamp ON safety_buffer(timestamp DESC);

        CREATE TABLE IF NOT EXISTS daily_aggregates (
            date TEXT NOT NULL,
            mode TEXT NOT NULL,
            word_count INTEGER NOT NULL DEFAULT 0,
            duration_ms INTEGER NOT NULL DEFAULT 0,
            session_count INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (date, mode)
        );
        """
        try executeLocked(schemaSQL)
    }

    private func executeLocked(_ sql: String) throws {
        guard let db else { throw HistoryDatabaseError.databaseClosed }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if rc != SQLITE_OK {
            let message = errorMessage.flatMap { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw HistoryDatabaseError.executeFailed(code: rc, message: message, sql: sql)
        }
    }

    private func prepareLocked(_ sql: String) throws -> OpaquePointer {
        guard let db else { throw HistoryDatabaseError.databaseClosed }
        var statement: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard rc == SQLITE_OK, let statement else {
            let message = String(cString: sqlite3_errmsg(db))
            throw HistoryDatabaseError.prepareFailed(code: rc, message: message, sql: sql)
        }
        return statement
    }

    private func executeTransactionLocked<T>(_ block: () throws -> T) throws -> T {
        try executeLocked("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let result = try block()
            try executeLocked("COMMIT;")
            return result
        } catch {
            _ = try? executeLocked("ROLLBACK;")
            throw error
        }
    }
}
