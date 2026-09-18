import SwiftUI

public struct HeroStageView: View {
    @ObservedObject var state: DashboardState
    let isDark: Bool

    public init(state: DashboardState, isDark: Bool) {
        self.state = state
        self.isDark = isDark
    }

    private var beaconState: BeaconState {
        if !state.permissionsReady {
            return .holding
        }
        switch state.modelState {
        case .failed:
            return .conflict
        case .loading:
            return .offline
        case .ready:
            if state.isRecording || state.isTranscribing {
                return .syncing
            }
            return .synced
        }
    }

    private var heroTitle: String {
        if !state.permissionsReady {
            return "Setup Needed"
        }
        if state.isRecording {
            return "Listening…"
        }
        if state.isTranscribing {
            return "Transcribing…"
        }
        switch state.modelState {
        case .failed:
            return "Offline"
        case .loading:
            return "Loading Model"
        case .ready:
            return "Ready"
        }
    }

    private var stateBadgeText: String {
        if !state.micAuthorized {
            return "Needs Mic"
        }
        if !state.accessTrusted {
            return "Needs Access"
        }
        if state.isRecording {
            return "Audio Active"
        }
        if state.isTranscribing {
            return "Neural Engine"
        }
        switch state.modelState {
        case .failed:
            return "Engine Error"
        case .loading:
            return "Initializing"
        case .ready:
            return "On-Device"
        }
    }

    private var heroSubtitle: String {
        if !state.micAuthorized && !state.accessTrusted {
            return "Microphone and Accessibility permissions required for local speech recognition and system typing."
        }
        if !state.micAuthorized {
            return "Microphone permission is required to capture your speech."
        }
        if !state.accessTrusted {
            return "Accessibility permission is required to type text directly into focused applications."
        }
        if state.isRecording {
            return "Capturing live audio from microphone. Release keys when finished speaking."
        }
        if state.isTranscribing {
            return "Running Neural Engine CoreML speech recognition on-device. Zero data leaves your Mac."
        }
        switch state.modelState {
        case .failed(let err):
            return "Model failed to load: \(err). Click Retry to reload."
        case .loading:
            return "Preloading \(state.speechModelLabel) CoreML model into Neural Engine memory…"
        case .ready:
            return "Hold Ctrl + Option to write. Option + Command to clean. Ctrl + V to paste last."
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // Status Line: Beacon + Title + Badge
            HStack(alignment: .center, spacing: 10) {
                BeaconView(state: beaconState, isDark: isDark)

                Text(heroTitle)
                    .font(.system(size: 21, weight: .bold))
                    .tracking(-0.5)
                    .foregroundColor(VTTTheme.text1(isDark: isDark))

                Text(stateBadgeText)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(VTTTheme.text2(isDark: isDark))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(VTTTheme.surfaceHover(isDark: isDark))
                            .overlay(
                                Capsule()
                                    .stroke(VTTTheme.borderSubtle(isDark: isDark), lineWidth: 1)
                            )
                    )

                Spacer()
            }

            // Subtitle
            Text(heroSubtitle)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundColor(VTTTheme.text2(isDark: isDark))
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)

            // Action Buttons Row
            HStack(spacing: 8) {
                if !state.permissionsReady {
                    Button(action: {
                        if !state.micAuthorized {
                            state.requestMicrophone()
                        } else {
                            state.requestAccessibility()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 12, weight: .bold))
                            Text("Grant Access")
                        }
                    }
                    .buttonStyle(VTTPrimaryButtonStyle(isDark: isDark))
                    .focusEffectDisabled()
                } else if case .failed = state.modelState {
                    Button(action: { state.onRetryModel?() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .bold))
                            Text("Retry Model")
                        }
                    }
                    .buttonStyle(VTTPrimaryButtonStyle(isDark: isDark))
                    .focusEffectDisabled()
                } else {
                    Button(action: {
                        state.refreshPermissions()
                        state.refreshActivitiesFromTranscripts()
                        state.showTransientBanner("System Status Refreshed", type: .success)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .bold))
                            Text("Refresh")
                        }
                    }
                    .buttonStyle(VTTPrimaryButtonStyle(isDark: isDark))
                    .focusEffectDisabled()
                }

                Button(action: {
                    state.copyLastTranscript()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 11, weight: .medium))
                        Text("Paste Last")
                    }
                }
                .buttonStyle(VTTGhostButtonStyle(isDark: isDark))
                .focusEffectDisabled()
                .disabled(state.safetyBuffer.lastTranscript == nil)

                Button(action: {
                    state.showGatewaySheet = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .medium))
                        Text("AI Cleanup")
                    }
                }
                .buttonStyle(VTTGhostButtonStyle(isDark: isDark))
                .focusEffectDisabled()

                Button(action: {
                    state.showVocabularySheet = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.badge.plus")
                            .font(.system(size: 11, weight: .medium))
                        Text("+ Vocabulary")
                    }
                }
                .buttonStyle(VTTGhostButtonStyle(isDark: isDark))
                .focusEffectDisabled()

                Button(action: {
                    state.showSpeechSheet = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.circle")
                            .font(.system(size: 11, weight: .medium))
                        Text(state.speechModelLabel.isEmpty ? "Model" : state.speechModelLabel)
                    }
                }
                .buttonStyle(VTTGhostButtonStyle(isDark: isDark))
                .focusEffectDisabled()
            }
            .padding(.top, 4)

            // Progress / Audio Level Track
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(VTTTheme.borderSubtle(isDark: isDark))
                    .frame(height: 3)

                if state.isRecording {
                    // Responsive level bar
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(VTTTheme.stateSyncing(isDark: isDark))
                            .frame(width: max(8, geo.size.width * CGFloat(min(1.0, max(0.05, state.audioLevel)))))
                            .animation(.easeOut(duration: 0.1), value: state.audioLevel)
                    }
                    .frame(height: 3)
                } else if state.isTranscribing || state.modelState == .loading {
                    // Smooth Shimmer
                    TimelineView(.animation) { timeline in
                        GeometryReader { geo in
                            let phase = CGFloat((timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4)) / 1.4)
                            let barWidth = geo.size.width * 0.35
                            let start = -barWidth
                            let end = geo.size.width
                            let currentX = start + (end - start) * phase

                            RoundedRectangle(cornerRadius: 2)
                                .fill(VTTTheme.stateSyncing(isDark: isDark))
                                .frame(width: barWidth)
                                .offset(x: currentX)
                        }
                    }
                    .frame(height: 3)
                    .clipped()
                }
            }
            .frame(height: 3)
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}
