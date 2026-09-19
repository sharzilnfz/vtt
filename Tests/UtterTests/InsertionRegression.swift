import AppKit
import UtterCore

@MainActor
func runInsertionRegressionTests() {
    runTest("Clipboard restores all item types without main-queue deadlock") {
        let board = NSPasteboard(name: .init("Utter-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let original = NSPasteboardItem()
        original.setString("original", forType: .string)
        let customType = NSPasteboard.PasteboardType("dev.utter.test-data")
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
        let board = NSPasteboard(name: .init("Utter-tests-\(UUID().uuidString)"))
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
        let board = NSPasteboard(name: .init("Utter-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        let manager = PasteboardManager(pasteboard: board, postPaste: { false })
        precondition(!manager.pasteWithRestore(text: "dictation"))
        precondition(board.string(forType: .string) == "original")
    }
    runTest("Consecutive pastes retain the original clipboard") {
        let board = NSPasteboard(name: .init("Utter-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        let manager = PasteboardManager(pasteboard: board, postPaste: { true })
        precondition(manager.pasteWithRestore(text: "one"))
        precondition(manager.pasteWithRestore(text: "two"))
        manager.restoreIfUnchanged()
        precondition(board.string(forType: .string) == "original")
    }
    runTest("Both single-line and multi-line text use universal clipboard paste per ADR 002") {
        let board = NSPasteboard(name: .init("Utter-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let manager = PasteboardManager(pasteboard: board, postPaste: { true })
        let service = InsertionService(
            targetValidator: TargetValidator(),
            pasteboardManager: manager,
            config: AppConfiguration(revalidateTargetApp: false)
        )
        let multiline = "Line 1\nLine 2\nLine 3"
        let multilineResult = service.insert(text: multiline, targetApp: nil)
        precondition(multilineResult == .success(.clipboardPaste), "Multiline formatted text must use clipboard paste")

        let singleline = "Hello world"
        let singlelineResult = service.insert(text: singleline, targetApp: nil)
        precondition(singlelineResult == .success(.clipboardPaste), "Single line text must also use universal clipboard paste per ADR 002")
    }
}
