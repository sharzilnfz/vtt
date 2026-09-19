import AppKit
import SwiftUI

@MainActor
public final class SetupWindowController: NSWindowController {
    public let dashboardState: DashboardState

    public var onRetryModel: (() -> Void)? {
        didSet {
            dashboardState.onRetryModel = onRetryModel
        }
    }

    public var onPermissionsChanged: (() -> Void)? {
        didSet {
            dashboardState.onPermissionsChanged = onPermissionsChanged
        }
    }

    public var permissionsReady: Bool {
        dashboardState.permissionsReady
    }

    public init(
        safetyBuffer: SafetyBuffer,
        settings: RefinementSettingsStore,
        statsStore: StatsStore? = nil,
        vocabularyStore: VocabularyStore? = nil,
        coordinator: DictationCoordinator? = nil,
        sttStore: STTModelStore? = nil
    ) {
        self.dashboardState = DashboardState(
            safetyBuffer: safetyBuffer,
            settingsStore: settings,
            statsStore: statsStore,
            vocabularyStore: vocabularyStore,
            coordinator: coordinator,
            sttStore: sttStore
        )

        let fixedSize = NSSize(width: 660, height: 550)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: fixedSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Utter"
        window.isRestorable = false
        window.setContentSize(fixedSize)
        window.minSize = fixedSize
        window.maxSize = fixedSize
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: window)

        dashboardState.onRetryModel = { [weak self] in
            self?.onRetryModel?()
        }
        dashboardState.onPermissionsChanged = { [weak self] in
            self?.onPermissionsChanged?()
        }

        let hostingView = NSHostingView(rootView: DashboardView(state: dashboardState))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        guard let content = window.contentView else { return }
        content.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: content.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        window.setFrame(NSRect(origin: window.frame.origin, size: fixedSize), display: true)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    public func present(recovery: Bool = false) {
        dashboardState.refreshPermissions()
        dashboardState.refreshActivitiesFromTranscripts()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    public func update(modelState: ModelLoadState) {
        if dashboardState.modelState != modelState {
            dashboardState.modelState = modelState
        }
        guard window?.isVisible == true else { return }
        dashboardState.refreshPermissions()
        dashboardState.refreshActivitiesFromTranscripts()
    }

    public func refreshPermissions() {
        dashboardState.refreshPermissions()
    }

    public func copyLast() {
        dashboardState.copyLastTranscript()
    }
}
