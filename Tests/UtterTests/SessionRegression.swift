import Foundation
import UtterCore

private func sessionCheck(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw NSError(domain: "SessionRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

func runShortcutRegressions() throws {
    var keys = ShortcutKeyReducer()
    try sessionCheck(keys.updateModifiers(leftControlDown: false, leftOptionDown: true, leftCommandDown: false) == [], "Left Option alone must not record")
    try sessionCheck(keys.updateModifiers(leftControlDown: true, leftOptionDown: false, leftCommandDown: false) == [], "Left Ctrl alone must not record")
    try sessionCheck(keys.pressV(isRepeat: false) == .reinsert, "Left Ctrl + V reinserts")
    try sessionCheck(keys.pressV(isRepeat: true) == nil, "Repeated V must not reinsert")
    try sessionCheck(keys.updateModifiers(leftControlDown: false, leftOptionDown: false, leftCommandDown: false) == [], "Idle flags emit nothing")

    try sessionCheck(keys.updateModifiers(leftControlDown: true, leftOptionDown: true, leftCommandDown: false) == [.start(.direct)], "Left Ctrl + Left Option starts direct")
    try sessionCheck(keys.pressV(isRepeat: false) == nil, "Chord held must not reinsert")
    try sessionCheck(keys.updateModifiers(leftControlDown: true, leftOptionDown: true, leftCommandDown: true) == [], "Command added mid-hold is ignored")
    try sessionCheck(keys.updateModifiers(leftControlDown: false, leftOptionDown: true, leftCommandDown: true) == [.stop(.direct), .start(.refined)], "Dropping Ctrl while Option+Command held switches to refined")
    try sessionCheck(keys.updateModifiers(leftControlDown: false, leftOptionDown: false, leftCommandDown: true) == [.stop(.refined)], "Releasing Option stops refined")
    try sessionCheck(keys.updateModifiers(leftControlDown: false, leftOptionDown: false, leftCommandDown: false) == [], "Idle flags emit nothing")

    try sessionCheck(keys.updateModifiers(leftControlDown: false, leftOptionDown: true, leftCommandDown: true) == [.start(.refined)], "Left Option + Left Command starts refined")
    try sessionCheck(keys.updateModifiers(leftControlDown: true, leftOptionDown: true, leftCommandDown: true) == [], "Ctrl added mid-hold is ignored")
    try sessionCheck(keys.updateModifiers(leftControlDown: true, leftOptionDown: false, leftCommandDown: true) == [.stop(.refined)], "Releasing Option stops refined")
    try sessionCheck(keys.pressV(isRepeat: false) == nil, "Ctrl + Command held must not reinsert")

    try sessionCheck(keys.updateModifiers(leftControlDown: true, leftOptionDown: true, leftCommandDown: true) == [], "All three at once is ambiguous and must not start")
    try sessionCheck(keys.updateModifiers(leftControlDown: true, leftOptionDown: false, leftCommandDown: false) == [], "Ambiguous state releases to no start")
    try sessionCheck(keys.pressV(isRepeat: false) == .reinsert, "Left Ctrl + V reinserts again")

    var rightOptionKeys = ShortcutKeyReducer()
    try sessionCheck(rightOptionKeys.updateModifiers(leftControlDown: false, leftOptionDown: false, leftCommandDown: false, rightOptionDown: true) == [.start(.direct)], "Right Option alone starts direct dictation avoiding VoiceOver collision")
    try sessionCheck(rightOptionKeys.updateModifiers(leftControlDown: false, leftOptionDown: false, leftCommandDown: false, rightOptionDown: false) == [.stop(.direct)], "Releasing Right Option stops direct dictation")
}

func runSessionStateRegressions() throws {
    let machine = SessionStateMachine()
    let target = TargetApplication(bundleIdentifier: "test.target", processIdentifier: 42, localizedName: "Test")
    _ = machine.startRecording(mode: .refined, targetApp: target)
    let capturedState = machine.state
    try sessionCheck(machine.startRecording(mode: .direct, targetApp: nil) == .failure(.alreadyActive), "Duplicate start must be rejected")
    try sessionCheck(machine.state == capturedState, "Duplicate start must preserve captured context")
    try sessionCheck(machine.startReinserting(text: "saved", targetApp: nil) == .failure(.alreadyActive), "Reinsert must reject recording")
    try sessionCheck(machine.stopRecording() == .success(.transcribing(mode: .refined, targetApp: target)), "Stop must retain captured mode and target")
    try sessionCheck(machine.startReinserting(text: "saved", targetApp: nil) == .failure(.alreadyActive), "Reinsert must reject transcription")
    machine.reset()
    try sessionCheck(machine.startReinserting(text: "saved", targetApp: target) == .success(.inserting(text: "saved", targetApp: target)), "Idle reinsert must enter inserting state")
    try sessionCheck(machine.startRecording(mode: .direct, targetApp: target) == .failure(.alreadyActive), "Recording must reject active reinsert")
}

private final class RegressionAudio: AudioCaptureServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var capturing = false
    private var starts = 0
    private var stops = 0
    private var levelCallback: (@Sendable (Float) -> Void)?
    let samples: [Int16]
    let shouldFail: Bool

    init(samples: [Int16] = [100, 200], shouldFail: Bool = false) {
        self.samples = samples
        self.shouldFail = shouldFail
    }

    var isCapturing: Bool { lock.withLock { capturing } }
    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }

    func startCapture(onLevelUpdate: (@Sendable (Float) -> Void)?) throws {
        try lock.withLock {
            starts += 1
            if shouldFail { throw SessionFailureReason.microphoneUnavailable }
            capturing = true
            levelCallback = onLevelUpdate
        }
    }

    func stopCapture() -> [Int16] {
        lock.withLock {
            guard capturing else { return [] }
            capturing = false
            stops += 1
            return samples
        }
    }

    func sendLateLevel() {
        let callback = lock.withLock { levelCallback }
        callback?(0.9)
    }
}

private final class RegressionInsertion: InsertionServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var inserted: [String] = []
    let result: Result<InsertionMethod, SessionFailureReason>

    init(result: Result<InsertionMethod, SessionFailureReason> = .success(.directTyping)) {
        self.result = result
    }

    var texts: [String] { lock.withLock { inserted } }

    func insert(text: String, targetApp: TargetApplication?, forceClipboard: Bool) -> Result<InsertionMethod, SessionFailureReason> {
        lock.withLock { inserted.append(text) }
        return result
    }
}

private struct RegressionRefinement: RefinementServiceProtocol {
    func refine(rawText: String) async -> String { "refined: " + rawText }
}

private struct RegressionTarget: TargetValidating {
    func currentTarget() -> TargetApplication? { nil }
    func validate(against expected: TargetApplication?) -> TargetValidationResult { .valid }
}

@MainActor
private func waitForSession(_ predicate: () -> Bool) async throws {
    for _ in 0..<2_000 {
        if predicate() { return }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    throw NSError(domain: "SessionRegression", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for session"])
}

@MainActor
func runCoordinatorRegressions() async throws {
    for mode in DictationMode.allCases {
        let audio = RegressionAudio()
        let insertion = RegressionInsertion()
        let coordinator = DictationCoordinator(
            audioCapture: audio,
            transcriptionService: MockTranscriptionService(stubbedText: "spoken", delayNanoseconds: 0),
            refinementService: RegressionRefinement(),
            insertionService: insertion,
            targetValidator: RegressionTarget(),
            config: AppConfiguration(playSounds: false)
        )
        let wrongMode: DictationMode = mode == .direct ? .refined : .direct
        coordinator.startSession(mode: mode)
        coordinator.startSession(mode: wrongMode)
        try sessionCheck(audio.startCount == 1, "Duplicate coordinator start must not restart audio")
        coordinator.stopSession(mode: wrongMode)
        audio.sendLateLevel()
        try await waitForSession { coordinator.stateMachine.state.isIdle }
        try sessionCheck(coordinator.safetyBuffer.lastTranscript?.mode == mode, "Transcript must use captured mode, not release mode")
        try sessionCheck(insertion.texts == [mode == .direct ? "spoken" : "refined: spoken"], "Refinement must follow captured mode")
        try sessionCheck(coordinator.pillViewModel.status == .idle, "Late meter callback must not restore recording UI")
    }

    let sampleCases: [[Int16]] = [[], [100]]
    for samples in sampleCases {
        let insertion = RegressionInsertion()
        let coordinator = DictationCoordinator(
            audioCapture: RegressionAudio(samples: samples),
            transcriptionService: MockTranscriptionService(stubbedText: " \n\t", delayNanoseconds: 0),
            insertionService: insertion,
            targetValidator: RegressionTarget(),
            config: AppConfiguration(playSounds: false)
        )
        coordinator.startSession(mode: .direct)
        coordinator.stopSession(mode: .direct)
        try await waitForSession { coordinator.stateMachine.state.isIdle }
        try sessionCheck(insertion.texts.isEmpty, "Empty audio or ASR must not insert")
        try sessionCheck(coordinator.safetyBuffer.lastTranscript == nil, "Empty ASR must not replace safety text")
    }

    let insertion = RegressionInsertion(result: .failure(.insertionFailed))
    let coordinator = DictationCoordinator(
        audioCapture: RegressionAudio(),
        transcriptionService: MockTranscriptionService(stubbedText: "spoken", delayNanoseconds: 50_000_000),
        insertionService: insertion,
        targetValidator: RegressionTarget(),
        config: AppConfiguration(playSounds: false)
    )
    coordinator.safetyBuffer.recordRaw(Transcript(rawText: "saved", mode: .direct, durationSeconds: 1))
    coordinator.startSession(mode: .direct)
    coordinator.reinsertLast()
    try sessionCheck(insertion.texts.isEmpty, "Reinsert must not run during recording")
    coordinator.stopSession(mode: .direct)
    coordinator.reinsertLast()
    try sessionCheck(insertion.texts.isEmpty, "Reinsert must not run during transcription")
    try await waitForSession { coordinator.stateMachine.state == .failed(reason: .insertionFailed) }
    coordinator.stateMachine.reset()
    coordinator.reinsertLast()
    try sessionCheck(coordinator.stateMachine.state == .failed(reason: .insertionFailed), "Failed reinsert must enter failed state")
    try sessionCheck(coordinator.pillViewModel.status == .failed(reason: .insertionFailed), "Failed reinsert must show failure UI")

    let failedStart = DictationCoordinator(audioCapture: RegressionAudio(shouldFail: true), targetValidator: RegressionTarget())
    failedStart.startSession(mode: .direct)
    try sessionCheck(failedStart.stateMachine.state == .failed(reason: .microphoneUnavailable), "Capture error must fail session")

    let cappedAudio = RegressionAudio()
    let capped = DictationCoordinator(
        audioCapture: cappedAudio,
        transcriptionService: MockTranscriptionService(stubbedText: "spoken", delayNanoseconds: 0),
        refinementService: RegressionRefinement(),
        insertionService: RegressionInsertion(),
        targetValidator: RegressionTarget(),
        config: AppConfiguration(playSounds: false),
        maxRecordingSeconds: 0.2
    )
    capped.startSession(mode: .direct)
    capped.stopSession(mode: .direct)
    try await waitForSession { capped.stateMachine.state.isIdle }
    try await Task.sleep(nanoseconds: 150_000_000)
    capped.startSession(mode: .refined)
    try await Task.sleep(nanoseconds: 100_000_000)
    try sessionCheck(capped.stateMachine.state.isRecording, "Cancelled cap must not stop the next recording")
    try await waitForSession { !cappedAudio.isCapturing }
    try sessionCheck(cappedAudio.stopCount == 2, "Recording cap must stop audio exactly once")
    capped.stopSession(mode: .direct)
    try sessionCheck(cappedAudio.stopCount == 2, "Release after cap must be ignored")

    var startSoundCount = 0
    var completionSoundCount = 0
    let soundCoordinator = DictationCoordinator(
        audioCapture: RegressionAudio(),
        transcriptionService: MockTranscriptionService(stubbedText: "sound test", delayNanoseconds: 0),
        refinementService: RegressionRefinement(),
        insertionService: RegressionInsertion(),
        targetValidator: RegressionTarget(),
        config: AppConfiguration(playSounds: true),
        playStartSound: { startSoundCount += 1 },
        playSound: { completionSoundCount += 1 }
    )
    soundCoordinator.startSession(mode: .direct)
    try sessionCheck(startSoundCount == 1, "Subtle click audio cue must play on key press (startSession)")
    soundCoordinator.stopSession(mode: .direct)
    try await waitForSession { soundCoordinator.stateMachine.state.isIdle }
    try sessionCheck(completionSoundCount == 1, "Soft pop completion cue must play upon confirmed delivery")
}
