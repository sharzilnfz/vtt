import SwiftUI

public struct DashboardView: View {
    @ObservedObject public var state: DashboardState

    public init(state: DashboardState) {
        self.state = state
    }

    private var isDark: Bool {
        state.isDarkMode
    }

    public var body: some View {
        VStack(spacing: 10) {
            // Header Bar (aligned with macOS traffic lights)
            headerView
                .padding(.horizontal, 16)
                .padding(.top, 12)

            // Main Inner Glass Sub-Box Card
            mainSubBoxCard
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(width: 660, height: 550)
        .background(
            ZStack {
                // Outer Canvas Background
                UtterTheme.canvasBg(isDark: isDark)
                    .ignoresSafeArea()

                // Subtle ambient radial glow
                ambientGlow
            }
        )
        .preferredColorScheme(isDark ? .dark : .light)
        .sheet(isPresented: $state.showGatewaySheet) {
            GatewaySettingsSheet(state: state, isDark: isDark)
        }
        .sheet(isPresented: $state.showVocabularySheet) {
            VocabularySheet(state: state, isDark: isDark)
        }
        .sheet(isPresented: $state.showSpeechSheet) {
            SpeechModelSheet(state: state, isDark: isDark)
        }
    }

    // MARK: - Ambient Glow

    private var ambientGlow: some View {
        RadialGradient(
            gradient: Gradient(colors: [
                Color(hex: "0ea5e9").opacity(isDark ? 0.08 : 0.04),
                Color.clear
            ]),
            center: .top,
            startRadius: 0,
            endRadius: 300
        )
        .allowsHitTesting(false)
    }

    // MARK: - App Header (Window Titlebar Layer)

    private var headerView: some View {
        HStack(alignment: .center) {
            // Space reserved for macOS window traffic lights (close, minimize)
            Spacer()
                .frame(width: 58)

            // Brand Logo: utter.
            HStack(spacing: 0) {
                Text("utter")
                    .font(.system(size: 16, weight: .heavy))
                    .tracking(-0.6)
                    .foregroundColor(UtterTheme.text1(isDark: isDark))

                Text(".")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(UtterTheme.stateSynced(isDark: isDark))
            }

            Spacer()

            // Header Actions: Status Pill + Theme Toggle
            HStack(spacing: 8) {
                // Status Pill
                HStack(spacing: 5) {
                    MiniBeaconView(state: headerBeaconState, isDark: isDark, size: 5)

                    Text(headerStatusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(UtterTheme.text2(isDark: isDark))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(
                    Capsule()
                        .fill(UtterTheme.surfaceHover(isDark: isDark))
                        .overlay(
                            Capsule()
                                .stroke(UtterTheme.borderSubtle(isDark: isDark), lineWidth: 1)
                        )
                )

                // Theme Toggle Button
                Button(action: {
                    state.toggleTheme()
                }) {
                    Image(systemName: isDark ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(UtterIconButtonStyle(isDark: isDark))
                .focusEffectDisabled()
                .help("Toggle Dark / Light Theme")
            }
        }
        .frame(height: 28)
    }

    // MARK: - Main Sub-Box Glass Card

    private var mainSubBoxCard: some View {
        VStack(spacing: 0) {
            // Transient Banner Message (if present)
            if let banner = state.bannerMessage {
                HStack(spacing: 8) {
                    Image(systemName: bannerIconName)
                        .font(.system(size: 11, weight: .bold))
                    Text(banner)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundColor(bannerColor)
                .background(bannerColor.opacity(0.12))
                .overlay(
                    Rectangle()
                        .stroke(bannerColor.opacity(0.3), lineWidth: 1)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Hero Stage: Title, Beacon, Subtitle, Actions, Audio Track
            HeroStageView(state: state, isDark: isDark)

            // Telemetry Strip: 5 Columns
            TelemetryStripView(state: state, isDark: isDark)

            // Lower Content Flow (2 Columns: System/Shortcuts on left, Activity on right)
            FlowColumnsView(state: state, isDark: isDark)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(UtterTheme.glassBg(isDark: isDark))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            UtterTheme.borderTop(isDark: isDark),
                            UtterTheme.borderGlass(isDark: isDark),
                            UtterTheme.borderGlass(isDark: isDark)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(
            color: isDark ? Color.black.opacity(0.45) : Color.black.opacity(0.08),
            radius: 16,
            x: 0,
            y: 8
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var headerBeaconState: BeaconState {
        if !state.permissionsReady {
            return .holding
        }
        switch state.modelState {
        case .ready:
            return state.isRecording || state.isTranscribing ? .syncing : .synced
        case .loading:
            return .offline
        case .failed:
            return .conflict
        }
    }

    private var headerStatusText: String {
        if !state.permissionsReady {
            return "Setup Needed"
        }
        if state.isRecording {
            return "Listening"
        }
        if state.isTranscribing {
            return "Processing"
        }
        switch state.modelState {
        case .ready: return "Ready"
        case .loading: return "Loading"
        case .failed: return "Offline"
        }
    }

    private var bannerColor: Color {
        switch state.bannerType {
        case .info: return UtterTheme.stateSyncing(isDark: isDark)
        case .warning: return UtterTheme.stateHolding(isDark: isDark)
        case .error: return UtterTheme.stateConflict(isDark: isDark)
        case .success: return UtterTheme.stateSynced(isDark: isDark)
        }
    }

    private var bannerIconName: String {
        switch state.bannerType {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        case .success: return "checkmark.circle"
        }
    }
}
