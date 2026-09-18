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
    private let keySynthesizer: KeySynthesizing
    private let pasteboardManager: PasteboardManaging
    private let config: AppConfiguration

    public init(
        targetValidator: TargetValidating = TargetValidator(),
        keySynthesizer: KeySynthesizing = KeySynthesizer(),
        pasteboardManager: PasteboardManaging = PasteboardManager(),
        config: AppConfiguration = AppConfiguration()
    ) {
        self.targetValidator = targetValidator
        self.keySynthesizer = keySynthesizer
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
        let text = text.trimmingCharacters(in: .newlines)
        if config.revalidateTargetApp {
            let validation = targetValidator.validate(against: targetApp)
            if case .appChanged = validation {
                return .failure(.targetAppChanged)
            }
        }

        let secureInput = IsSecureEventInputEnabled()
        let hasNewlines = text.contains("\n") || text.contains("\r")
        let shouldUseClipboard = forceClipboard || secureInput || hasNewlines || text.count > config.maxTypingLengthForDirectKeyEvents
        if shouldUseClipboard {
            let success = pasteboardManager.pasteWithRestore(text: text)
            return success ? .success(.clipboardPaste) : .failure(.insertionFailed)
        } else {
            let success = keySynthesizer.type(text: text, characterDelayMicroseconds: config.characterTypingDelayMicroseconds)
            if success {
                return .success(.directTyping)
            }
            let fallbackSuccess = pasteboardManager.pasteWithRestore(text: text)
            return fallbackSuccess ? .success(.clipboardPaste) : .failure(.insertionFailed)
        }
    }
}
