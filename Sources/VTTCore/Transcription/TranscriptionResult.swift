import Foundation

public struct TranscriptionResult: Sendable, Equatable {
    public let text: String
    public let durationSeconds: Double
    public let confidence: Float?

    public init(text: String, durationSeconds: Double, confidence: Float? = nil) {
        self.text = text
        self.durationSeconds = durationSeconds
        self.confidence = confidence
    }
}
