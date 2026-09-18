import SwiftUI

public enum BeaconState: Sendable, Equatable {
    case synced      // Ready / normal operation (Green)
    case syncing     // Working / Recording / Transcribing (Blue)
    case holding     // Setup needed / waiting (Orange)
    case conflict    // Error / Failed (Red)
    case offline     // Disconnected / Model Loading (Gray)

    public func color(isDark: Bool) -> Color {
        switch self {
        case .synced: return VTTTheme.stateSynced(isDark: isDark)
        case .syncing: return VTTTheme.stateSyncing(isDark: isDark)
        case .holding: return VTTTheme.stateHolding(isDark: isDark)
        case .conflict: return VTTTheme.stateConflict(isDark: isDark)
        case .offline: return VTTTheme.stateOffline(isDark: isDark)
        }
    }

    public func glow(isDark: Bool) -> Color {
        switch self {
        case .synced: return VTTTheme.stateSyncedGlow(isDark: isDark)
        case .syncing: return VTTTheme.stateSyncingGlow(isDark: isDark)
        case .holding: return VTTTheme.stateHoldingGlow(isDark: isDark)
        case .conflict: return VTTTheme.stateConflictGlow(isDark: isDark)
        case .offline: return VTTTheme.stateOfflineGlow(isDark: isDark)
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

    public init(state: BeaconState, isDark: Bool) {
        self.state = state
        self.isDark = isDark
    }

    public var body: some View {
        ZStack {
            // Outer Ring
            if state.isPulsing {
                TimelineView(.animation) { timeline in
                    let elapsed = timeline.date.timeIntervalSinceReferenceDate
                    let phase = elapsed.truncatingRemainder(dividingBy: 2.4) / 2.4
                    let wave = sin(phase * .pi)
                    let scale = 0.92 + 0.38 * wave
                    let opacity = 0.70 - 0.65 * wave

                    Circle()
                        .stroke(state.color(isDark: isDark), lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                        .scaleEffect(scale)
                        .opacity(opacity)
                }
            } else {
                Circle()
                    .stroke(state.color(isDark: isDark).opacity(0.3), lineWidth: 1.5)
                    .frame(width: 24, height: 24)
            }

            // Core Dot
            Circle()
                .fill(state.color(isDark: isDark))
                .frame(width: 10, height: 10)
                .shadow(color: state.glow(isDark: isDark), radius: 8, x: 0, y: 0)
        }
        .frame(width: 24, height: 24)
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
            .shadow(color: state.glow(isDark: isDark), radius: 4, x: 0, y: 0)
    }
}
