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
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.6)
                            .foregroundColor(UtterTheme.text2(isDark: isDark))
                        Spacer()
                    }
                    .padding(.bottom, 2)

                    // Microphone Row
                    SystemRowView(
                        beaconState: state.micAuthorized ? .synced : .holding,
                        title: "Microphone",
                        subtitle: state.micAuthorized ? "16 kHz Mono Active" : "Authorization needed",
                        isDark: isDark,
                        trailing: AnyView(
                            Group {
                                if !state.micAuthorized {
                                    Button("Grant") { state.requestMicrophone() }
                                        .buttonStyle(UtterGhostSmallButtonStyle(isDark: isDark))
                                        .focusEffectDisabled()
                                } else {
                                    Text("Active")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(UtterTheme.stateSynced(isDark: isDark))
                                }
                            }
                        )
                    )

                    // Accessibility Row
                    SystemRowView(
                        beaconState: state.accessTrusted ? .synced : .holding,
                        title: "Accessibility",
                        subtitle: state.accessTrusted ? "Direct text insertion (CGEvent)" : "Accessibility needed",
                        isDark: isDark,
                        trailing: AnyView(
                            Group {
                                if !state.accessTrusted {
                                    Button("Grant") { state.requestAccessibility() }
                                        .buttonStyle(UtterGhostSmallButtonStyle(isDark: isDark))
                                        .focusEffectDisabled()
                                } else {
                                    Text("Active")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(UtterTheme.stateSynced(isDark: isDark))
                                }
                            }
                        )
                    )

                    // Speech Engine Row
                    SystemRowView(
                        beaconState: modelBeaconState,
                        title: "Speech Engine",
                        subtitle: modelSubtitle,
                        isDark: isDark,
                        trailing: AnyView(
                            HStack(spacing: 6) {
                                Button("Change") { state.showSpeechSheet = true }
                                    .buttonStyle(UtterGhostSmallButtonStyle(isDark: isDark))
                                    .focusEffectDisabled()
                                if case .failed = state.modelState {
                                    Button("Retry") { state.onRetryModel?() }
                                        .buttonStyle(UtterGhostSmallButtonStyle(isDark: isDark))
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
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.6)
                            .foregroundColor(UtterTheme.text2(isDark: isDark))
                        Spacer()
                    }
                    .padding(.bottom, 2)

                    ShortcutRowView(
                        title: "Direct Dictation",
                        subtitle: "Hold to write spoken text directly",
                        keys: "Left ⌃⌥",
                        isDark: isDark
                    )

                    ShortcutRowView(
                        title: "AI Cleaned Dictation",
                        subtitle: "Hold to transcribe and polish via LLM",
                        keys: "Left ⌥⌘",
                        isDark: isDark
                    )

                    ShortcutRowView(
                        title: "Paste Last Dictation",
                        subtitle: "Paste previous transcript into active app",
                        keys: "Left ⌃V",
                        isDark: isDark
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // Right Column: History
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("HISTORY")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(UtterTheme.text2(isDark: isDark))

                    Spacer()

                    Button(action: {
                        withAnimation(UtterTheme.springSmooth) {
                            state.clearActivities()
                        }
                    }) {
                        Text("Clear")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(historyItems.isEmpty ? UtterTheme.text3(isDark: isDark) : UtterTheme.text2(isDark: isDark))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(UtterTheme.surfaceHover(isDark: isDark))
                            )
                    }
                    .buttonStyle(UtterScaledButtonStyle())
                    .focusEffectDisabled()
                    .disabled(historyItems.isEmpty)
                }
                .padding(.bottom, 2)

                // History Feed List
                VStack(spacing: 3) {
                    if historyItems.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "waveform")
                                .font(.system(size: 20))
                                .foregroundColor(UtterTheme.text3(isDark: isDark).opacity(0.8))
                            Text("No dictation history yet")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(UtterTheme.text3(isDark: isDark))
                            Text("Hold Left ⌃⌥ to speak")
                                .font(.system(size: 10))
                                .foregroundColor(UtterTheme.text3(isDark: isDark).opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 28)
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 3) {
                                ForEach(historyItems) { activity in
                                    ActivityRowView(
                                        item: activity,
                                        isDark: isDark,
                                        onCopy: { text in state.copyText(text) }
                                    )
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .top)),
                                        removal: .opacity
                                    ))
                                }
                            }
                            .animation(UtterTheme.springSmooth, value: historyItems)
                        }
                        .frame(maxHeight: 180)
                    }
                }
                .animation(UtterTheme.springSmooth, value: historyItems.isEmpty)
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
}

// MARK: - Subcomponents with Emil Kowalski & Apple Design Hover / Interaction Polish

struct SystemRowView: View {
    let beaconState: BeaconState
    let title: String
    let subtitle: String
    let isDark: Bool
    let trailing: AnyView
    @LocalState private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            MiniBeaconView(state: beaconState, isDark: isDark, size: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(UtterTheme.text1(isDark: isDark))

                Text(subtitle)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(UtterTheme.text3(isDark: isDark))
                    .lineLimit(1)
            }

            Spacer()

            trailing
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4.5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(UtterTheme.surfaceHover(isDark: isDark).opacity(isHovered ? 0.75 : 0.40))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isHovered ? UtterTheme.borderHover(isDark: isDark) : Color.clear, lineWidth: 1)
        )
        .animation(UtterTheme.hoverTransition, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

struct ShortcutRowView: View {
    let title: String
    let subtitle: String
    let keys: String
    let isDark: Bool
    @LocalState private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isHovered ? UtterTheme.text2(isDark: isDark) : UtterTheme.text3(isDark: isDark))
                .frame(width: 4, height: 4)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(UtterTheme.text1(isDark: isDark))

                Text(subtitle)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundColor(UtterTheme.text3(isDark: isDark))
            }

            Spacer()

            Text(keys)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundColor(isHovered ? UtterTheme.text1(isDark: isDark) : UtterTheme.text2(isDark: isDark))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(UtterTheme.surfaceHover(isDark: isDark))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(UtterTheme.borderSubtle(isDark: isDark), lineWidth: 1)
                        )
                )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(UtterTheme.surfaceHover(isDark: isDark).opacity(isHovered ? 0.60 : 0.25))
        )
        .animation(UtterTheme.hoverTransition, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

struct UtterScaledButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(UtterTheme.pressFeedback, value: configuration.isPressed)
    }
}

struct ActivityRowView: View {
    let item: ActivityItem
    let isDark: Bool
    let onCopy: (String) -> Void
    @LocalState private var isHovered = false

    private var cleanSubtitle: String {
        guard let sub = item.subtitle else { return "" }
        if sub.contains(".") {
            return sub.components(separatedBy: ".").last ?? sub
        }
        return sub
    }

    private var beaconState: BeaconState {
        switch item.kind {
        case .transcript: return .synced
        case .refinement: return .syncing
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        Button(action: {
            if let refined = item.refinedText {
                onCopy(refined)
            } else if let raw = item.rawText {
                onCopy(raw)
            }
        }) {
            HStack(spacing: 8) {
                MiniBeaconView(state: beaconState, isDark: isDark, size: 5)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(UtterTheme.text1(isDark: isDark))
                        .lineLimit(1)

                    if !cleanSubtitle.isEmpty {
                        Text(cleanSubtitle)
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundColor(UtterTheme.text3(isDark: isDark))
                            .lineLimit(1)
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    if isHovered {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(UtterTheme.text2(isDark: isDark))
                            .transition(.opacity)
                    }

                    Text(Self.timeFormatter.string(from: item.timestamp))
                        .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                        .foregroundColor(UtterTheme.text3(isDark: isDark))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(UtterTheme.surfaceHover(isDark: isDark).opacity(isHovered ? 0.85 : 0.40))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isHovered ? UtterTheme.borderHover(isDark: isDark) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(UtterScaledButtonStyle(scale: 0.98))
        .animation(UtterTheme.hoverTransition, value: isHovered)
        .onHover { isHovered = $0 }
        .help("Click to copy transcript")
    }
}
