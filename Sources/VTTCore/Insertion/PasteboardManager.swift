import AppKit
import ApplicationServices

public typealias PasteboardManaging = PasteboardManager

@MainActor
public final class PasteboardManager: Sendable {
    private let pasteboard: NSPasteboard
    private let postPaste: @MainActor () -> Bool
    private var pendingRestore: (items: [NSPasteboardItem], changeCount: Int)?

    public init(pasteboard: NSPasteboard = .general, postPaste: (@MainActor () -> Bool)? = nil) {
        self.pasteboard = pasteboard
        self.postPaste = postPaste ?? Self.synthesizeCmdV
    }

    public func pasteWithRestore(text: String) -> Bool {
        guard !text.isEmpty else { return false }
        restoreIfUnchanged()
        var snapshot: [NSPasteboardItem] = []
        for original in pasteboard.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in original.types {
                // Do not replace a clipboard whose promised data cannot be saved.
                guard let data = original.data(forType: type), copy.setData(data, forType: type) else {
                    return false
                }
            }
            snapshot.append(copy)
        }
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            pasteboard.clearContents()
            if !snapshot.isEmpty { pasteboard.writeObjects(snapshot) }
            return false
        }
        let ownedChangeCount = pasteboard.changeCount
        pendingRestore = (snapshot, ownedChangeCount)
        guard postPaste() else {
            restoreIfUnchanged()
            return false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            guard pendingRestore?.changeCount == ownedChangeCount else { return }
            restoreIfUnchanged()
        }
        return true
    }

    public func restoreIfUnchanged() {
        guard let pending = pendingRestore else { return }
        pendingRestore = nil
        guard pasteboard.changeCount == pending.changeCount else { return }
        pasteboard.clearContents()
        if !pending.items.isEmpty { pasteboard.writeObjects(pending.items) }
    }

    private static func synthesizeCmdV() -> Bool {
        guard (CGPreflightPostEventAccess() || AXIsProcessTrusted()),
              let source = CGEventSource(stateID: .combinedSessionState) ?? CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
