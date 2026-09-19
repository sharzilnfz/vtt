import SwiftUI

// MARK: - Color Extension for Hex Support

extension Color {
    public init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch clean.count {
        case 6:
            (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (255, 255, 255, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Design System Tokens

public enum UtterTheme {
    // Canvas Background
    public static func canvasBg(isDark: Bool) -> Color {
        isDark ? Color(hex: "09090b") : Color(hex: "f6f7fb")
    }

    // Glass Card Background
    public static func glassBg(isDark: Bool) -> Color {
        isDark ? Color(hex: "121216").opacity(0.82) : Color.white.opacity(0.92)
    }

    // Borders
    public static func borderGlass(isDark: Bool) -> Color {
        isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    public static func borderTop(isDark: Bool) -> Color {
        isDark ? Color.white.opacity(0.18) : Color.white.opacity(0.95)
    }

    public static func borderSubtle(isDark: Bool) -> Color {
        isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
    }

    public static func borderHover(isDark: Bool) -> Color {
        isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.14)
    }

    // Surfaces
    public static func surfaceHover(isDark: Bool) -> Color {
        isDark ? Color.white.opacity(0.045) : Color.black.opacity(0.035)
    }

    public static func surfaceActive(isDark: Bool) -> Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)
    }

    // Text Hierarchy
    public static func text1(isDark: Bool) -> Color {
        isDark ? Color(hex: "f8fafc") : Color(hex: "0f172a")
    }

    public static func text2(isDark: Bool) -> Color {
        isDark ? Color(hex: "8e8e93") : Color(hex: "64748b")
    }

    public static func text3(isDark: Bool) -> Color {
        isDark ? Color(hex: "58585e") : Color(hex: "94a3b8")
    }

    // State Colors
    public static func stateSynced(isDark: Bool) -> Color {
        isDark ? Color(hex: "30d158") : Color(hex: "16a34a")
    }

    public static func stateSyncedGlow(isDark: Bool) -> Color {
        isDark ? Color(hex: "30d158").opacity(0.35) : Color(hex: "16a34a").opacity(0.25)
    }

    public static func stateSyncing(isDark: Bool) -> Color {
        isDark ? Color(hex: "0a84ff") : Color(hex: "0284c7")
    }

    public static func stateSyncingGlow(isDark: Bool) -> Color {
        isDark ? Color(hex: "0a84ff").opacity(0.35) : Color(hex: "0284c7").opacity(0.25)
    }

    public static func stateHolding(isDark: Bool) -> Color {
        isDark ? Color(hex: "ff9f0a") : Color(hex: "d97706")
    }

    public static func stateHoldingGlow(isDark: Bool) -> Color {
        isDark ? Color(hex: "ff9f0a").opacity(0.35) : Color(hex: "d97706").opacity(0.25)
    }

    public static func stateConflict(isDark: Bool) -> Color {
        isDark ? Color(hex: "ff453a") : Color(hex: "dc2626")
    }

    public static func stateConflictGlow(isDark: Bool) -> Color {
        isDark ? Color(hex: "ff453a").opacity(0.35) : Color(hex: "dc2626").opacity(0.25)
    }

    public static func stateOffline(isDark: Bool) -> Color {
        isDark ? Color(hex: "636366") : Color(hex: "71717a")
    }

    public static func stateOfflineGlow(isDark: Bool) -> Color {
        isDark ? Color(hex: "636366").opacity(0.20) : Color(hex: "71717a").opacity(0.15)
    }

    // Telemetry Background
    public static func telemetryBg(isDark: Bool) -> Color {
        isDark ? Color.black.opacity(0.18) : Color.black.opacity(0.02)
    }

    // MARK: - Motion & Animation Tokens (Emil Kowalski & Apple Design)
    public static let springSnappy = Animation.spring(response: 0.32, dampingFraction: 0.86)
    public static let springSmooth = Animation.spring(response: 0.42, dampingFraction: 0.96)
    public static let springResponsive = Animation.spring(response: 0.16, dampingFraction: 0.80)
    public static let pressFeedback = Animation.easeOut(duration: 0.12)
    public static let hoverTransition = Animation.easeOut(duration: 0.15)
}

// MARK: - Custom Button Styles

public struct UtterPrimaryButtonStyle: ButtonStyle {
    let isDark: Bool
    public init(isDark: Bool) { self.isDark = isDark }

    public func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonContent(configuration: configuration, isDark: isDark)
    }

    private struct PrimaryButtonContent: View {
        let configuration: Configuration
        let isDark: Bool
        @LocalState private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isDark ? Color(hex: "09090b") : .white)
                .padding(.horizontal, 13)
                .padding(.vertical, 6.5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isDark ? Color(hex: "f8fafc") : Color(hex: "0f172a"))
                        .opacity(configuration.isPressed ? 0.88 : (isHovered ? 0.96 : 1.0))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isDark ? 0.35 : 0.20),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .scaleEffect(configuration.isPressed ? 0.97 : (isHovered ? 1.01 : 1.0))
                .animation(UtterTheme.pressFeedback, value: configuration.isPressed)
                .animation(UtterTheme.hoverTransition, value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}

public struct UtterGhostButtonStyle: ButtonStyle {
    let isDark: Bool
    public init(isDark: Bool) { self.isDark = isDark }

    public func makeBody(configuration: Configuration) -> some View {
        GhostButtonContent(configuration: configuration, isDark: isDark)
    }

    private struct GhostButtonContent: View {
        let configuration: Configuration
        let isDark: Bool
        @LocalState private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(UtterTheme.text1(isDark: isDark))
                .padding(.horizontal, 11)
                .padding(.vertical, 6.5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            configuration.isPressed
                                ? UtterTheme.surfaceActive(isDark: isDark)
                                : (isHovered ? UtterTheme.surfaceHover(isDark: isDark) : UtterTheme.surfaceHover(isDark: isDark).opacity(0.40))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(
                                    isHovered
                                        ? UtterTheme.borderHover(isDark: isDark)
                                        : UtterTheme.borderSubtle(isDark: isDark),
                                    lineWidth: 1
                                )
                        )
                )
                .scaleEffect(configuration.isPressed ? 0.97 : (isHovered ? 1.01 : 1.0))
                .animation(UtterTheme.pressFeedback, value: configuration.isPressed)
                .animation(UtterTheme.hoverTransition, value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}

public struct UtterGhostSmallButtonStyle: ButtonStyle {
    let isDark: Bool
    public init(isDark: Bool) { self.isDark = isDark }

    public func makeBody(configuration: Configuration) -> some View {
        GhostSmallButtonContent(configuration: configuration, isDark: isDark)
    }

    private struct GhostSmallButtonContent: View {
        let configuration: Configuration
        let isDark: Bool
        @LocalState private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(UtterTheme.text1(isDark: isDark))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            configuration.isPressed
                                ? UtterTheme.surfaceActive(isDark: isDark)
                                : (isHovered ? UtterTheme.surfaceHover(isDark: isDark) : UtterTheme.surfaceHover(isDark: isDark).opacity(0.45))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(
                                    isHovered
                                        ? UtterTheme.borderHover(isDark: isDark)
                                        : UtterTheme.borderSubtle(isDark: isDark),
                                    lineWidth: 1
                                )
                        )
                )
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .animation(UtterTheme.pressFeedback, value: configuration.isPressed)
                .animation(UtterTheme.hoverTransition, value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}

public struct UtterIconButtonStyle: ButtonStyle {
    let isDark: Bool
    public init(isDark: Bool) { self.isDark = isDark }

    public func makeBody(configuration: Configuration) -> some View {
        IconButtonContent(configuration: configuration, isDark: isDark)
    }

    private struct IconButtonContent: View {
        let configuration: Configuration
        let isDark: Bool
        @LocalState private var isHovered = false

        var body: some View {
            configuration.label
                .frame(width: 26, height: 26)
                .foregroundColor(isHovered ? UtterTheme.text1(isDark: isDark) : UtterTheme.text2(isDark: isDark))
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            configuration.isPressed
                                ? UtterTheme.surfaceActive(isDark: isDark)
                                : (isHovered ? UtterTheme.surfaceHover(isDark: isDark) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(
                                    isHovered
                                        ? UtterTheme.borderHover(isDark: isDark)
                                        : UtterTheme.borderSubtle(isDark: isDark),
                                    lineWidth: 1
                                )
                        )
                )
                .scaleEffect(configuration.isPressed ? 0.96 : (isHovered ? 1.02 : 1.0))
                .animation(UtterTheme.pressFeedback, value: configuration.isPressed)
                .animation(UtterTheme.hoverTransition, value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}

@propertyWrapper
public struct LocalState<Value>: DynamicProperty {
    private var state: State<Value>

    public init(wrappedValue: Value) {
        self.state = State(wrappedValue: wrappedValue)
    }

    public var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }

    public var projectedValue: Binding<Value> {
        state.projectedValue
    }
}
