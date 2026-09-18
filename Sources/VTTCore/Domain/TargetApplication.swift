import Foundation

public struct TargetApplication: Codable, Sendable, Equatable {
    public let bundleIdentifier: String?
    public let processIdentifier: Int32
    public let localizedName: String?
    public let windowNumber: Int?

    public init(
        bundleIdentifier: String?,
        processIdentifier: Int32,
        localizedName: String?,
        windowNumber: Int? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.localizedName = localizedName
        self.windowNumber = windowNumber
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
}
