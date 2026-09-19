import AppKit
import Foundation
import SwiftUI
import UtterCore

@MainActor
func renderToPNG<V: View>(view: V, size: CGSize, path: String) {
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(size)
    renderer.scale = 2.0 // Retina 2x

    guard let cgImage = renderer.cgImage else {
        print("Failed to render cgImage for \(path)")
        return
    }

    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("Failed to convert to PNG data for \(path)")
        return
    }

    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("Saved: \(path)")
    } catch {
        print("Failed to write \(path): \(error)")
    }
}

@main
struct RenderPreview {
    @MainActor
    static func main() {
        let buffer = SafetyBuffer(capacity: 10)
        let t1 = Transcript(
            rawText: "Good morning team, let's sync on the CoreML pipeline at 10 AM.",
            mode: .direct,
            durationSeconds: 3.2,
            targetApplication: TargetApplication(bundleIdentifier: "com.apple.dt.Xcode", processIdentifier: 1234, localizedName: "Xcode")
        )
        var t2 = Transcript(
            rawText: "I want to refactor the session state machine to isolate speech samples.",
            mode: .refined,
            durationSeconds: 4.5,
            targetApplication: TargetApplication(bundleIdentifier: "com.apple.Terminal", processIdentifier: 5678, localizedName: "Terminal")
        )
        t2.refinedText = "Refactor the session state machine to isolate speech samples."
        buffer.recordRaw(t1)
        buffer.recordRaw(t2)

        let settings = RefinementSettingsStore()
        let stats = StatsStore(initialStats: DictationStats(
            totalRecordings: 14,
            totalDirectRecordings: 9,
            totalRefinedRecordings: 5,
            totalAudioSeconds: 42.8,
            totalWordsDelivered: 142
        ))
        let vocab = VocabularyStore(initialAliases: [
            "pr": "pull request",
            "utter": "Voice-to-Text",
            "core ml": "CoreML"
        ])

        let stateDark = DashboardState(
            safetyBuffer: buffer,
            settingsStore: settings,
            statsStore: stats,
            vocabularyStore: vocab
        )
        stateDark.modelState = .ready
        stateDark.micAuthorized = true
        stateDark.accessTrusted = true
        stateDark.activeTheme = .dark
        stateDark.refreshActivitiesFromTranscripts()

        let previewSize = CGSize(width: 660, height: 550)

        // 1. Dark Mode Dashboard
        renderToPNG(
            view: DashboardView(state: stateDark).frame(width: previewSize.width, height: previewSize.height, alignment: .top),
            size: previewSize,
            path: "/tmp/utter-dashboard-dark.png"
        )

        // 2. Light Mode Dashboard
        let stateLight = DashboardState(
            safetyBuffer: buffer,
            settingsStore: settings,
            statsStore: stats,
            vocabularyStore: vocab
        )
        stateLight.modelState = .ready
        stateLight.micAuthorized = true
        stateLight.accessTrusted = true
        stateLight.activeTheme = .light
        stateLight.refreshActivitiesFromTranscripts()

        renderToPNG(
            view: DashboardView(state: stateLight).frame(width: previewSize.width, height: previewSize.height, alignment: .top),
            size: previewSize,
            path: "/tmp/utter-dashboard-light.png"
        )

        // 3. Indicator Pill (Strictly Black and White, No Text)
        let pillVM = PillViewModel()
        pillVM.update(status: .recording(level: 0.65))
        renderToPNG(
            view: IndicatorPillView(viewModel: pillVM),
            size: CGSize(width: 90, height: 38),
            path: "/tmp/utter-indicator-pill.png"
        )

        // 4. Menu Bar Popover / Hover Window (Dark)
        let popoverDark = MenuBarPopoverView(
            modelState: .ready,
            permissionsReady: true,
            lastTranscript: t2,
            stats: stats.currentStats,
            isDark: true,
            onOpenDashboard: {},
            onCopyLast: {},
            onRetryModel: {},
            onQuit: {},
            onToggleTheme: {}
        )
        renderToPNG(
            view: popoverDark,
            size: CGSize(width: 320, height: 320),
            path: "/tmp/utter-menubar-popover-dark.png"
        )

        // 5. Menu Bar Popover / Hover Window (Light)
        let popoverLight = MenuBarPopoverView(
            modelState: .ready,
            permissionsReady: true,
            lastTranscript: t2,
            stats: stats.currentStats,
            isDark: false,
            onOpenDashboard: {},
            onCopyLast: {},
            onRetryModel: {},
            onQuit: {},
            onToggleTheme: {}
        )
        renderToPNG(
            view: popoverLight,
            size: CGSize(width: 320, height: 320),
            path: "/tmp/utter-menubar-popover-light.png"
        )

        print("Finished generating previews.")
        exit(0)
    }
}
