import AppKit
@testable import UtterCore

private struct HotkeyRegressionFailure: Error {
    let message: String
}

@MainActor
private final class HotkeyRegressionDelegate: ModifierKeyMonitorDelegate {
    var actions: [ShortcutKeyAction] = []
    var onReplay: (() -> Void)?

    func didPressShortcut(mode: DictationMode) { actions.append(.start(mode)) }
    func didReleaseShortcut(mode: DictationMode) { actions.append(.stop(mode)) }
    func didTriggerReinsert() {
        actions.append(.reinsert)
        onReplay?()
    }
}

@MainActor
private final class HotkeyRegressionReceiver: NSTextView {
    var keys: [UInt16] = []
    var flags: [NSEvent.ModifierFlags] = []
    var commands: [String] = []
    var pasteCount = 0

    override func paste(_ sender: Any?) {
        pasteCount += 1
    }

    override func keyDown(with event: NSEvent) {
        keys.append(event.keyCode)
        flags.append(event.modifierFlags)
        interpretKeyEvents([event])
    }

    override func doCommand(by selector: Selector) {
        commands.append(NSStringFromSelector(selector))
    }
}

@MainActor
func runHotkeyMonitorRegressions() async throws {
    func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw HotkeyRegressionFailure(message: message) }
    }
    try check(CGPreflightPostEventAccess() && AXIsProcessTrusted(), "Requires event-posting and Accessibility permission")
    let app = NSApplication.shared
    let previousApp = NSWorkspace.shared.frontmostApplication
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let receiver = HotkeyRegressionReceiver(frame: window.contentView!.bounds)
    window.contentView = receiver
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(receiver)
    let source = CGEventSource(stateID: .privateState)!
    let ctrl = CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x01)
    let option = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x20)
    let command = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x08)
    func post(_ type: CGEventType, _ key: CGKeyCode, _ flags: CGEventFlags, repeatKey: Bool = false) {
        let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: type == .keyDown)!
        event.type = type
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
        event.postToPid(getpid())
    }
    func send(_ type: CGEventType, _ key: CGKeyCode, _ flags: CGEventFlags, repeatKey: Bool = false) async throws {
        post(type, key, flags, repeatKey: repeatKey)
        try await Task.sleep(for: .milliseconds(80))
    }
    var tap: CFMachPort?
    var callback: CGEventTapCallBack?
    var context: UnsafeMutableRawPointer?
    let monitor = ModifierKeyMonitor(eventTapFactory: { mask, handler, userInfo in
        callback = handler
        context = userInfo
        tap = CGEvent.tapCreateForPid(pid: getpid(), place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: handler, userInfo: userInfo)
        return tap
    })
    let delegate = HotkeyRegressionDelegate()
    monitor.delegate = delegate
    defer {
        monitor.stopMonitoring()
        window.close()
        if let previousApp, previousApp.processIdentifier != getpid() {
            previousApp.activate(options: [])
        }
        _ = app
    }
    try check(monitor.startMonitoring(), "Could not create PID-scoped production monitor")
    try check(monitor.startMonitoring(), "Starting twice must remain enabled")

    try await send(.flagsChanged, 59, ctrl)
    try await send(.keyDown, 9, ctrl)
    try await send(.keyDown, 9, ctrl, repeatKey: true)
    try check(delegate.actions.isEmpty && receiver.keys.isEmpty, "Ctrl+V must be suppressed without replaying on key-down")
    try await send(.keyUp, 9, ctrl)
    try check(delegate.actions.isEmpty, "V release must wait for Control release")
    try await send(.flagsChanged, 59, [])
    try check(delegate.actions == [.reinsert] && receiver.commands.isEmpty, "One replay after release, no native pageDown")

    delegate.actions = []
    try await send(.keyDown, 9, ctrl)
    try await send(.flagsChanged, 59, [])
    try check(delegate.actions.isEmpty, "Control-first release must wait for V release")
    try await send(.keyUp, 9, [])
    try check(delegate.actions == [.reinsert], "Key-down flags must recognize Ctrl+V without flagsChanged")

    delegate.actions = []
    delegate.onReplay = {
        post(.flagsChanged, 55, command)
        post(.keyDown, 9, command)
        post(.keyUp, 9, command)
        post(.flagsChanged, 55, [])
    }
    delegate.actions = []
    delegate.onReplay = {
        post(.flagsChanged, 55, command)
        post(.keyDown, 9, command)
        post(.keyUp, 9, command)
        post(.flagsChanged, 55, [])
    }
    for _ in 0..<2 {
        try await send(.keyDown, 9, ctrl)
        try await send(.keyUp, 9, ctrl)
        try await send(.flagsChanged, 59, [])
        try await Task.sleep(for: .milliseconds(160))
    }
    try check(delegate.actions == [.reinsert, .reinsert], "Synthetic paste flags must not break the next replay or cause recursion")
    try checkSyntheticSuppressDecisions(source: source, ctrl: ctrl, command: command)
    delegate.onReplay = nil
    delegate.actions = []

    for flags: CGEventFlags in [[], command, ctrl.union(.maskShift), ctrl.union(option), CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x2000)] {
        try await send(.keyDown, 9, flags)
        try await send(.keyUp, 9, flags)
    }
    try await send(.keyDown, 0, ctrl)
    try await send(.keyUp, 0, ctrl)
    try await send(.flagsChanged, 59, [])
    try check(delegate.actions.isEmpty, "Nonshortcuts, right Control, and other keys must not trigger actions")
    try checkPassthroughSuppressDecisions(ctrl: ctrl, command: command, option: option)

    try await send(.flagsChanged, 58, ctrl.union(option))
    try await send(.flagsChanged, 55, ctrl.union(option).union(command))
    try await send(.flagsChanged, 59, option.union(command))
    try await send(.flagsChanged, 58, command)
    try await send(.flagsChanged, 55, [])
    try check(delegate.actions == [.start(.direct), .stop(.direct), .start(.refined), .stop(.refined)], "Existing latched recording chords must survive tap migration")

    delegate.actions = []
    try await send(.keyDown, 9, ctrl)
    monitor.stopMonitoring()
    try check(monitor.startMonitoring(), "Stopped monitor must restart")
    try await send(.keyUp, 9, [])
    try check(delegate.actions.isEmpty, "Stopping cancels pending replay")
    for type in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
        CGEvent.tapEnable(tap: tap!, enable: false)
        _ = callback?(OpaquePointer(context!), type, CGEvent(source: source)!, context)
        try check(CGEvent.tapIsEnabled(tap: tap!), "Disabled tap must be reenabled")
    }
    try await send(.keyDown, 9, ctrl)
    try await send(.keyUp, 9, [])
    try check(delegate.actions == [.reinsert], "Reenabled monitor must replay again")
    try checkCommandVPassesThrough(command: command)
    print("Hotkey monitor regressions passed: native suppression, release timing, flag snapshots, synthetic paste, passthrough, chords, restart, tap recovery")
}

private struct StubTap {
    let callback: CGEventTapCallBack
    let context: UnsafeMutableRawPointer?
    let monitor: ModifierKeyMonitor
    let delegate: HotkeyRegressionDelegate
}

@MainActor
private func makeStubTap() -> StubTap {
    var callback: CGEventTapCallBack!
    var context: UnsafeMutableRawPointer?
    let monitor = ModifierKeyMonitor(eventTapFactory: { _, handler, userInfo in
        callback = handler
        context = userInfo
        return CFMachPortCreate(kCFAllocatorDefault, nil, nil, nil)
    })
    let delegate = HotkeyRegressionDelegate()
    monitor.delegate = delegate
    _ = monitor.startMonitoring()
    return StubTap(callback: callback, context: context, monitor: monitor, delegate: delegate)
}

@MainActor
private func invokeStub(_ stub: StubTap, type: CGEventType, key: CGKeyCode, flags: CGEventFlags, repeatKey: Bool = false) -> (suppressed: Bool, seenFlags: CGEventFlags) {
    let event = CGEvent(source: nil)!
    event.type = type
    event.flags = flags
    event.setIntegerValueField(.keyboardEventKeycode, value: Int64(key))
    event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
    let seen = event.flags
    let result = stub.callback(OpaquePointer(stub.context!), type, event, stub.context)
    return (result == nil, seen)
}

@MainActor
private func checkSyntheticSuppressDecisions(source: CGEventSource, ctrl: CGEventFlags, command: CGEventFlags) throws {
    func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw HotkeyRegressionFailure(message: message) }
    }
    let stub = makeStubTap()
    defer { stub.monitor.stopMonitoring() }
    let maskCommand = CGEventFlags.maskCommand.rawValue
    let maskControl = CGEventFlags.maskControl.rawValue
    for _ in 0..<2 {
        let down = invokeStub(stub, type: .keyDown, key: 9, flags: ctrl)
        try check(down.suppressed, "Original Ctrl+V key-down must be swallowed at the tap")
        let up = invokeStub(stub, type: .keyUp, key: 9, flags: ctrl)
        try check(up.suppressed, "Original Ctrl+V key-up must be swallowed at the tap")
        _ = invokeStub(stub, type: .flagsChanged, key: 59, flags: [])
        try check(stub.delegate.actions.last == .reinsert, "Release must fire one replay")
        let synthDown = invokeStub(stub, type: .keyDown, key: 9, flags: command)
        try check(!synthDown.suppressed, "Synthetic Command+V key-down must pass through")
        try check((synthDown.seenFlags.rawValue & maskCommand) != 0, "Synthetic key-down must keep Command intact")
        try check((synthDown.seenFlags.rawValue & maskControl) == 0 && (synthDown.seenFlags.rawValue & 0x01) == 0, "Synthetic key-down must have Control cleared")
        let synthUp = invokeStub(stub, type: .keyUp, key: 9, flags: command)
        try check(!synthUp.suppressed, "Synthetic Command+V key-up must pass through")
    }
    try check(stub.delegate.actions == [.reinsert, .reinsert], "Synthetic paste flags must not cause recursion")
}

@MainActor
private func checkPassthroughSuppressDecisions(ctrl: CGEventFlags, command: CGEventFlags, option: CGEventFlags) throws {
    func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw HotkeyRegressionFailure(message: message) }
    }
    let stub = makeStubTap()
    defer { stub.monitor.stopMonitoring() }
    for flags in [[CGEventFlags](), [command], [ctrl.union(.maskShift)], [ctrl.union(option)], [CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x2000)]].flatMap({ $0 }) {
        let down = invokeStub(stub, type: .keyDown, key: 9, flags: flags)
        let up = invokeStub(stub, type: .keyUp, key: 9, flags: flags)
        try check(!down.suppressed && !up.suppressed, "Nonshortcuts, right Control, and other keys must pass unchanged")
    }
    let zeroDown = invokeStub(stub, type: .keyDown, key: 0, flags: ctrl)
    let zeroUp = invokeStub(stub, type: .keyUp, key: 0, flags: ctrl)
    try check(!zeroDown.suppressed && !zeroUp.suppressed, "Other keys must pass unchanged")
    try check(stub.delegate.actions.isEmpty, "Passthrough keys must not trigger actions")
}

@MainActor
private func checkCommandVPassesThrough(command: CGEventFlags) throws {
    func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw HotkeyRegressionFailure(message: message) }
    }
    let stub = makeStubTap()
    defer { stub.monitor.stopMonitoring() }
    let down = invokeStub(stub, type: .keyDown, key: 9, flags: command)
    let up = invokeStub(stub, type: .keyUp, key: 9, flags: command)
    try check(!down.suppressed && !up.suppressed, "Command+V must pass through the tap without touching the reinsert path")
    try check(stub.delegate.actions.isEmpty, "Command+V must not trigger reinsert")
}

@MainActor
func runPopoverShortcutRegressions() throws {
    func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw HotkeyRegressionFailure(message: message) }
    }
    func keyEvent(flags: NSEvent.ModifierFlags, chars: String, ignoring: String, keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: chars,
            charactersIgnoringModifiers: ignoring,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
    let commandComma = keyEvent(flags: [.command], chars: ",", ignoring: ",", keyCode: 43)
    try check(MenuBarManager.shortcut(for: commandComma) == .openDashboard, "Command comma must open the dashboard")
    let commandQ = keyEvent(flags: [.command], chars: "q", ignoring: "q", keyCode: 12)
    try check(MenuBarManager.shortcut(for: commandQ) == nil, "Command Q must stay on the main menu quit path")
    let controlV = keyEvent(flags: [.control], chars: "v", ignoring: "v", keyCode: 9)
    try check(MenuBarManager.shortcut(for: controlV) == nil, "Control V stays owned by the reinsert tap")
    let plainComma = keyEvent(flags: [], chars: ",", ignoring: ",", keyCode: 43)
    try check(MenuBarManager.shortcut(for: plainComma) == nil, "Comma without Command must not open the dashboard")
    let shiftCommandComma = keyEvent(flags: [.command, .shift], chars: "<", ignoring: ",", keyCode: 43)
    try check(MenuBarManager.shortcut(for: shiftCommandComma) == nil, "Shift Command comma must not open the dashboard")
}

@MainActor
func runHardwareEventFlagRegressions() throws {
    func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw HotkeyRegressionFailure(message: message) }
    }
    var callback: CGEventTapCallBack?
    var context: UnsafeMutableRawPointer?
    let monitor = ModifierKeyMonitor(eventTapFactory: { mask, handler, userInfo in
        callback = handler
        context = userInfo
        return CFMachPortCreate(kCFAllocatorDefault, nil, nil, nil)
    })
    let delegate = HotkeyRegressionDelegate()
    monitor.delegate = delegate
    guard monitor.startMonitoring() else {
        throw HotkeyRegressionFailure(message: "Failed to initialize test monitor")
    }
    defer { monitor.stopMonitoring() }

    func simulate(_ type: CGEventType, _ flags: CGEventFlags, keycode: Int64 = 0) {
        let event = CGEvent(source: nil)!
        event.type = type
        event.flags = flags
        event.setIntegerValueField(.keyboardEventKeycode, value: keycode)
        _ = callback?(OpaquePointer(context!), type, event, context)
    }

    // 1. Hardware flag test for Control + Option: flags = 0x200C0000 (maskControl + maskAlternate, NO device bits 0x01/0x20)
    let hardwareCtrlOpt = CGEventFlags(rawValue: 0x200C0000)
    simulate(.flagsChanged, hardwareCtrlOpt, keycode: 58)
    try check(delegate.actions == [.start(.direct)], "Hardware Control+Option flags (0x200C0000) must start direct dictation")

    // Release Option, keep Control: flags = 0x20040000
    let hardwareCtrlOnly = CGEventFlags(rawValue: 0x20040000)
    simulate(.flagsChanged, hardwareCtrlOnly, keycode: 58)
    try check(delegate.actions == [.start(.direct), .stop(.direct)], "Releasing Option must stop direct dictation")

    // 2. Hardware flag test for Option + Command: flags = 0x20180000 (maskAlternate + maskCommand, NO device bits 0x20/0x08)
    delegate.actions = []
    let hardwareOptCmd = CGEventFlags(rawValue: 0x20180000)
    simulate(.flagsChanged, hardwareOptCmd, keycode: 55)
    try check(delegate.actions == [.start(.refined)], "Hardware Option+Command flags (0x20180000) must start refined dictation")

    // Release all
    simulate(.flagsChanged, [], keycode: 55)
    try check(delegate.actions == [.start(.refined), .stop(.refined)], "Releasing Option+Command must stop refined dictation")

    // 3. Right Control test: 0x2000 bit explicitly present without 0x01
    delegate.actions = []
    let rightCtrlOpt = CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | 0x2000)
    simulate(.flagsChanged, rightCtrlOpt, keycode: 62)
    try check(delegate.actions.isEmpty, "Explicit Right Control + Option must not trigger direct dictation")

    // 4. Hardware Ctrl+V reinsert test: Control down, V down, V up, Control up
    delegate.actions = []
    simulate(.flagsChanged, hardwareCtrlOnly, keycode: 59)
    simulate(.keyDown, hardwareCtrlOnly, keycode: 9)
    simulate(.keyUp, hardwareCtrlOnly, keycode: 9)
    simulate(.flagsChanged, [], keycode: 59)
    try check(delegate.actions == [.reinsert], "Hardware Ctrl+V must trigger reinsert after release")
}
