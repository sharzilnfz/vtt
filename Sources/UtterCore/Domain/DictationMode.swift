import Foundation

public enum DictationMode: String, Codable, Sendable, CaseIterable {
    case direct
    case refined

    public var displayName: String {
        switch self {
        case .direct:
            return "Write"
        case .refined:
            return "Clean"
        }
    }
}
