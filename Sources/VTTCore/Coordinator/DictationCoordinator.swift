import AppKit
import Foundation

@MainActor
public final class DictationCoordinator {
    public let stateMachine: SessionStateMachine
    public let safetyBuffer: SafetyBuffer
    public let statsStore: StatsStore
    public let vocabularyStore: VocabularyStore
    public let audioCapture: AudioCaptureServiceProtocol
    public let transcriptionService: TranscriptionServiceProtocol
    public let refinementService: RefinementServiceProtocol
    public let insertionService: InsertionServiceProtocol
    public let targetValidator: TargetValidating
    public let pillViewModel: PillViewModel
    public let config: AppConfiguration
    public var playSound: (@MainActor () -> Void)?
    private let maxRecordingSeconds: Double
    private var recordingID: UUID?
    private var recordingLimitTask: Task<Void, Never>?
    private var resetTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?

    public init(
        stateMachine: SessionStateMachine = SessionStateMachine(),
        safetyBuffer: SafetyBuffer = SafetyBuffer(),
        statsStore: StatsStore = StatsStore(),
        vocabularyStore: VocabularyStore = VocabularyStore(),
        audioCapture: AudioCaptureServiceProtocol = AudioCaptureService(),
        transcriptionService: TranscriptionServiceProtocol = MockTranscriptionService(),
        refinementService: RefinementServiceProtocol? = nil,
        insertionService: InsertionServiceProtocol? = nil,
        targetValidator: TargetValidating = TargetValidator(),
        pillViewModel: PillViewModel = PillViewModel(),
        config: AppConfiguration = AppConfiguration(),
        maxRecordingSeconds: Double = 120,
        playSound: (@MainActor () -> Void)? = { NSSound(named: "Pop")?.play() }
    ) {
        self.stateMachine = stateMachine
        self.safetyBuffer = safetyBuffer
        self.statsStore = statsStore
        self.vocabularyStore = vocabularyStore
        self.audioCapture = audioCapture
        self.transcriptionService = transcriptionService
        self.refinementService = refinementService ?? RefinementService(config: config.refinementConfig)
        self.insertionService = insertionService ?? InsertionService(
            targetValidator: targetValidator,
            config: config
        )
        self.targetValidator = targetValidator
        self.pillViewModel = pillViewModel
        self.config = config
        self.maxRecordingSeconds = maxRecordingSeconds.isFinite ? max(0.001, min(120, maxRecordingSeconds)) : 120
        self.playSound = playSound
    }

    deinit {
        recordingLimitTask?.cancel()
        resetTask?.cancel()
        processingTask?.cancel()
    }

    public func startSession(mode: DictationMode) {
        guard stateMachine.state.isIdle else { return }
        processingTask?.cancel()
        processingTask = nil
        let currentTarget = targetValidator.currentTarget()
        let result = stateMachine.startRecording(mode: mode, targetApp: currentTarget)
        guard case .success = result else { return }
        resetTask?.cancel()
        resetTask = nil
        let id = UUID()
        recordingID = id

        do {
            try audioCapture.startCapture { [weak self] level in
                Task { @MainActor in
                    guard let self, self.recordingID == id, self.stateMachine.state.isRecording else { return }
                    self.pillViewModel.update(status: .recording(level: level))
                }
            }
            pillViewModel.update(status: .recording(level: 0))
            recordingLimitTask?.cancel()
            let nanoseconds = UInt64(maxRecordingSeconds * 1_000_000_000)
            recordingLimitTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: nanoseconds) }
                catch { return }
                guard let self, self.recordingID == id else { return }
                self.stopSession(mode: mode)
            }
        } catch {
            recordingID = nil
            recordingLimitTask?.cancel()
            recordingLimitTask = nil
            _ = audioCapture.stopCapture()
            showFailure(.microphoneUnavailable)
        }
    }

    public func stopSession(mode: DictationMode? = nil) {
        let stopResult = stateMachine.stopRecording()
        guard case .success(.transcribing(let sessionMode, let targetApp)) = stopResult else { return }
        recordingID = nil
        recordingLimitTask?.cancel()
        recordingLimitTask = nil

        pillViewModel.update(status: .transcribing)
        let samples = audioCapture.stopCapture()

        guard !samples.isEmpty else {
            stateMachine.reset()
            pillViewModel.update(status: .idle)
            return
        }

        processingTask?.cancel()
        processingTask = Task {
            do {
                let transcription = try await transcriptionService.transcribe(samples: samples)
                guard !Task.isCancelled else { return }
                let aliasedText = vocabularyStore.applyAliases(to: transcription.text)
                guard !aliasedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    stateMachine.reset()
                    pillViewModel.update(status: .idle)
                    return
                }

                var transcript = Transcript(
                    rawText: aliasedText,
                    mode: sessionMode,
                    durationSeconds: transcription.durationSeconds,
                    targetApplication: targetApp
                )

                // Save raw text before refinement or insertion can fail.
                safetyBuffer.recordRaw(transcript)
                var textToDeliver = aliasedText

                if sessionMode == .refined {
                    guard case .success = stateMachine.startRefining(rawText: aliasedText) else { return }
                    pillViewModel.update(status: .refining)
                    let result = await refinementService.refine(rawText: aliasedText)
                    guard !Task.isCancelled else { return }
                    let refinedText = result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? aliasedText : result
                    transcript.refinedText = refinedText
                    safetyBuffer.updateRefined(id: transcript.id, refinedText: refinedText)
                    textToDeliver = refinedText
                }

                guard case .success = stateMachine.startInserting(text: textToDeliver) else { return }
                pillViewModel.update(status: .inserting)
                let insertionResult = insertionService.insert(
                    text: textToDeliver,
                    targetApp: targetApp,
                    forceClipboard: false
                )

                switch insertionResult {
                case .success:
                    statsStore.recordSession(
                        mode: sessionMode,
                        audioDuration: transcript.durationSeconds,
                        wordCount: transcript.wordCount
                    )
                    if config.playSounds {
                        playSound?()
                    }
                    stateMachine.complete()
                    pillViewModel.update(status: .idle)
                case .failure(let reason):
                    showFailure(reason)
                }
            } catch {
                guard !Task.isCancelled else { return }
                showFailure(.transcriptionFailed)
            }
        }
    }

    public func reinsertLast() {
        guard stateMachine.state.isIdle, let last = safetyBuffer.lastTranscript,
              !last.textToInsert.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let currentTarget = targetValidator.currentTarget()
        guard case .success = stateMachine.startReinserting(text: last.textToInsert, targetApp: currentTarget) else { return }
        resetTask?.cancel()
        resetTask = nil
        pillViewModel.update(status: .inserting)
        switch insertionService.insert(text: last.textToInsert, targetApp: currentTarget, forceClipboard: false) {
        case .success:
            stateMachine.complete()
            pillViewModel.update(status: .idle)
        case .failure(let reason):
            showFailure(reason)
        }
    }

    private func showFailure(_ reason: SessionFailureReason) {
        stateMachine.fail(reason: reason)
        pillViewModel.update(status: .failed(reason: reason))
        scheduleReset()
    }

    private func scheduleReset(after seconds: Double = 1.2) {
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            catch { return }
            guard let self, case .failed = self.stateMachine.state else { return }
            self.stateMachine.reset()
            self.pillViewModel.update(status: .idle)
            self.resetTask = nil
        }
    }
}
