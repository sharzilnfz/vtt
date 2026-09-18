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
        case .ready:
            let label = state.speechModelLabel
            return label.isEmpty ? "Parakeet" : (label.count > 14 ? String(label.prefix(14)) : label)
        case .loading: return "Loading"
        case .failed: return "Offline"
        }
    }

    private var bufferText: String {
        "\(state.safetyBuffer.count)/10"
    }

    private var wordsText: String {
        if let stats = state.statsStore?.currentStats {
            return "\(stats.totalWordsDelivered)"
        }
        return "0"
    }

    private var cleanupText: String {
        if let config = state.settingsStore.config {
            return config.model.isEmpty ? "Active" : config.model
        }
        return "Local"
    }

    public var body: some View {
        HStack(spacing: 0) {
            telemetryItem(label: "Engine", value: modelText, isMono: false)

            telemetryDivider

            telemetryItem(label: "Buffer", value: bufferText, isMono: true)

            telemetryDivider

            telemetryItem(label: "Words", value: wordsText, isMono: true)

            telemetryDivider

            telemetryItem(label: "Cleanup", value: cleanupText, isMono: false)

            telemetryDivider

            telemetryItem(label: "Hotkeys", value: "⌃⌥ / ⌥⌘", isMono: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(VTTTheme.telemetryBg(isDark: isDark))
        .overlay(
            VStack {
                Rectangle()
                    .fill(VTTTheme.borderSubtle(isDark: isDark))
                    .frame(height: 1)
                Spacer()
                Rectangle()
                    .fill(VTTTheme.borderSubtle(isDark: isDark))
                    .frame(height: 1)
            }
        )
    }

    private func telemetryItem(label: String, value: String, isMono: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(VTTTheme.text3(isDark: isDark))

            Text(value)
                .font(isMono ? .system(size: 12, weight: .bold, design: .monospaced) : .system(size: 12, weight: .bold))
                .foregroundColor(VTTTheme.text1(isDark: isDark))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var telemetryDivider: some View {
        Rectangle()
            .fill(VTTTheme.borderSubtle(isDark: isDark))
            .frame(width: 1, height: 14)
    }
}
