import Foundation
import Combine

public enum PillStatus: Sendable, Equatable {
    case idle
    case recording(level: Float)
    case transcribing
    case refining
    case inserting
    case failed(reason: SessionFailureReason)

    public var isVisible: Bool {
        if case .idle = self { return false }
        return true
    }
}

@MainActor
public final class PillViewModel: ObservableObject {
    @Published public private(set) var status: PillStatus = .idle

    public init() {}

    public func update(status: PillStatus) {
        self.status = status
    }
}
