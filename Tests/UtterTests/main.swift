import AppKit
import Foundation
import UtterCore

func runTest(_ name: String, block: () throws -> Void) {
    do {
        try block()
        print("✔ \(name)")
    } catch {
        print("✘ \(name): \(error)")
        exit(1)
    }
}

print("Running Utter Test Suite...")

runTest("SessionState transitions and re-entrancy protection") {
    let machine = SessionStateMachine()
    assert(machine.state == .idle)

    let target = TargetApplication(bundleIdentifier: "com.apple.TextEdit", processIdentifier: 1234, localizedName: "TextEdit")
    let startResult = machine.startRecording(mode: .direct, targetApp: target)
    guard case .success = startResult else { throw NSError(domain: "Test", code: 1) }

    // Re-entrancy protection
    let concurrent = machine.startRecording(mode: .direct, targetApp: target)
    guard case .failure(let err) = concurrent, err == .alreadyActive else {
        throw NSError(domain: "Test", code: 2)
    }

    let stopResult = machine.stopRecording()
    guard case .success = stopResult else { throw NSError(domain: "Test", code: 3) }

    let insertResult = machine.startInserting(text: "Hello world")
    guard case .success = insertResult else { throw NSError(domain: "Test", code: 4) }

    machine.complete()
    assert(machine.state == .idle)
}

runTest("SafetyBuffer rolling capacity and eviction") {
    let buffer = SafetyBuffer(capacity: 3)
    assert(buffer.lastTranscript == nil)

    for i in 1...5 {
        let item = Transcript(
            rawText: "Transcript \(i)",
            mode: .direct,
            durationSeconds: Double(i)
        )
        buffer.recordRaw(item)
    }

    let all = buffer.allItems
    assert(all.count == 3)
    assert(all[0].rawText == "Transcript 5")
    assert(all[1].rawText == "Transcript 4")
    assert(all[2].rawText == "Transcript 3")
}

runTest("SafetyBuffer refined text update") {
    let buffer = SafetyBuffer(capacity: 5)
    let item = Transcript(
        rawText: "raw words",
        mode: .refined,
        durationSeconds: 2.0
    )
    buffer.recordRaw(item)
    assert(buffer.lastTranscript?.rawText == "raw words")

    buffer.updateRefined(id: item.id, refinedText: "Refined words.")
    assert(buffer.lastTranscript?.refinedText == "Refined words.")
    assert(buffer.lastTranscript?.textToInsert == "Refined words.")
}

runTest("TargetApplication matching") {
    let app1 = TargetApplication(bundleIdentifier: "com.apple.dt.Xcode", processIdentifier: 100, localizedName: "Xcode", windowNumber: 7)
    let app2 = TargetApplication(bundleIdentifier: "com.apple.dt.Xcode", processIdentifier: 100, localizedName: "Xcode", windowNumber: 9)
    let app3 = TargetApplication(bundleIdentifier: "com.apple.dt.Xcode", processIdentifier: 200, localizedName: "Xcode", windowNumber: 7)
    let app4 = TargetApplication(bundleIdentifier: "com.apple.dt.Xcode", processIdentifier: 100, localizedName: "Xcode", windowNumber: 7)

    assert(app1.matches(other: app4))
    assert(!app1.matches(other: app2), "Window switch inside one process must invalidate the target")
    assert(!app1.matches(other: app3), "Different PID must invalidate the target")

    let terminalApp = TargetApplication(bundleIdentifier: "com.apple.Terminal", processIdentifier: 500, localizedName: "Terminal")
    assert(terminalApp.isTerminal, "Terminal bundle must be identified as terminal")
    let iTermApp = TargetApplication(bundleIdentifier: "com.googlecode.iterm2", processIdentifier: 501, localizedName: "iTerm2")
    assert(iTermApp.isTerminal, "iTerm2 must be identified as terminal")
    let ghosttyApp = TargetApplication(bundleIdentifier: "com.mitchellh.ghostty", processIdentifier: 502, localizedName: "Ghostty")
    assert(ghosttyApp.isTerminal, "Ghostty must be identified as terminal")
    assert(!app1.isTerminal, "Xcode standard window must not be identified as terminal")

    let vscodeEditor = TargetApplication(bundleIdentifier: "com.microsoft.VSCode", processIdentifier: 600, localizedName: "Code", windowTitle: "main.swift — utter")
    assert(!vscodeEditor.isTerminal, "VS Code editor window must not be identified as terminal")
    let vscodeTerminal = TargetApplication(bundleIdentifier: "com.microsoft.VSCode", processIdentifier: 600, localizedName: "Code", windowTitle: "Terminal 1 — zsh")
    assert(vscodeTerminal.isTerminal, "VS Code integrated terminal window must be identified as terminal")
    let cursorTerminal = TargetApplication(bundleIdentifier: "com.todesktop.230313mzl4w4u92", processIdentifier: 601, localizedName: "Cursor", windowTitle: "Terminal: bash")
    assert(cursorTerminal.isTerminal, "Cursor integrated terminal window must be identified as terminal")
    let explicitTerminal = TargetApplication(bundleIdentifier: "com.apple.dt.Xcode", processIdentifier: 100, localizedName: "Xcode", isTerminalExplicit: true)
    assert(explicitTerminal.isTerminal, "Explicit terminal flag must be honored")
}

runTest("Terminal newline protection during insertion") {
    let board = NSPasteboard(name: .init("Utter-tests-\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    let manager = PasteboardManager(pasteboard: board, postPaste: { true })
    let service = InsertionService(
        targetValidator: TargetValidator(),
        pasteboardManager: manager,
        config: AppConfiguration(revalidateTargetApp: false)
    )
    let terminalApp = TargetApplication(bundleIdentifier: "com.apple.Terminal", processIdentifier: 500, localizedName: "Terminal")
    let multilineCommand = "git status\nrm -rf /"
    _ = service.insert(text: multilineCommand, targetApp: terminalApp)
    let pasted = board.string(forType: .string) ?? ""
    assert(!pasted.contains("\n") && !pasted.contains("\r"), "Terminal target must never receive newlines")
    assert(pasted == "git status rm -rf /", "Terminal newlines must be sanitized to spaces")
}

runTest("Storage file persistence") {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("utter-test-storage-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let vocabURL = tempDir.appendingPathComponent("vocabulary.json")
    let vocab1 = VocabularyStore(fileURL: vocabURL)
    vocab1.setAlias(from: "test key", to: "Test Value")
    // Allow background write
    Thread.sleep(forTimeInterval: 0.1)
    let vocab2 = VocabularyStore(fileURL: vocabURL)
    assert(vocab2.applyAliases(to: "test key") == "Test Value")

    let bufferURL = tempDir.appendingPathComponent("safety_buffer.json")
    let buffer1 = SafetyBuffer(capacity: 5, fileURL: bufferURL)
    let item = Transcript(rawText: "persisted transcript", mode: .direct, durationSeconds: 1.5)
    buffer1.recordRaw(item)
    Thread.sleep(forTimeInterval: 0.1)
    let buffer2 = SafetyBuffer(capacity: 5, fileURL: bufferURL)
    assert(buffer2.lastTranscript?.rawText == "persisted transcript")

    let statsURL = tempDir.appendingPathComponent("stats.json")
    let stats1 = StatsStore(fileURL: statsURL)
    stats1.recordSession(mode: .refined, audioDuration: 3.5, wordCount: 15)
    Thread.sleep(forTimeInterval: 0.1)
    let stats2 = StatsStore(fileURL: statsURL)
    assert(stats2.currentStats.totalWordsDelivered == 15)
    assert(stats2.currentStats.totalRefinedRecordings == 1)

    let dbURL = tempDir.appendingPathComponent("history.db")
    let sharedDB1 = try HistoryDatabase(fileURL: dbURL)
    let bufferDB1 = SafetyBuffer(capacity: 5, database: sharedDB1)
    let statsDB1 = StatsStore(database: sharedDB1)
    let dbItem = Transcript(rawText: "sqlite transcript", mode: .refined, durationSeconds: 2.0)
    bufferDB1.recordRaw(dbItem)
    statsDB1.recordSession(mode: .refined, audioDuration: 2.0, wordCount: 12)
    sharedDB1.close()

    let sharedDB2 = try HistoryDatabase(fileURL: dbURL)
    let bufferDB2 = SafetyBuffer(capacity: 5, database: sharedDB2)
    let statsDB2 = StatsStore(database: sharedDB2)
    assert(bufferDB2.lastTranscript?.rawText == "sqlite transcript", "SafetyBuffer must reload from SQLite history.db")
    assert(statsDB2.currentStats.totalWordsDelivered == 12, "StatsStore must reload aggregates from SQLite history.db")
    assert(statsDB2.currentStats.totalRefinedRecordings == 1, "StatsStore must reload refined count from SQLite history.db")
}

runTest("VocabularyStore alias replacement") {
    let store = VocabularyStore()
    store.setAlias(from: "core ml", to: "CoreML")
    store.setAlias(from: "swift ui", to: "SwiftUI")

    let input = "I am testing core ml with swift ui today."
    let result = store.applyAliases(to: input)
    assert(result == "I am testing CoreML with SwiftUI today.")

    let literalStore = VocabularyStore(initialAliases: ["price": "$1\\n total"])
    assert(literalStore.applyAliases(to: "price") == "$1\\n total")
}

runTest("RefinementService system prompt rules") {
    let prompt = RefinementService.systemPrompt
    assert(prompt.contains("Remove filler words"))
    assert(prompt.contains("Never answer questions"))
}

runInsertionRegressionTests()
runTest("Shortcut mode latching", block: runShortcutRegressions)
runTest("Reinsert state transitions", block: runSessionStateRegressions)
runTest("STT model link parsing and persistence", block: runSTTModelRegressions)
runTest("STT banner replacement without leak", block: runSTTBannerRegressions)
do {
    try await runCoordinatorRegressions()
    print("✔ Coordinator lifecycle regressions")
} catch {
    print("✘ Coordinator lifecycle regressions: \(error)")
    exit(1)
}

do {
    try await runGatewayRegressionTests()
    print("Gateway regressions passed")
} catch {
    print("Gateway regressions failed: \(error)")
    exit(1)
}

runTest("Hardware modifier flag detection and chords", block: runHardwareEventFlagRegressions)
runTest("Popover Command comma shortcut matcher", block: runPopoverShortcutRegressions)

do {
    try await runHotkeyMonitorRegressions()
    print("✔ Hotkey monitor regressions")
} catch {
    print("SKIP Hotkey monitor regressions: \(error)")
}

runTest("History picker keeps sessions separate") {
    _ = NSApplication.shared
    let buffer = SafetyBuffer(capacity: 2)
    let first = Transcript(rawText: "First independent session", mode: .direct, durationSeconds: 1)
    let second = Transcript(rawText: "Second independent session", mode: .refined, durationSeconds: 2)
    buffer.recordRaw(first)
    buffer.recordRaw(second)
    let suite = "Utter.HistoryRegression.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let controller = SetupWindowController(safetyBuffer: buffer, settings: RefinementSettingsStore(defaults: defaults))
    defer { controller.close() }

    let state = controller.dashboardState
    state.refreshActivitiesFromTranscripts()
    assert(state.activities.count == 2)
    assert(state.activities[0].title.contains("Second independent session"))
    assert(state.activities[1].title.contains("First independent session"))

    buffer.updateRefined(id: second.id, refinedText: "Second refined session")
    state.refreshActivitiesFromTranscripts()
    assert(state.activities.count == 2)
    assert(state.activities[0].refinedText == "Second refined session")
    assert(state.activities[0].kind == .refinement)

    state.clearActivities()
    assert(state.activities.isEmpty)
    assert(buffer.count == 0)
}

runTest("App menu wires Cut, Copy, Paste, Select All") {
    _ = NSApplication.shared
    AppMenuBuilder.install()
    let editMenu = NSApp.mainMenu!.items.compactMap(\.submenu).first { $0.title == "Edit" }!
    let actions = Dictionary(uniqueKeysWithValues: editMenu.items.map { ($0.title, $0.action) })
    assert(actions["Cut"] == #selector(NSText.cut(_:)))
    assert(actions["Copy"] == #selector(NSText.copy(_:)))
    assert(actions["Paste"] == #selector(NSText.paste(_:)))
    assert(actions["Select All"] == #selector(NSText.selectAll(_:)))
}

runTest("Info.plist enables Dock icon (LSUIElement is false)") {
    let plistURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("scripts/Info.plist")
    guard let data = try? Data(contentsOf: plistURL),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load scripts/Info.plist"])
    }
    if let uiElement = plist["LSUIElement"] as? Bool, uiElement {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "LSUIElement is true; must be false or omitted so the app appears in the Dock"])
    }
}

runTest("HistoryDatabase schema, rolling eviction, and daily aggregates", block: runHistoryDatabaseRegressions)

do {
    try await runHistoryDatabaseConcurrencyRegressions()
    print("✔ HistoryDatabase concurrent read/write")
} catch {
    print("✘ HistoryDatabase concurrent read/write: \(error)")
    exit(1)
}

runTest("Speech model abbreviation deduplication") {
    _ = NSApplication.shared
    let buffer = SafetyBuffer()
    let settings = RefinementSettingsStore()
    let state = MainActor.assumeIsolated {
        DashboardState(safetyBuffer: buffer, settingsStore: settings)
    }
    MainActor.assumeIsolated {
        state.speechModelLabel = "Parakeet TDT 0.6B v2"
        assert(state.abbreviatedSpeechModelLabel == "Parakeet", "Parakeet models should abbreviate to 'Parakeet'")
        state.speechModelLabel = "VeryLongCustomModelName"
        assert(state.abbreviatedSpeechModelLabel == "VeryLongCu", "Long model names should truncate to 10 chars")
        state.speechModelLabel = "Whisper"
        assert(state.abbreviatedSpeechModelLabel == "Whisper", "Short model names should be unchanged")
    }
}

print("\nAll test suites passed successfully.")
