import AppKit
import VTTCore

@MainActor
func runInsertionRegressionTests() {
    runTest("Clipboard restores all item types without main-queue deadlock") {
        let board = NSPasteboard(name: .init("VTT-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let original = NSPasteboardItem()
        original.setString("original", forType: .string)
        let customType = NSPasteboard.PasteboardType("dev.vtt.test-data")
        original.setData(Data([1, 2, 3]), forType: customType)
        board.writeObjects([original])
        let manager = PasteboardManager(pasteboard: board, postPaste: { true })
        precondition(manager.pasteWithRestore(text: "dictation"))
        precondition(board.string(forType: .string) == "dictation")
        manager.restoreIfUnchanged()
        precondition(board.string(forType: .string) == "original")
        precondition(board.data(forType: customType) == Data([1, 2, 3]))
    }
    runTest("Clipboard restoration preserves newer user content") {
        let board = NSPasteboard(name: .init("VTT-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        let manager = PasteboardManager(pasteboard: board, postPaste: { true })
        precondition(manager.pasteWithRestore(text: "dictation"))
        board.clearContents()
        board.setString("new copy", forType: .string)
        manager.restoreIfUnchanged()
        precondition(board.string(forType: .string) == "new copy")
    }
    runTest("Failed paste restores clipboard immediately") {
        let board = NSPasteboard(name: .init("VTT-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        let manager = PasteboardManager(pasteboard: board, postPaste: { false })
        precondition(!manager.pasteWithRestore(text: "dictation"))
        precondition(board.string(forType: .string) == "original")
    }
    runTest("Consecutive pastes retain the original clipboard") {
        let board = NSPasteboard(name: .init("VTT-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        let manager = PasteboardManager(pasteboard: board, postPaste: { true })
        precondition(manager.pasteWithRestore(text: "one"))
        precondition(manager.pasteWithRestore(text: "two"))
        manager.restoreIfUnchanged()
        precondition(board.string(forType: .string) == "original")
    }
    runTest("Multi-line text uses clipboard paste while single-line uses direct typing") {
        let board = NSPasteboard(name: .init("VTT-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let manager = PasteboardManager(pasteboard: board, postPaste: { true })
        let service = InsertionService(
            targetValidator: TargetValidator(),
            keySynthesizer: KeySynthesizer(),
            pasteboardManager: manager,
            config: AppConfiguration(revalidateTargetApp: false)
        )
        let multiline = "Line 1\nLine 2\nLine 3"
        let multilineResult = service.insert(text: multiline, targetApp: nil)
        precondition(multilineResult == .success(.clipboardPaste), "Multiline formatted text must use clipboard paste to preserve newlines")

        let singleline = "Hello world"
        let singlelineResult = service.insert(text: singleline, targetApp: nil)
        precondition(singlelineResult == .success(.directTyping), "Single line text must use direct typing")
    }
}
