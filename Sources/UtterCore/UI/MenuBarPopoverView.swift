import SwiftUI

public struct MenuBarPopoverView: View {
    let modelState: ModelLoadState
    let permissionsReady: Bool
    let lastTranscript: Transcript?
    let stats: DictationStats?
    let isDark: Bool

    var onOpenDashboard: () -> Void
    var onCopyLast: () -> Void
    var onRetryModel: () -> Void
    var onQuit: () -> Void
    var onToggleTheme: () -> Void

    public init(
        modelState: ModelLoadState,
        permissionsReady: Bool,
        lastTranscript: Transcript?,
        stats: DictationStats?,
        isDark: Bool,
        onOpenDashboard: @escaping () -> Void,
        onCopyLast: @escaping () -> Void,
        onRetryModel: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        onToggleTheme: @escaping () -> Void
    ) {
        self.modelState = modelState
        self.permissionsReady = permissionsReady
        self.lastTranscript = lastTranscript
        self.stats = stats
        self.isDark = isDark
        self.onOpenDashboard = onOpenDashboard
        self.onCopyLast = onCopyLast
        self.onRetryModel = onRetryModel
        self.onQuit = onQuit
        self.onToggleTheme = onToggleTheme
    }

    private var beaconState: BeaconState {
        if !permissionsReady { return .holding }
        switch modelState {
        case .ready: return .synced
        case .loading: return .syncing
        case .failed: return .conflict
        }
    }

    private var statusTitle: String {
        if !permissionsReady { return "Setup Required" }
        switch modelState {
        case .ready: return "Ready"
        case .loading: return "Loading Model"
        case .failed: return "Model Offline"
        }
    }

    private var badgeText: String {
        if !permissionsReady { return "Action Needed" }
        switch modelState {
        case .ready: return "On-Device"
        case .loading: return "CoreML"
        case .failed: return "Error"
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header: Brand + Status Pill + Theme Button
            HStack {
                HStack(spacing: 0) {
                    Text("utter")
                        .font(.system(size: 15, weight: .heavy))
                        .tracking(-0.6)
                        .foregroundColor(UtterTheme.text1(isDark: isDark))

                    Text(".")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(UtterTheme.stateSynced(isDark: isDark))
                }

                Spacer()

                HStack(spacing: 6) {
                    // Status Pill
                    HStack(spacing: 5) {
                        MiniBeaconView(state: beaconState, isDark: isDark, size: 5)
                        Text(statusTitle)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(UtterTheme.text2(isDark: isDark))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(UtterTheme.surfaceHover(isDark: isDark))
                            .overlay(
                                Capsule()
                                    .stroke(UtterTheme.borderSubtle(isDark: isDark), lineWidth: 1)
                            )
                    )

                    // Theme Button
                    Button(action: onToggleTheme) {
                        Image(systemName: isDark ? "moon.fill" : "sun.max.fill")
                            .font(.system(size: 11))
                            .foregroundColor(UtterTheme.text2(isDark: isDark))
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(UtterTheme.surfaceHover(isDark: isDark))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(UtterTheme.borderSubtle(isDark: isDark), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .focusable(false)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()
                .background(UtterTheme.borderSubtle(isDark: isDark))

            // Mini Telemetry Bar
            HStack(spacing: 0) {
                miniTelemetryItem(label: "WORDS", value: "\(stats?.totalWordsDelivered ?? 0)")
                Rectangle().fill(UtterTheme.borderSubtle(isDark: isDark)).frame(width: 1, height: 12)
                miniTelemetryItem(label: "KEYS", value: "⌃⌥ / ⌥⌘ / ⌃V")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(UtterTheme.telemetryBg(isDark: isDark))

            Divider()
                .background(UtterTheme.borderSubtle(isDark: isDark))

            // Last Transcript Preview Card
            if let last = lastTranscript {
                PopoverLastTranscriptCard(
                    transcript: last,
                    isDark: isDark,
                    onCopy: onCopyLast
                )
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }

            // Quick Action Menu Rows
            VStack(spacing: 2) {
                PopoverMenuRow(
                    icon: "macwindow",
                    title: "Open Dashboard",
                    subtitle: "Full telemetry, safety buffer & settings",
                    shortcut: "⌘,",
                    isDark: isDark,
                    action: onOpenDashboard
                )

                if case .failed = modelState {
                    PopoverMenuRow(
                        icon: "arrow.clockwise",
                        title: "Retry Speech Model",
                        subtitle: "Reload CoreML Neural Engine",
                        shortcut: nil,
                        isDark: isDark,
                        action: onRetryModel
                    )
                }

                PopoverMenuRow(
                    icon: "doc.on.clipboard",
                    title: "Copy Last Transcript",
                    subtitle: "Send last dictated text to clipboard",
                    shortcut: "⌃V",
                    isDark: isDark,
                    action: onCopyLast
                )

                Divider()
                    .background(UtterTheme.borderSubtle(isDark: isDark))
                    .padding(.vertical, 4)

                PopoverMenuRow(
                    icon: "power",
                    title: "Quit Utter",
                    subtitle: nil,
                    shortcut: "⌘Q",
                    isDark: isDark,
                    action: onQuit
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .frame(width: 310)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(UtterTheme.glassBg(isDark: isDark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            UtterTheme.borderTop(isDark: isDark),
                            UtterTheme.borderGlass(isDark: isDark)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(
            color: isDark ? Color.black.opacity(0.6) : Color.black.opacity(0.12),
            radius: 20,
            x: 0,
            y: 10
        )
    }

    private func miniTelemetryItem(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.4)
                .foregroundColor(UtterTheme.text3(isDark: isDark))
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(UtterTheme.text1(isDark: isDark))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Popover Subcomponents with macOS Native Feel

struct PopoverMenuRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    let shortcut: String?
    let isDark: Bool
    let action: () -> Void
    @LocalState private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isHovered ? UtterTheme.text1(isDark: isDark) : UtterTheme.text2(isDark: isDark))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(UtterTheme.text1(isDark: isDark))

                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(size: 9.5))
                            .foregroundColor(UtterTheme.text3(isDark: isDark))
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(isHovered ? UtterTheme.text2(isDark: isDark) : UtterTheme.text3(isDark: isDark))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(UtterTheme.surfaceHover(isDark: isDark).opacity(isHovered ? 0.9 : 0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(UtterTheme.borderSubtle(isDark: isDark), lineWidth: 0.8)
                                )
                        )
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5.5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isHovered
                            ? UtterTheme.surfaceHover(isDark: isDark).opacity(0.9)
                            : Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isHovered ? UtterTheme.borderHover(isDark: isDark) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(UtterTheme.hoverTransition, value: isHovered)
        .onHover { isHovered = $0 }
        .focusEffectDisabled()
        .focusable(false)
    }
}

struct PopoverLastTranscriptCard: View {
    let transcript: Transcript
    let isDark: Bool
    let onCopy: () -> Void
    @LocalState private var isCopyHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("LAST TRANSCRIPT")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(UtterTheme.text3(isDark: isDark))

                Spacer()

                Button(action: onCopy) {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                        Text("Copy")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .foregroundColor(isCopyHovered ? UtterTheme.text1(isDark: isDark) : UtterTheme.text2(isDark: isDark))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isCopyHovered ? UtterTheme.surfaceHover(isDark: isDark) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .focusable(false)
                .onHover { isCopyHovered = $0 }
            }

            Text(transcript.textToInsert)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundColor(UtterTheme.text1(isDark: isDark))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(UtterTheme.surfaceHover(isDark: isDark).opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(UtterTheme.borderSubtle(isDark: isDark), lineWidth: 1)
                )
        )
    }
}
