import AppKit
import Combine
import UtterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ModifierKeyMonitorDelegate {
    private var coordinator: DictationCoordinator!
    private var menuBarManager: MenuBarManager!
    private var indicatorController: IndicatorPanelController!
    private var setupController: SetupWindowController!
    private var keyMonitor: ModifierKeyMonitor!
    private var sttStore: STTModelStore!
    private var provider: FluidAudioProvider!
    private var modelState: ModelLoadState = .loading
    private var modelLoadTask: Task<Void, Never>?
    private var statusObservation: AnyCancellable?
    private var admittedMode: DictationMode?
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppMenuBuilder.install()
        sttStore = STTModelStore()
        Task.detached(priority: .background) {
            await FluidAudioProvider.removeLegacyCaches()
        }
        provider = FluidAudioProvider(selection: sttStore.selection)
        let pillViewModel = PillViewModel()
        let refinementSettings = RefinementSettingsStore()
        let historyDB = try? HistoryDatabase(fileURL: HistoryDatabase.defaultDatabaseURL)
        let persistentSafetyBuffer = SafetyBuffer(database: historyDB)
        let persistentStatsStore = StatsStore(database: historyDB)
        let persistentVocabularyStore = VocabularyStore(fileURL: VocabularyStore.defaultFileURL)
        coordinator = DictationCoordinator(
            safetyBuffer: persistentSafetyBuffer,
            statsStore: persistentStatsStore,
            vocabularyStore: persistentVocabularyStore,
            transcriptionService: provider,
            refinementService: RefinementService(settings: refinementSettings),
            pillViewModel: pillViewModel
        )
        coordinator.onTranscriptUpdated = { [weak self] _ in
            self?.setupController.dashboardState.refreshActivitiesFromTranscripts()
            self?.refreshUI()
        }
        indicatorController = IndicatorPanelController(viewModel: pillViewModel)
        menuBarManager = MenuBarManager()
        setupController = SetupWindowController(
            safetyBuffer: coordinator.safetyBuffer,
            settings: refinementSettings,
            statsStore: coordinator.statsStore,
            vocabularyStore: coordinator.vocabularyStore,
            coordinator: coordinator,
            sttStore: sttStore
        )
        keyMonitor = ModifierKeyMonitor()
        keyMonitor.delegate = self
        keyMonitor.startMonitoring()

        menuBarManager.onQuit = { NSApp.terminate(nil) }
        menuBarManager.onOpenSettings = { [weak self] in self?.setupController.present() }
        menuBarManager.onRecoverTranscripts = { [weak self] in self?.setupController.present(recovery: true) }
        menuBarManager.onCopyLast = { [weak self] in self?.setupController.copyLast() }
        menuBarManager.onRetryModel = { [weak self] in self?.preloadModel() }
        menuBarManager.onRefresh = { [weak self] in self?.refreshUI() }
        setupController.onRetryModel = { [weak self] in self?.preloadModel() }
        setupController.onPermissionsChanged = { [weak self] in self?.refreshUI() }
        setupController.dashboardState.onSpeechModelChanged = { [weak self] selection in
            self?.switchSpeechModel(to: selection)
        }
        installMemoryPressureValve()
        statusObservation = pillViewModel.$status
            .sink { [weak self] status in
                guard let self else { return }
                var stateChanged = false
                switch status {
                case .recording(let level):
                    if !self.setupController.dashboardState.isRecording {
                        self.setupController.dashboardState.isRecording = true
                        self.setupController.dashboardState.isTranscribing = false
                        stateChanged = true
                    }
                    if self.setupController.window?.isVisible == true {
                        self.setupController.dashboardState.audioLevel = level
                    }
                case .transcribing, .refining, .inserting:
                    if !self.setupController.dashboardState.isTranscribing {
                        self.setupController.dashboardState.isRecording = false
                        self.setupController.dashboardState.isTranscribing = true
                        stateChanged = true
                    }
                case .idle, .failed:
                    if self.setupController.dashboardState.isRecording || self.setupController.dashboardState.isTranscribing {
                        self.setupController.dashboardState.isRecording = false
                        self.setupController.dashboardState.isTranscribing = false
                        stateChanged = true
                    }
                }
                if stateChanged {
                    self.refreshUI()
                }
            }

        refreshUI()
        preloadModel()
        setupController.present()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            setupController.present()
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard setupController != nil else { return }
        refreshUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        modelLoadTask?.cancel()
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        keyMonitor?.stopMonitoring()
        if coordinator?.audioCapture.isCapturing == true {
            _ = coordinator.audioCapture.stopCapture()
        }
    }

    private func installMemoryPressureValve() {
        memoryPressureSource?.cancel()
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.coordinator.stateMachine.state.isIdle else { return }
            Task { @MainActor in
                await self.provider.unload()
                if self.modelState == .ready {
                    self.modelState = .loading
                    self.refreshUI()
                }
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func switchSpeechModel(to selection: STTModelSelection) {
        modelLoadTask?.cancel()
        modelLoadTask = nil
        modelState = .loading
        setupController.dashboardState.refreshSpeechModelDisplay()
        refreshUI()
        Task {
            await provider.updateSelection(selection)
            await provider.unload()
            preloadModel()
        }
    }

    private func preloadModel() {
        guard modelLoadTask == nil, modelState != .ready, let provider else { return }
        modelState = .loading
        refreshUI()
        modelLoadTask = Task { [weak self, provider] in
            do {
                _ = try await provider.loadIfNeeded()
                guard !Task.isCancelled else { return }
                self?.modelState = .ready
            } catch {
                guard !Task.isCancelled else { return }
                self?.modelState = .failed(error.localizedDescription)
            }
            self?.modelLoadTask = nil
            self?.refreshUI()
        }
    }

    private func refreshUI() {
        if keyMonitor != nil && !keyMonitor.isRunning {
            keyMonitor.startMonitoring()
        }
        menuBarManager.update(
            modelState: modelState,
            permissionsReady: setupController.permissionsReady,
            hasTranscript: coordinator.safetyBuffer.lastTranscript != nil,
            lastTranscript: coordinator.safetyBuffer.lastTranscript,
            statsStore: coordinator.statsStore
        )
        setupController.update(modelState: modelState)
    }

    func didPressShortcut(mode: DictationMode) {
        guard admittedMode == nil, coordinator.stateMachine.state.isIdle else { return }
        guard modelState == .ready, setupController.permissionsReady else {
            refreshUI()
            setupController.present()
            return
        }
        coordinator.startSession(mode: mode)
        if coordinator.stateMachine.state.isRecording { admittedMode = mode }
    }

    func didReleaseShortcut(mode: DictationMode) {
        guard let admittedMode, admittedMode == mode else { return }
        self.admittedMode = nil
        coordinator.stopSession(mode: admittedMode)
    }

    func didTriggerReinsert() {
        guard coordinator.stateMachine.state.isIdle else { return }
        guard setupController.permissionsReady else {
            setupController.present(recovery: true)
            return
        }
        coordinator.reinsertLast()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
