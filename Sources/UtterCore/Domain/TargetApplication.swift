import Foundation

public struct TargetApplication: Codable, Sendable, Equatable {
    public let bundleIdentifier: String?
    public let processIdentifier: Int32
    public let localizedName: String?
    public let windowNumber: Int?
    public let windowTitle: String?
    public let isTerminalExplicit: Bool?

    public init(
        bundleIdentifier: String?,
        processIdentifier: Int32,
        localizedName: String?,
        windowNumber: Int? = nil,
        windowTitle: String? = nil,
        isTerminalExplicit: Bool? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.localizedName = localizedName
        self.windowNumber = windowNumber
        self.windowTitle = windowTitle
        self.isTerminalExplicit = isTerminalExplicit
    }

    public func matches(other: TargetApplication) -> Bool {
        guard processIdentifier == other.processIdentifier else { return false }
        if let bundleIdentifier, let otherBundle = other.bundleIdentifier,
           bundleIdentifier != otherBundle { return false }
        if let windowNumber, let otherWindow = other.windowNumber {
            return windowNumber == otherWindow
        }
        return true
    }

    public var isTerminal: Bool {
        if let explicit = isTerminalExplicit {
            return explicit
        }
        if let bundleId = bundleIdentifier?.lowercased() {
            let knownTerminals: Set<String> = [
                "com.apple.terminal",
                "com.googlecode.iterm2",
                "net.kovidgoyal.kitty",
                "dev.warp.warp-stable",
                "io.alacritty",
                "org.alacritty",
                "com.mitchellh.ghostty",
                "com.github.wez.wezterm",
                "co.zeit.hyper"
            ]
            if knownTerminals.contains(bundleId) {
                return true
            }

            let knownEditors: Set<String> = [
                "com.microsoft.vscode",
                "com.microsoft.vscodeinsiders",
                "com.visualstudio.code.oss",
                "com.todesktop.230313mzl4w4u92",
                "com.apple.dt.xcode",
                "com.sublimetext.4",
                "com.sublimetext.3"
            ]
            if knownEditors.contains(bundleId) || bundleId.hasPrefix("com.jetbrains.") {
                if let title = windowTitle?.lowercased(),
                   title.contains("terminal") || title.contains("zsh") || title.contains("bash") || title.contains("fish") {
                    return true
                }
            }
        }
        if let title = windowTitle?.lowercased(),
           title.contains("terminal") || title.contains("— zsh") || title.contains("— bash") {
            return true
        }
        return false
    }
}
