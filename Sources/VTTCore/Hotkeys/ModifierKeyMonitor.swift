import AppKit

@MainActor
public protocol ModifierKeyMonitorDelegate: AnyObject {
    func didPressShortcut(mode: DictationMode)
    func didReleaseShortcut(mode: DictationMode)
    func didTriggerReinsert()
}

@MainActor
public final class ModifierKeyMonitor: NSObject {
    typealias EventTapFactory = (CGEventMask, CGEventTapCallBack, UnsafeMutableRawPointer) -> CFMachPort?

    private let makeEventTap: EventTapFactory
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var reducer = ShortcutKeyReducer()
    private var swallowedV = false
    private var pendingReinsert = false
    private var latestFlags: CGEventFlags = []
    private var generation = 0
    public weak var delegate: ModifierKeyMonitorDelegate?

    public override init() {
        makeEventTap = { mask, callback, context in
            CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: context
            )
        }
        super.init()
    }

    init(eventTapFactory: @escaping EventTapFactory) {
        makeEventTap = eventTapFactory
        super.init()
    }

    isolated deinit {
        if let eventTap { CFMachPortInvalidate(eventTap) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }

    public var isRunning: Bool {
        guard let eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    @discardableResult
    public func startMonitoring() -> Bool {
        if let eventTap {
            if !CGEvent.tapIsEnabled(tap: eventTap) {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return CGEvent.tapIsEnabled(tap: eventTap)
        }
        let mask = [CGEventType.flagsChanged, .keyDown, .keyUp].reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
        guard let tap = makeEventTap(mask, { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let suppress = MainActor.assumeIsolated {
                let monitor = Unmanaged<ModifierKeyMonitor>.fromOpaque(context).takeUnretainedValue()
                return monitor.handleEvent(type: type, event: event)
            }
            return suppress ? nil : Unmanaged.passUnretained(event)
        }, Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func stopMonitoring() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        reset()
    }

    private func reset() {
        generation += 1
        swallowedV = false
        pendingReinsert = false
        latestFlags = []
        for action in reducer.updateModifiers(leftControlDown: false, leftOptionDown: false, leftCommandDown: false) {
            deliver(action)
        }
        reducer = ShortcutKeyReducer()
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reset()
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return false
        }
        latestFlags = event.flags
        let rawFlags = latestFlags.rawValue
        let hasDeviceBits = (rawFlags & 0xFFFF) != 0
        let isRightControlOnly = hasDeviceBits && (rawFlags & 0x2000 != 0) && (rawFlags & 0x01 == 0)

        let controlDown = (latestFlags.contains(.maskControl) || (rawFlags & 0x01 != 0)) && !isRightControlOnly
        let optionDown = latestFlags.contains(.maskAlternate) || (rawFlags & 0x20 != 0) || (rawFlags & 0x40 != 0)
        let commandDown = latestFlags.contains(.maskCommand) || (rawFlags & 0x08 != 0) || (rawFlags & 0x10 != 0)

        if type == .flagsChanged {
            for action in reducer.updateModifiers(
                leftControlDown: controlDown,
                leftOptionDown: optionDown,
                leftCommandDown: commandDown
            ) {
                enqueue(action)
            }
        }

        var suppress = false
        if event.getIntegerValueField(.keyboardEventKeycode) == 9 {
            if type == .keyDown {
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                let isShortcut = controlDown
                    && latestFlags.intersection([.maskAlternate, .maskCommand, .maskShift, .maskSecondaryFn]).isEmpty
                if swallowedV {
                    suppress = true
                } else if isShortcut, !isRepeat {
                    swallowedV = true
                    pendingReinsert = true
                    suppress = true
                }
            } else if type == .keyUp, swallowedV {
                swallowedV = false
                suppress = true
            }
        }
        if pendingReinsert, !swallowedV, modifiersReleased {
            pendingReinsert = false
            deliver(.reinsert)
        }
        return suppress
    }

    private var modifiersReleased: Bool {
        latestFlags.intersection([.maskControl, .maskAlternate, .maskCommand, .maskShift, .maskSecondaryFn]).isEmpty
    }

    private func enqueue(_ action: ShortcutKeyAction) {
        deliver(action)
    }

    private func deliver(_ action: ShortcutKeyAction) {
        switch action {
        case .start(let mode): delegate?.didPressShortcut(mode: mode)
        case .stop(let mode): delegate?.didReleaseShortcut(mode: mode)
        case .reinsert: delegate?.didTriggerReinsert()
        }
    }
}
