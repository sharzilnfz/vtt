import SwiftUI

/// A minimal vector logo for Utter, inspired by Open Code's technical precision
/// and Whisperflow's fluid acoustic resonance.
public struct UtterLogoView: View {
    public var size: CGFloat
    public var isDark: Bool
    public var showBackground: Bool

    public init(size: CGFloat = 32, isDark: Bool = true, showBackground: Bool = false) {
        self.size = size
        self.isDark = isDark
        self.showBackground = showBackground
    }

    public var body: some View {
        ZStack {
            if showBackground {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(
                        isDark
                        ? LinearGradient(
                            colors: [Color(hex: "18181b"), Color(hex: "09090b")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [Color(hex: "ffffff"), Color(hex: "f4f4f5")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                            .stroke(
                                isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
                                lineWidth: max(1, size * 0.004)
                            )
                    )

                // Subtle ambient glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                (isDark ? Color(hex: "38bdf8") : Color(hex: "0284c7")).opacity(isDark ? 0.18 : 0.10),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.40
                        )
                    )
            }

            // Vector Glyph: Geometric U Vessel + 3-Bar Voice Core
            ZStack {
                // The U Vessel
                Path { path in
                    let w = size * (showBackground ? 0.44 : 0.72)
                    let h = size * (showBackground ? 0.44 : 0.72)
                    let left = (size - w) / 2
                    let right = left + w
                    let top = (size - h) / 2 - (size * (showBackground ? 0.04 : 0.03))
                    let bottom = top + h
                    let r = w / 2

                    path.move(to: CGPoint(x: left, y: top))
                    path.addLine(to: CGPoint(x: left, y: bottom - r))
                    path.addArc(
                        center: CGPoint(x: left + r, y: bottom - r),
                        radius: r,
                        startAngle: .degrees(180),
                        endAngle: .degrees(0),
                        clockwise: true
                    )
                    path.addLine(to: CGPoint(x: right, y: top))
                }
                .stroke(
                    isDark ? Color.white : Color(hex: "09090b"),
                    style: StrokeStyle(
                        lineWidth: size * (showBackground ? 0.052 : 0.086),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                // 3-Bar Acoustic Waveform Core
                let barW = size * (showBackground ? 0.036 : 0.060)
                let spacing = size * (showBackground ? 0.026 : 0.042)
                let accentColor = isDark ? Color(hex: "38bdf8") : Color(hex: "0284c7")
                let centerColor = isDark ? Color.white : Color(hex: "09090b")

                HStack(alignment: .center, spacing: spacing) {
                    // Left bar
                    Capsule()
                        .fill(accentColor)
                        .frame(width: barW, height: size * (showBackground ? 0.095 : 0.155))

                    // Center bar (voice peak)
                    Capsule()
                        .fill(centerColor)
                        .frame(width: barW, height: size * (showBackground ? 0.165 : 0.270))

                    // Right bar
                    Capsule()
                        .fill(accentColor)
                        .frame(width: barW, height: size * (showBackground ? 0.095 : 0.155))
                }
                .offset(y: -size * (showBackground ? 0.02 : 0.01))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Logo mark + "utter." wordmark lockup
public struct UtterLockupView: View {
    public var isDark: Bool
    public var size: CGFloat

    public init(isDark: Bool = true, size: CGFloat = 28) {
        self.isDark = isDark
        self.size = size
    }

    public var body: some View {
        HStack(spacing: size * 0.35) {
            UtterLogoView(size: size, isDark: isDark, showBackground: true)

            HStack(spacing: 0) {
                Text("utter")
                    .font(.system(size: size * 0.72, weight: .bold))
                    .tracking(-0.6)
                    .foregroundColor(isDark ? Color(hex: "f8fafc") : Color(hex: "09090b"))

                Text(".")
                    .font(.system(size: size * 0.72, weight: .black))
                    .foregroundColor(isDark ? Color(hex: "38bdf8") : Color(hex: "0284c7"))
            }
        }
    }
}
