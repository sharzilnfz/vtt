import AppKit
import CoreGraphics

public enum TargetValidationResult: Sendable, Equatable {
    case valid
    case appChanged(expected: TargetApplication?, actual: TargetApplication?)
}

public protocol TargetValidating: Sendable {
    func currentTarget() -> TargetApplication?
    func validate(against expected: TargetApplication?) -> TargetValidationResult
}

public final class TargetValidator: TargetValidating {
    public init() {}

    public func currentTarget() -> TargetApplication? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        let (windowNumber, windowTitle) = Self.frontWindowInfo(pid: frontApp.processIdentifier)
        let isTerminalAX = Self.detectTerminalAX(pid: frontApp.processIdentifier)

        return TargetApplication(
            bundleIdentifier: frontApp.bundleIdentifier,
            processIdentifier: frontApp.processIdentifier,
            localizedName: frontApp.localizedName,
            windowNumber: windowNumber,
            windowTitle: windowTitle,
            isTerminalExplicit: isTerminalAX ? true : nil
        )
    }

    private static func frontWindowInfo(pid: Int32) -> (number: Int?, title: String?) {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in list {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == pid,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let number = window[kCGWindowNumber as String] as? Int else {
                continue
            }
            let title = window[kCGWindowName as String] as? String
            return (number, title)
        }
        return (nil, nil)
    }

    private static func detectTerminalAX(pid: Int32) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let appRef = AXUIElementCreateApplication(pid)
        var focusedElementValue: AnyObject?
        let axResult = AXUIElementCopyAttributeValue(appRef, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
        guard axResult == .success, let element = focusedElementValue else {
            return false
        }
        let axElement = element as! AXUIElement

        var roleDescValue: AnyObject?
        if AXUIElementCopyAttributeValue(axElement, kAXRoleDescriptionAttribute as CFString, &roleDescValue) == .success,
           let roleDesc = roleDescValue as? String,
           roleDesc.localizedCaseInsensitiveContains("terminal") {
            return true
        }

        var descValue: AnyObject?
        if AXUIElementCopyAttributeValue(axElement, kAXDescriptionAttribute as CFString, &descValue) == .success,
           let desc = descValue as? String,
           desc.localizedCaseInsensitiveContains("terminal") {
            return true
        }

        return false
    }

    public func validate(against expected: TargetApplication?) -> TargetValidationResult {
        guard let expected else {
            return .valid
        }
        guard let current = currentTarget() else {
            return .valid
        }
        if expected.matches(other: current) {
            return .valid
        }
        // If the expected target was Utter itself (e.g. user was in Utter setup window when pressing shortcut),
        // allow typing into whatever external application is currently active.
        if expected.bundleIdentifier == Bundle.main.bundleIdentifier ||
           expected.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return .valid
        }
        return .appChanged(expected: expected, actual: current)
    }
}
