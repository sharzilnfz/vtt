import Foundation

public protocol TranscriptionServiceProtocol: Sendable {
    func transcribe(samples: [Int16]) async throws -> TranscriptionResult
}

public final class MockTranscriptionService: TranscriptionServiceProtocol {
    private let stubbedText: String?
    private let delayNanoseconds: UInt64

    public init(stubbedText: String? = nil, delayNanoseconds: UInt64 = 50_000_000) {
        self.stubbedText = stubbedText
        self.delayNanoseconds = delayNanoseconds
    }

    public func transcribe(samples: [Int16]) async throws -> TranscriptionResult {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        let duration = Double(samples.count) / 16000.0
        let text = stubbedText ?? "Transcribed speech sample"
        return TranscriptionResult(text: text, durationSeconds: duration, confidence: 0.98)
    }
}
