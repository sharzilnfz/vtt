import SwiftUI

public struct IndicatorPillView: View {
    @ObservedObject var viewModel: PillViewModel

    public init(viewModel: PillViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Minimal White Status Indicator
            statusIndicator

            // Dynamic Audio Activity or Processing Wave
            switch viewModel.status {
            case .recording(let level):
                waveformBars(level: CGFloat(max(0.0, min(1.0, level))))
            case .transcribing, .refining, .inserting:
                processingDots
            case .failed:
                failedIndicator
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color(hex: "09090b").opacity(0.88))
                .background(.ultraThinMaterial, in: Capsule())
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.24),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.50), radius: 16, x: 0, y: 6)
    }

    // MARK: - Status Indicator (White / Monochrome)

    @ViewBuilder
    private var statusIndicator: some View {
        ZStack {
            if case .recording = viewModel.status {
                // Soft pulsing outer ring
                TimelineView(.animation) { timeline in
                    let elapsed = timeline.date.timeIntervalSinceReferenceDate
                    let phase = elapsed.truncatingRemainder(dividingBy: 1.8) / 1.8
                    let wave = sin(phase * .pi)
                    let scale = 0.90 + 0.35 * wave
                    let opacity = 0.50 - 0.45 * wave

                    Circle()
                        .stroke(Color.white.opacity(opacity), lineWidth: 1.2)
                        .frame(width: 14, height: 14)
                        .scaleEffect(scale)
                }
            }

            // Core Solid Dot
            Circle()
                .fill(Color.white)
                .frame(width: 5, height: 5)
                .shadow(color: Color.white.opacity(0.5), radius: 4, x: 0, y: 0)
        }
        .frame(width: 14, height: 14)
    }

    // MARK: - Monochrome Waveform Bars (Black & White)

    private func waveformBars(level: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 2.5) {
            bar(height: 3 + 7 * level * 0.75)
            bar(height: 3 + 12 * level * 1.0)
            bar(height: 3 + 10 * level * 0.85)
            bar(height: 3 + 6 * level * 0.60)
        }
        .frame(height: 16)
    }

    private func bar(height: CGFloat) -> some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 2.5, height: max(3, min(16, height)))
            .animation(.easeOut(duration: 0.07), value: height)
    }

    // MARK: - Processing Wave (Transcribing / Refining / Inserting)

    private var processingDots: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    let offset = Double(index) * 0.25
                    let phase = (elapsed + offset).truncatingRemainder(dividingBy: 1.0)
                    let scale = 0.6 + 0.5 * sin(phase * .pi)
                    let opacity = 0.3 + 0.7 * sin(phase * .pi)

                    Circle()
                        .fill(Color.white.opacity(opacity))
                        .frame(width: 3.5, height: 3.5)
                        .scaleEffect(scale)
                }
            }
        }
        .frame(height: 14)
    }

    // MARK: - Failed Indicator

    private var failedIndicator: some View {
        Image(systemName: "exclamationmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(Color.white.opacity(0.9))
            .frame(height: 14)
    }
}
