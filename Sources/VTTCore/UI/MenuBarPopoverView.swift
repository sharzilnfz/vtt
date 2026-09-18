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
                    Text("vtt")
                        .font(.system(size: 15, weight: .heavy))
                        .tracking(-0.6)
                        .foregroundColor(VTTTheme.text1(isDark: isDark))

                    Text(".")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(VTTTheme.stateSynced(isDark: isDark))
                }

                Spacer()

                HStack(spacing: 6) {
                    // Status Pill
                    HStack(spacing: 5) {
                        MiniBeaconView(state: beaconState, isDark: isDark, size: 5)
                        Text(statusTitle)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(VTTTheme.text2(isDark: isDark))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(VTTTheme.surfaceHover(isDark: isDark))
                            .overlay(
                                Capsule()
                                    .stroke(VTTTheme.borderSubtle(isDark: isDark), lineWidth: 1)
                            )
                    )

                    // Theme Button
                    Button(action: onToggleTheme) {
                        Image(systemName: isDark ? "moon.fill" : "sun.max.fill")
                            .font(.system(size: 11))
                            .foregroundColor(VTTTheme.text2(isDark: isDark))
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(VTTTheme.surfaceHover(isDark: isDark))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(VTTTheme.borderSubtle(isDark: isDark), lineWidth: 1)
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
                .background(VTTTheme.borderSubtle(isDark: isDark))

            // Mini Telemetry Bar
            HStack(spacing: 0) {
                miniTelemetryItem(label: "WORDS", value: "\(stats?.totalWordsDelivered ?? 0)")
                Rectangle().fill(VTTTheme.borderSubtle(isDark: isDark)).frame(width: 1, height: 12)
                miniTelemetryItem(label: "KEYS", value: "⌃⌥ / ⌥⌘")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(VTTTheme.telemetryBg(isDark: isDark))

            Divider()
                .background(VTTTheme.borderSubtle(isDark: isDark))

            // Last Transcript Preview Card
            if let last = lastTranscript {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("LAST TRANSCRIPT")
                            .font(.system(size: 9.5, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(VTTTheme.text3(isDark: isDark))

                        Spacer()

                        Button(action: onCopyLast) {
                            HStack(spacing: 3) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 9))
                                Text("Copy")
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                            .foregroundColor(VTTTheme.text2(isDark: isDark))
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                        .focusable(false)
                    }

                    Text(last.textToInsert)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundColor(VTTTheme.text1(isDark: isDark))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(VTTTheme.surfaceHover(isDark: isDark))
                )
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }

            // Quick Action Menu Rows
            VStack(spacing: 2) {
                menuRow(
                    icon: "macwindow",
                    title: "Open Dashboard",
                    subtitle: "Full telemetry, safety buffer & settings",
                    shortcut: "⌘,",
                    action: onOpenDashboard
                )

                if case .failed = modelState {
                    menuRow(
                        icon: "arrow.clockwise",
                        title: "Retry Speech Model",
                        subtitle: "Reload CoreML Neural Engine",
                        shortcut: nil,
                        action: onRetryModel
                    )
                }

                menuRow(
                    icon: "doc.on.clipboard",
                    title: "Copy Last Transcript",
                    subtitle: "Send last dictated text to clipboard",
                    shortcut: "⌃V",
                    action: onCopyLast
                )

                Divider()
                    .background(VTTTheme.borderSubtle(isDark: isDark))
                    .padding(.vertical, 4)

                menuRow(
                    icon: "power",
                    title: "Quit VTT",
                    subtitle: nil,
                    shortcut: "⌘Q",
                    action: onQuit
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .frame(width: 310)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(VTTTheme.glassBg(isDark: isDark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            VTTTheme.borderTop(isDark: isDark),
                            VTTTheme.borderGlass(isDark: isDark)
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
                .foregroundColor(VTTTheme.text3(isDark: isDark))
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(VTTTheme.text1(isDark: isDark))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func menuRow(
        icon: String,
        title: String,
        subtitle: String?,
        shortcut: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(VTTTheme.text2(isDark: isDark))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(VTTTheme.text1(isDark: isDark))

                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(size: 9.5))
                            .foregroundColor(VTTTheme.text3(isDark: isDark))
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(VTTTheme.text3(isDark: isDark))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(VTTTheme.surfaceHover(isDark: isDark))
                        )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focusable(false)
    }
}
