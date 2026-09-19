import Foundation

public struct Transcript: Codable, Sendable, Equatable {
    public let id: UUID
    public let rawText: String
    public var refinedText: String?
    public let mode: DictationMode
    public let durationSeconds: Double
    public let targetApplication: TargetApplication?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        rawText: String,
        refinedText: String? = nil,
        mode: DictationMode,
        durationSeconds: Double,
        targetApplication: TargetApplication? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.rawText = rawText
        self.refinedText = refinedText
        self.mode = mode
        self.durationSeconds = durationSeconds
        self.targetApplication = targetApplication
        self.createdAt = createdAt
    }

    public var textToInsert: String {
        if mode == .refined, let refinedText, !refinedText.isEmpty {
            return refinedText
        }
        return rawText
    }

    public var wordCount: Int {
        let text = textToInsert
        return text.split { $0.isWhitespace || $0.isPunctuation }.count
    }
}
