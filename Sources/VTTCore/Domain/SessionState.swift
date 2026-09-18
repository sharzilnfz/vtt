import Foundation

public enum SessionFailureReason: String, Codable, Sendable, Equatable, Error {
    case microphoneUnavailable
    case audioRecordingFailed
    case transcriptionFailed
    case targetAppChanged
    case insertionFailed
    case cancelled
}

public enum SessionState: Sendable, Equatable {
    case idle
    case recording(mode: DictationMode, startedAt: Date, targetApp: TargetApplication?)
    case transcribing(mode: DictationMode, targetApp: TargetApplication?)
    case refining(rawText: String, targetApp: TargetApplication?)
    case inserting(text: String, targetApp: TargetApplication?)
    case failed(reason: SessionFailureReason)

    public var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    public var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    public var targetApp: TargetApplication? {
        switch self {
        case .recording(_, _, let app),
             .transcribing(_, let app),
             .refining(_, let app),
             .inserting(_, let app):
            return app
        case .idle, .failed:
            return nil
        }
    }
}

public enum SessionError: Error, Equatable {
    case alreadyActive
    case notRecording
    case notTranscribing
    case notRefining
    case notInserting
    case invalidTransition
}

public final class SessionStateMachine: @unchecked Sendable {
    private let lock = NSLock()
    private var _state: SessionState = .idle

    public init() {}

    public var state: SessionState {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    public func startRecording(
        mode: DictationMode,
        targetApp: TargetApplication?
    ) -> Result<SessionState, SessionError> {
        lock.lock()
        defer { lock.unlock() }

        guard _state == .idle else {
            return .failure(.alreadyActive)
        }

        _state = .recording(mode: mode, startedAt: Date(), targetApp: targetApp)
        return .success(_state)
    }

    public func stopRecording() -> Result<SessionState, SessionError> {
        lock.lock()
        defer { lock.unlock() }

        guard case .recording(let mode, _, let targetApp) = _state else {
            return .failure(.notRecording)
        }

        _state = .transcribing(mode: mode, targetApp: targetApp)
        return .success(_state)
    }

    public func startRefining(rawText: String) -> Result<SessionState, SessionError> {
        lock.lock()
        defer { lock.unlock() }

        guard case .transcribing(let mode, let targetApp) = _state, mode == .refined else {
            return .failure(.notTranscribing)
        }

        _state = .refining(rawText: rawText, targetApp: targetApp)
        return .success(_state)
    }

    public func startInserting(text: String) -> Result<SessionState, SessionError> {
        lock.lock()
        defer { lock.unlock() }

        switch _state {
        case .transcribing(let mode, let targetApp) where mode == .direct:
            _state = .inserting(text: text, targetApp: targetApp)
            return .success(_state)
        case .refining(_, let targetApp):
            _state = .inserting(text: text, targetApp: targetApp)
            return .success(_state)
        default:
            return .failure(.invalidTransition)
        }
    }

    public func startReinserting(
        text: String,
        targetApp: TargetApplication?
    ) -> Result<SessionState, SessionError> {
        lock.lock()
        defer { lock.unlock() }

        guard _state == .idle else { return .failure(.alreadyActive) }
        _state = .inserting(text: text, targetApp: targetApp)
        return .success(_state)
    }

    @discardableResult
    public func complete() -> SessionState {
        lock.lock()
        defer { lock.unlock() }
        _state = .idle
        return _state
    }

    @discardableResult
    public func fail(reason: SessionFailureReason) -> SessionState {
        lock.lock()
        defer { lock.unlock() }
        _state = .failed(reason: reason)
        return _state
    }

    @discardableResult
    public func reset() -> SessionState {
        lock.lock()
        defer { lock.unlock() }
        _state = .idle
        return _state
    }
}
