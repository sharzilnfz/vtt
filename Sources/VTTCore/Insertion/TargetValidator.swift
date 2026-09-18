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
        return TargetApplication(
            bundleIdentifier: frontApp.bundleIdentifier,
            processIdentifier: frontApp.processIdentifier,
            localizedName: frontApp.localizedName,
            windowNumber: Self.frontWindowNumber(pid: frontApp.processIdentifier)
        )
    }

    private static func frontWindowNumber(pid: Int32) -> Int? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in list {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == pid,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let number = window[kCGWindowNumber as String] as? Int else {
                continue
            }
            return number
        }
        return nil
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
        // If the expected target was VTT itself (e.g. user was in VTT setup window when pressing shortcut),
        // allow typing into whatever external application is currently active.
        if expected.bundleIdentifier == Bundle.main.bundleIdentifier ||
           expected.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return .valid
        }
        return .appChanged(expected: expected, actual: current)
    }
}
