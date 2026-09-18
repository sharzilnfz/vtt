public enum ShortcutKeyAction: Sendable, Equatable {
    case start(DictationMode)
    case stop(DictationMode)
    case reinsert
}

public struct ShortcutKeyReducer: Sendable {
    private var leftControlDown = false
    private var leftOptionDown = false
    private var leftCommandDown = false
    private var activeMode: DictationMode?

    public init() {}

    public mutating func updateModifiers(
        leftControlDown: Bool,
        leftOptionDown: Bool,
        leftCommandDown: Bool
    ) -> [ShortcutKeyAction] {
        self.leftControlDown = leftControlDown
        self.leftOptionDown = leftOptionDown
        self.leftCommandDown = leftCommandDown

        var actions: [ShortcutKeyAction] = []
        if let mode = activeMode {
            let stillHeld = mode == .direct
                ? (leftControlDown && leftOptionDown)
                : (leftOptionDown && leftCommandDown)
            if !stillHeld {
                activeMode = nil
                actions.append(.stop(mode))
            }
        }
        // Exactly-two-modifier chords keep the modes unambiguous when all three are held.
        let chord: DictationMode? = (leftControlDown && leftOptionDown && !leftCommandDown)
            ? .direct
            : ((leftOptionDown && leftCommandDown && !leftControlDown) ? .refined : nil)
        if activeMode == nil, let chord {
            activeMode = chord
            actions.append(.start(chord))
        }
        return actions
    }

    public func pressV(isRepeat: Bool) -> ShortcutKeyAction? {
        guard leftControlDown, !leftOptionDown, !leftCommandDown, !isRepeat else { return nil }
        return .reinsert
    }
}
