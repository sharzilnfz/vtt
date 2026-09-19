import SwiftUI

public enum BeaconState: Sendable, Equatable {
    case synced      // Ready / normal operation (Green)
    case syncing     // Working / Recording / Transcribing (Blue)
    case holding     // Setup needed / waiting (Orange)
    case conflict    // Error / Failed (Red)
    case offline     // Disconnected / Model Loading (Gray)

    public func color(isDark: Bool) -> Color {
        switch self {
        case .synced: return UtterTheme.stateSynced(isDark: isDark)
        case .syncing: return UtterTheme.stateSyncing(isDark: isDark)
        case .holding: return UtterTheme.stateHolding(isDark: isDark)
        case .conflict: return UtterTheme.stateConflict(isDark: isDark)
        case .offline: return UtterTheme.stateOffline(isDark: isDark)
        }
    }

    public func glow(isDark: Bool) -> Color {
        switch self {
        case .synced: return UtterTheme.stateSyncedGlow(isDark: isDark)
        case .syncing: return UtterTheme.stateSyncingGlow(isDark: isDark)
        case .holding: return UtterTheme.stateHoldingGlow(isDark: isDark)
        case .conflict: return UtterTheme.stateConflictGlow(isDark: isDark)
        case .offline: return UtterTheme.stateOfflineGlow(isDark: isDark)
        }
    }

    public var isPulsing: Bool {
        switch self {
        case .syncing, .holding: return true
        case .synced, .conflict, .offline: return false
        }
    }
}

public struct BeaconView: View {
    public let state: BeaconState
    public let isDark: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(state: BeaconState, isDark: Bool) {
        self.state = state
        self.isDark = isDark
    }

    public var body: some View {
        ZStack {
            // Outer Ring
            if state.isPulsing && !reduceMotion {
                TimelineView(.animation) { timeline in
                    let elapsed = timeline.date.timeIntervalSinceReferenceDate
                    let phase = elapsed.truncatingRemainder(dividingBy: 2.2) / 2.2
                    let wave = sin(phase * .pi)
                    let scale = 0.90 + 0.36 * wave
                    let opacity = 0.65 - 0.55 * wave

                    Circle()
                        .stroke(state.color(isDark: isDark), lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                        .scaleEffect(scale)
                        .opacity(opacity)
                }
            } else {
                Circle()
                    .stroke(state.color(isDark: isDark).opacity(state.isPulsing ? 0.5 : 0.25), lineWidth: 1.5)
                    .frame(width: 24, height: 24)
            }

            // Core Dot with tactile light reflection
            Circle()
                .fill(state.color(isDark: isDark))
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.40),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: state.glow(isDark: isDark), radius: 8, x: 0, y: 0)
        }
        .frame(width: 24, height: 24)
        .animation(UtterTheme.springSmooth, value: state)
    }
}

public struct MiniBeaconView: View {
    public let state: BeaconState
    public let isDark: Bool
    public let size: CGFloat

    public init(state: BeaconState, isDark: Bool, size: CGFloat = 6) {
        self.state = state
        self.isDark = isDark
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(state.color(isDark: isDark))
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
            )
            .shadow(color: state.glow(isDark: isDark), radius: 4, x: 0, y: 0)
            .animation(UtterTheme.springSmooth, value: state)
    }
}
