import SwiftUI

public struct FlowColumnsView: View {
    @ObservedObject var state: DashboardState
    let isDark: Bool

    public init(state: DashboardState, isDark: Bool) {
        self.state = state
        self.isDark = isDark
    }

    private var historyItems: [ActivityItem] {
        state.activities.filter { $0.kind == .transcript || $0.kind == .refinement }
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 24) {
            // Left Column: System & Shortcuts
            VStack(alignment: .leading, spacing: 10) {
                // Section 1: System & Permissions
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("SYSTEM & PERMISSIONS")
                            .font(.system(size: 10.5, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(VTTTheme.text2(isDark: isDark))
                        Spacer()
                    }
                    .padding(.bottom, 1)

                    // Microphone Row
                    systemRow(
                        beaconState: state.micAuthorized ? .synced : .holding,
                        title: "Microphone",
                        subtitle: state.micAuthorized ? "16 kHz Mono Active" : "Authorization needed",
                        trailingView: AnyView(
                            Group {
                                if !state.micAuthorized {
                                    Button("Grant") { state.requestMicrophone() }
                                        .buttonStyle(VTTGhostSmallButtonStyle(isDark: isDark))
                                        .focusEffectDisabled()
                                } else {
                                    Text("Active")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(VTTTheme.stateSynced(isDark: isDark))
                                }
                            }
                        )
                    )

                    // Accessibility Row
                    systemRow(
                        beaconState: state.accessTrusted ? .synced : .holding,
                        title: "Accessibility",
                        subtitle: state.accessTrusted ? "Direct text insertion (CGEvent)" : "Accessibility needed",
                        trailingView: AnyView(
                            Group {
                                if !state.accessTrusted {
                                    Button("Grant") { state.requestAccessibility() }
                                        .buttonStyle(VTTGhostSmallButtonStyle(isDark: isDark))
                                        .focusEffectDisabled()
                                } else {
                                    Text("Active")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(VTTTheme.stateSynced(isDark: isDark))
                                }
                            }
                        )
                    )

                    // Speech Engine Row
                    systemRow(
                        beaconState: modelBeaconState,
                        title: "Speech Engine",
                        subtitle: modelSubtitle,
                        trailingView: AnyView(
                            HStack(spacing: 6) {
                                Button("Change") { state.showSpeechSheet = true }
                                    .buttonStyle(VTTGhostSmallButtonStyle(isDark: isDark))
                                    .focusEffectDisabled()
                                if case .failed = state.modelState {
                                    Button("Retry") { state.onRetryModel?() }
                                        .buttonStyle(VTTGhostSmallButtonStyle(isDark: isDark))
                                        .focusEffectDisabled()
                                } else {
                                    Text(modelStatusText)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(modelBeaconState.color(isDark: isDark))
                                }
                            }
                        )
                    )
                }

                // Section 2: Shortcuts & Modes
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("SHORTCUTS & MODES")
                            .font(.system(size: 10.5, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(VTTTheme.text2(isDark: isDark))
                        Spacer()
                    }
                    .padding(.bottom, 1)

                    shortcutRow(
                        title: "Direct Dictation",
                        subtitle: "Type spoken text directly",
                        keys: "⌃⌥"
                    )

                    shortcutRow(
                        title: "AI Cleaned Dictation",
                        subtitle: "Transcribe and format via LLM",
                        keys: "⌥⌘"
                    )

                    shortcutRow(
                        title: "Re-insert Last",
                        subtitle: "Replay last transcript",
                        keys: "⌃V"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // Right Column: History
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("HISTORY")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(VTTTheme.text2(isDark: isDark))

                    Spacer()

                    Button("Clear") {
                        state.clearActivities()
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(VTTTheme.text2(isDark: isDark))
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(VTTTheme.surfaceHover(isDark: isDark))
                    )
                }
                .padding(.bottom, 1)

                // History Feed List
                VStack(spacing: 3) {
                    if historyItems.isEmpty {
                        Text("No dictation history")
                            .font(.system(size: 11.5))
                            .foregroundColor(VTTTheme.text3(isDark: isDark))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(historyItems.prefix(5)) { activity in
                            activityRow(activity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var modelBeaconState: BeaconState {
        switch state.modelState {
        case .ready: return .synced
        case .loading: return .syncing
        case .failed: return .conflict
        }
    }

    private var modelSubtitle: String {
        let base = state.speechModelLabel.isEmpty ? "Parakeet" : state.speechModelLabel
        switch state.modelState {
        case .ready: return base
        case .loading: return "Loading \(base)…"
        case .failed(let err): return "\(base): \(err)"
        }
    }

    private var modelStatusText: String {
        switch state.modelState {
        case .ready: return "Ready"
        case .loading: return "Loading"
        case .failed: return "Failed"
        }
    }

    private func systemRow(
        beaconState: BeaconState,
        title: String,
        subtitle: String,
        trailingView: AnyView
    ) -> some View {
        HStack(spacing: 8) {
            MiniBeaconView(state: beaconState, isDark: isDark, size: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(VTTTheme.text1(isDark: isDark))

                Text(subtitle)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundColor(VTTTheme.text3(isDark: isDark))
                    .lineLimit(1)
            }

            Spacer()

            trailingView
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(VTTTheme.surfaceHover(isDark: isDark).opacity(0.5))
        )
    }

    private func shortcutRow(
        title: String,
        subtitle: String,
        keys: String
    ) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(VTTTheme.text3(isDark: isDark))
                .frame(width: 4, height: 4)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(VTTTheme.text1(isDark: isDark))

                Text(subtitle)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(VTTTheme.text3(isDark: isDark))
            }

            Spacer()

            Text(keys)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundColor(VTTTheme.text2(isDark: isDark))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(VTTTheme.surfaceHover(isDark: isDark))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(VTTTheme.borderSubtle(isDark: isDark), lineWidth: 1)
                        )
                )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(VTTTheme.surfaceHover(isDark: isDark).opacity(0.3))
        )
    }

    private func activityRow(_ item: ActivityItem) -> some View {
        Button(action: {
            if let refined = item.refinedText {
                state.copyText(refined)
            } else if let raw = item.rawText {
                state.copyText(raw)
            }
        }) {
            HStack(spacing: 8) {
                MiniBeaconView(state: activityBeaconState(item.kind), isDark: isDark, size: 5)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(VTTTheme.text1(isDark: isDark))
                        .lineLimit(1)

                    if let sub = item.subtitle {
                        Text(sub)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(VTTTheme.text3(isDark: isDark))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(timeString(from: item.timestamp))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(VTTTheme.text3(isDark: isDark))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(VTTTheme.surfaceHover(isDark: isDark).opacity(0.4))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func activityBeaconState(_ kind: ActivityItem.ActivityKind) -> BeaconState {
        switch kind {
        case .transcript: return .synced
        case .refinement: return .syncing
        case .warning: return .holding
        case .error: return .conflict
        case .system: return .offline
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private func timeString(from date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
}
