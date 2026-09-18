import Foundation
import Combine

public enum PillStatus: Sendable, Equatable {
    case idle
    case recording(level: Float)
    case transcribing
    case refining
    case inserting
    case failed(reason: SessionFailureReason)

    public var displayText: String {
        switch self {
        case .idle: return "Ready"
        case .recording: return "Recording"
        case .transcribing: return "Working"
        case .refining: return "Cleaning"
        case .inserting: return "Typing"
        case .failed(let reason):
            switch reason {
            case .microphoneUnavailable: return "No mic"
            case .audioRecordingFailed: return "No audio"
            case .transcriptionFailed: return "No text"
            case .targetAppChanged: return "App changed"
            case .insertionFailed: return "No insert"
            case .cancelled: return "Cancelled"
            }
        }
    }

    public var isVisible: Bool {
        if case .idle = self { return false }
        return true
    }
}

@MainActor
public final class PillViewModel: ObservableObject {
    @Published public private(set) var status: PillStatus = .idle

    public init() {}

    public func update(status: PillStatus) {
        self.status = status
    }
}
