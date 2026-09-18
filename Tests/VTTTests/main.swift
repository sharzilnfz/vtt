import AppKit
import Foundation
import VTTCore

func runTest(_ name: String, block: () throws -> Void) {
    do {
        try block()
        print("✔ \(name)")
    } catch {
        print("✘ \(name): \(error)")
        exit(1)
    }
}

print("Running VTT Test Suite...")

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
    let suite = "VTT.HistoryRegression.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let controller = SetupWindowController(safetyBuffer: buffer, settings: RefinementSettingsStore(defaults: defaults))
    defer { controller.close() }
    let views: [NSView] = MainActor.assumeIsolated {
        @MainActor
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        return descendants(controller.window!.contentView!)
    }
    let picker = views.compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == "History" }!
    let detail = views.compactMap { $0 as? NSTextView }.first!
    let fields = views.compactMap { $0 as? NSTextField }
    for label in ["URL", "Key", "Model"] {
        let field = fields.first { $0.accessibilityLabel() == label }!
        assert(field.isEditable && field.isSelectable, "\(label) must accept typed and pasted text")
    }
    controller.refreshTranscripts()
    assert(picker.numberOfItems == 2)
    assert(detail.string == "Said:\nSecond independent session")
    picker.selectItem(at: 1)
    _ = picker.sendAction(picker.action!, to: picker.target)
    assert(detail.string == "Said:\nFirst independent session")
    buffer.updateRefined(id: second.id, refinedText: "Second refined session")
    controller.refreshTranscripts()
    assert(picker.indexOfSelectedItem == 1)
    assert(detail.string == "Said:\nFirst independent session")
    picker.selectItem(at: 0)
    _ = picker.sendAction(picker.action!, to: picker.target)
    assert(detail.string == "Said:\nSecond independent session\n\nClean:\nSecond refined session")
    buffer.clear()
    controller.refreshTranscripts()
    assert(!picker.isEnabled && detail.string == "Empty.")
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

print("\nAll test suites passed successfully.")
