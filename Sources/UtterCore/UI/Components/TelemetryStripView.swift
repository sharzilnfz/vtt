import SwiftUI

public struct TelemetryStripView: View {
    @ObservedObject var state: DashboardState
    let isDark: Bool

    public init(state: DashboardState, isDark: Bool) {
        self.state = state
        self.isDark = isDark
    }

    private var modelText: String {
        switch state.modelState {
        case .ready: return state.abbreviatedSpeechModelLabel
        case .loading: return "Loading"
        case .failed: return "Offline"
        }
    }

    private var bufferText: String {
        "\(state.safetyBuffer.count)"
    }

    private var wordsText: String {
        if let stats = state.statsStore?.currentStats {
            return "\(stats.totalWordsDelivered)"
        }
        return "0"
    }

    private var cleanupText: String {
        if let config = state.settingsStore.config {
            let model = config.model
            if model.isEmpty { return "Active" }
            if model.count > 10 {
                return String(model.prefix(10))
            }
            return model
        }
        return "Local"
    }

    public var body: some View {
        HStack(spacing: 0) {
            telemetryItem(label: "Engine", value: modelText, isMono: false, helpText: "CoreML Speech Engine: \(state.speechModelLabel)")

            telemetryDivider

            telemetryItem(label: "Buffer", value: bufferText, isMono: true, helpText: "Safety Buffer: \(state.safetyBuffer.count) recent transcripts stored")

            telemetryDivider

            telemetryItem(label: "Words", value: wordsText, isMono: true, helpText: "Total words delivered to applications")

            telemetryDivider

            telemetryItem(label: "Cleanup", value: cleanupText, isMono: false, helpText: "AI Refinement: \(state.settingsStore.config?.model ?? "Local")")

            telemetryDivider

            telemetryItem(label: "Hotkeys", value: "⌃⌥ / ⌥⌘ / ⌃V", isMono: true, helpText: "Direct: Left Control+Option · Clean: Left Option+Command · Paste: Left Control+V")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(UtterTheme.telemetryBg(isDark: isDark))
        .overlay(
            VStack {
                Rectangle()
                    .fill(UtterTheme.borderSubtle(isDark: isDark))
                    .frame(height: 1)
                Spacer()
                Rectangle()
                    .fill(UtterTheme.borderSubtle(isDark: isDark))
                    .frame(height: 1)
            }
        )
    }

    private func telemetryItem(label: String, value: String, isMono: Bool, helpText: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.5)
                .foregroundColor(UtterTheme.text3(isDark: isDark))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)

            Text(value)
                .font(isMono ? .system(size: 11.5, weight: .bold, design: .monospaced) : .system(size: 11.5, weight: .bold))
                .foregroundColor(UtterTheme.text1(isDark: isDark))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .help(helpText ?? "\(label): \(value)")
    }

    private var telemetryDivider: some View {
        Rectangle()
            .fill(UtterTheme.borderSubtle(isDark: isDark))
            .frame(width: 1, height: 14)
    }
}
