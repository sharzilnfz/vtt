import AppKit
import Carbon

public enum InsertionMethod: Sendable, Equatable {
    case directTyping
    case clipboardPaste
}

public protocol InsertionServiceProtocol: Sendable {
    @MainActor func insert(
        text: String,
        targetApp: TargetApplication?,
        forceClipboard: Bool
    ) -> Result<InsertionMethod, SessionFailureReason>
}

@MainActor
public final class InsertionService: InsertionServiceProtocol {
    private let targetValidator: TargetValidating
    private let pasteboardManager: PasteboardManager
    private let config: AppConfiguration

    public init(
        targetValidator: TargetValidating = TargetValidator(),
        pasteboardManager: PasteboardManager = PasteboardManager(),
        config: AppConfiguration = AppConfiguration()
    ) {
        self.targetValidator = targetValidator
        self.pasteboardManager = pasteboardManager
        self.config = config
    }

    public func insert(
        text: String,
        targetApp: TargetApplication?,
        forceClipboard: Bool = false
    ) -> Result<InsertionMethod, SessionFailureReason> {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, AXIsProcessTrusted() else {
            return .failure(.insertionFailed)
        }
        var text = text.trimmingCharacters(in: .newlines)
        if targetApp?.isTerminal == true {
            text = text.replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
        }
        if config.revalidateTargetApp {
            let validation = targetValidator.validate(against: targetApp)
            if case .appChanged = validation {
                return .failure(.targetAppChanged)
            }
        }

        let success = pasteboardManager.pasteWithRestore(text: text)
        return success ? .success(.clipboardPaste) : .failure(.insertionFailed)
    }
}
