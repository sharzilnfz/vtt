public enum ShortcutKeyAction: Sendable, Equatable {
    case start(DictationMode)
    case stop(DictationMode)
    case reinsert
}

public struct ShortcutKeyReducer: Sendable {
    private var leftControlDown = false
    private var leftOptionDown = false
    private var rightOptionDown = false
    private var leftCommandDown = false
    private var activeMode: DictationMode?

    public init() {}

    public mutating func updateModifiers(
        leftControlDown: Bool,
        leftOptionDown: Bool,
        leftCommandDown: Bool,
        rightOptionDown: Bool = false
    ) -> [ShortcutKeyAction] {
        self.leftControlDown = leftControlDown
        self.leftOptionDown = leftOptionDown
        self.rightOptionDown = rightOptionDown
        self.leftCommandDown = leftCommandDown

        var actions: [ShortcutKeyAction] = []
        if let mode = activeMode {
            let stillHeld = mode == .direct
                ? (rightOptionDown || (leftControlDown && leftOptionDown))
                : (leftOptionDown && leftCommandDown)
            if !stillHeld {
                activeMode = nil
                actions.append(.stop(mode))
            }
        }
        let directActive = (rightOptionDown && !leftCommandDown && !leftControlDown) ||
            (leftControlDown && leftOptionDown && !leftCommandDown)
        let refinedActive = (leftOptionDown && leftCommandDown && !leftControlDown && !rightOptionDown)
        let chord: DictationMode? = directActive ? .direct : (refinedActive ? .refined : nil)
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
