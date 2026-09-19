import AppKit
import Combine
import SwiftUI

@MainActor
public final class IndicatorPanelController: NSObject {
    private let panel: NSPanel
    private let viewModel: PillViewModel
    private var observation: AnyCancellable?

    public init(viewModel: PillViewModel) {
        self.viewModel = viewModel
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 88, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView: IndicatorPillView(viewModel: viewModel))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView

        observation = viewModel.$status.sink { [weak self] status in
            self?.render(status)
        }
    }

    private func render(_ status: PillStatus) {
        switch status {
        case .idle:
            hide()
        case .recording, .transcribing, .refining, .inserting, .failed:
            presentPanel()
        }
    }

    public func show() {
        guard viewModel.status.isVisible else { return }
        render(viewModel.status)
    }

    private func presentPanel() {
        if !panel.isVisible {
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 68))
            }
            panel.orderFrontRegardless()
        }
    }

    public func hide() {
        panel.orderOut(nil)
    }
}
