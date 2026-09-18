import AppKit
import SwiftUI

public enum ModelLoadState: Equatable, Sendable {
    case loading
    case ready
    case failed(String)

    public var displayText: String {
        switch self {
        case .loading: return "Loading"
        case .ready: return "Ready"
        case .failed: return "Failed"
        }
    }
}

public enum PopoverShortcut: Sendable, Equatable {
    case openDashboard
}

@MainActor
public final class MenuBarManager: NSObject, NSMenuDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var fallbackMenu: NSMenu!
    private let modelItem = NSMenuItem(title: "Loading", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Setup needed", action: nil, keyEquivalent: "")
    private var retryItem: NSMenuItem!
    private var copyItem: NSMenuItem!
    private let shortcutItem = NSMenuItem(title: "Keys off", action: nil, keyEquivalent: "")

    private var currentModelState: ModelLoadState = .loading
    private var currentPermissionsReady: Bool = false
    private var lastTranscript: Transcript?
    private var statsStore: StatsStore?
    private var isDarkMode: Bool = true
    private var shortcutMonitor: Any?

    public var onQuit: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onRetryModel: (() -> Void)?
    public var onCopyLast: (() -> Void)?
    public var onRecoverTranscripts: (() -> Void)?
    public var onRefresh: (() -> Void)?

    public override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "VTT Dictation")
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Setup fallback system menu
        fallbackMenu = NSMenu()
        fallbackMenu.autoenablesItems = false
        fallbackMenu.delegate = self
        let heading = NSMenuItem(title: "VTT", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        modelItem.isEnabled = false
        permissionItem.isEnabled = false
        fallbackMenu.addItem(heading)
        fallbackMenu.addItem(modelItem)
        fallbackMenu.addItem(permissionItem)
        shortcutItem.isEnabled = false
        fallbackMenu.addItem(shortcutItem)
        retryItem = NSMenuItem(title: "Retry", action: #selector(retryClicked), keyEquivalent: "")
        retryItem.isHidden = true
        fallbackMenu.addItem(retryItem)
        fallbackMenu.addItem(.separator())
        fallbackMenu.addItem(NSMenuItem(title: "Setup", action: #selector(openSettingsClicked), keyEquivalent: ","))
        fallbackMenu.addItem(NSMenuItem(title: "History", action: #selector(recoveryClicked), keyEquivalent: ""))
        copyItem = NSMenuItem(title: "Copy last", action: #selector(copyClicked), keyEquivalent: "")
        copyItem.isEnabled = false
        fallbackMenu.addItem(copyItem)
        fallbackMenu.addItem(.separator())
        fallbackMenu.addItem(NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q"))
        for item in fallbackMenu.items { item.target = self }

        // Setup Modern Popover Window
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        updatePopover(force: true)
    }

    public func setContext(statsStore: StatsStore?, lastTranscript: Transcript?) {
        self.statsStore = statsStore
        self.lastTranscript = lastTranscript
        updatePopover(force: false)
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) == true) {
            statusItem?.menu = fallbackMenu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            onRefresh?()
            updatePopover(force: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            installShortcutMonitor()
        }
    }

    public func popoverDidClose(_ notification: Notification) {
        removeShortcutMonitor()
    }

    public nonisolated static func shortcut(for event: NSEvent) -> PopoverShortcut? {
        guard event.type == .keyDown,
              event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.control),
              !event.modifierFlags.contains(.option),
              !event.modifierFlags.contains(.shift),
              (event.charactersIgnoringModifiers ?? "") == "," else { return nil }
        return .openDashboard
    }

    private func installShortcutMonitor() {
        guard shortcutMonitor == nil else { return }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if Self.shortcut(for: event) == .openDashboard {
                self.popover.performClose(nil)
                self.openSettingsClicked()
                return nil
            }
            return event
        }
    }

    private func removeShortcutMonitor() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }
    }

    private func updatePopover(force: Bool = false) {
        guard force || popover.isShown else { return }
        let view = MenuBarPopoverView(
            modelState: currentModelState,
            permissionsReady: currentPermissionsReady,
            lastTranscript: lastTranscript,
            stats: statsStore?.currentStats,
            isDark: isDarkMode,
            onOpenDashboard: { [weak self] in
                self?.popover.performClose(nil)
                self?.openSettingsClicked()
            },
            onCopyLast: { [weak self] in
                self?.copyClicked()
            },
            onRetryModel: { [weak self] in
                self?.retryClicked()
            },
            onQuit: { [weak self] in
                self?.quitClicked()
            },
            onToggleTheme: { [weak self] in
                guard let self else { return }
                self.isDarkMode.toggle()
                self.updatePopover(force: true)
            }
        )

        if let hosting = popover.contentViewController as? NSHostingController<MenuBarPopoverView> {
            hosting.rootView = view
        } else {
            let hosting = NSHostingController(rootView: view)
            popover.contentViewController = hosting
        }
    }

    public func update(
        modelState: ModelLoadState,
        permissionsReady: Bool,
        hasTranscript: Bool,
        shortcutsReady: Bool? = nil,
        lastTranscript: Transcript? = nil,
        statsStore: StatsStore? = nil
    ) {
        self.currentModelState = modelState
        self.currentPermissionsReady = permissionsReady
        if let lastTranscript { self.lastTranscript = lastTranscript }
        if let statsStore { self.statsStore = statsStore }

        modelItem.title = modelState.displayText
        modelItem.toolTip = modelState.displayText
        if case .failed = modelState { retryItem.isHidden = false } else { retryItem.isHidden = true }
        permissionItem.title = permissionsReady ? "Ready" : "Setup needed"
        if let shortcutsReady {
            shortcutItem.title = shortcutsReady ? "Keys on" : "Keys off"
        }
        statusItem?.button?.toolTip = "VTT"
        copyItem.isEnabled = hasTranscript

        updatePopover(force: false)
    }

    public func menuWillOpen(_ menu: NSMenu) { onRefresh?() }
    @objc private func openSettingsClicked() { onOpenSettings?() }
    @objc private func retryClicked() { onRetryModel?() }
    @objc private func copyClicked() { onCopyLast?() }
    @objc private func recoveryClicked() { onRecoverTranscripts?() }
    @objc private func quitClicked() {
        if let onQuit { onQuit() } else { NSApplication.shared.terminate(nil) }
    }
}
