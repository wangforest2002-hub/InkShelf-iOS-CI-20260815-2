import SwiftUI

private struct AmbientMotionEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Ambient decoration keeps moving only while its screen is actually
    /// visible. Navigation destinations and inactive tabs can therefore keep
    /// their state without running hidden animation loops behind the reader.
    var ambientMotionEnabled: Bool {
        get { self[AmbientMotionEnabledKey.self] }
        set { self[AmbientMotionEnabledKey.self] = newValue }
    }
}

enum AppTheme {
    static let accent = Color(red: 0.26, green: 0.56, blue: 0.98)
    static let cyan = Color(red: 0.24, green: 0.80, blue: 0.94)
    static let mint = Color(red: 0.30, green: 0.84, blue: 0.68)
    static let lilac = Color(red: 0.69, green: 0.52, blue: 0.98)
    static let coral = Color(red: 1.0, green: 0.48, blue: 0.59)
    static let honey = Color(red: 1.0, green: 0.72, blue: 0.32)
    static let peach = Color(red: 1.0, green: 0.73, blue: 0.67)
    static let cream = Color(red: 1.0, green: 0.975, blue: 0.92)
    static let wood = Color(red: 0.72, green: 0.47, blue: 0.31)
    static let midnight = Color(red: 0.045, green: 0.035, blue: 0.105)
    static let nightLamp = Color(red: 0.36, green: 0.20, blue: 0.20)

    static let accentGradient = LinearGradient(
        colors: [cyan, accent, lilac],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Shared motion timing keeps cards, panels and reader chrome feeling like one app.
enum AppMotion {
    static let press = Animation.snappy(duration: 0.15)
    static let value = Animation.smooth(duration: 0.18)
    static let panel = Animation.spring(response: 0.34, dampingFraction: 0.92)
    static let reveal = Animation.spring(response: 0.42, dampingFraction: 0.90)
}

struct AuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.ambientMotionEnabled) private var ambientMotionEnabled
    @State private var animate = false

    private var canAnimate: Bool {
        ambientMotionEnabled && scenePhase == .active && !reduceMotion
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [AppTheme.midnight, Color(red: 0.08, green: 0.075, blue: 0.17)]
                    : [AppTheme.cream, Color(red: 0.94, green: 0.985, blue: 1.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppTheme.honey.opacity(colorScheme == .dark ? 0.13 : 0.20), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 250
                    )
                )
                .frame(width: 520, height: 520)
                .offset(x: animate ? -90 : 80, y: animate ? -330 : -250)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppTheme.lilac.opacity(colorScheme == .dark ? 0.22 : 0.14), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 220
                    )
                )
                .frame(width: 460, height: 460)
                .offset(x: animate ? 130 : -120, y: animate ? -230 : -110)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppTheme.cyan.opacity(colorScheme == .dark ? 0.17 : 0.15), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 210
                    )
                )
                .frame(width: 440, height: 440)
                .offset(x: animate ? -150 : 110, y: animate ? 260 : 170)

            LinearGradient(
                colors: [.clear, AppTheme.peach.opacity(colorScheme == .dark ? 0.05 : 0.10), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .rotationEffect(.degrees(-18))
            .offset(x: animate ? 100 : -40)
        }
        .ignoresSafeArea()
        .task(id: canAnimate) {
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { animate = false }
            guard canAnimate else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
        .accessibilityHidden(true)
    }
}

struct CozyWindowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.ambientMotionEnabled) private var ambientMotionEnabled
    @State private var glowing = false
    @State private var drifting = false

    private var canAnimate: Bool {
        ambientMotionEnabled && scenePhase == .active && !reduceMotion
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let frameWidth = max(5, size.width * 0.055)

            ZStack {
                RoundedRectangle(cornerRadius: size.width * 0.16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(red: 0.14, green: 0.18, blue: 0.34), Color(red: 0.24, green: 0.14, blue: 0.24)]
                                : [Color(red: 0.68, green: 0.91, blue: 1.0), Color(red: 1.0, green: 0.85, blue: 0.68)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    (colorScheme == .dark ? AppTheme.honey : Color.white)
                                        .opacity(glowing ? 0.42 : 0.18),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: size.width * 0.19
                            )
                        )
                        .frame(width: size.width * 0.42)
                        .scaleEffect(glowing ? 1.06 : 0.92)

                    Circle()
                        .fill(colorScheme == .dark ? AppTheme.cream : AppTheme.honey)
                        .frame(width: size.width * 0.24)
                        .shadow(
                            color: (colorScheme == .dark ? AppTheme.honey : Color.white).opacity(0.32),
                            radius: 8
                        )
                }
                .offset(x: size.width * 0.22, y: -size.height * 0.20)

                Image(systemName: colorScheme == .dark ? "sparkles" : "cloud.fill")
                    .font(.system(size: size.width * 0.15, weight: .medium))
                    .foregroundStyle(.white.opacity(colorScheme == .dark ? 0.70 : 0.82))
                    .offset(
                        x: drifting ? -size.width * 0.10 : -size.width * 0.25,
                        y: drifting ? -size.height * 0.11 : -size.height * 0.06
                    )
                    .scaleEffect(drifting ? 1.04 : 0.96)

                VStack {
                    Spacer()
                    HStack(alignment: .bottom, spacing: 3) {
                        Image(systemName: "house.fill")
                        Image(systemName: "tree.fill")
                            .font(.system(size: size.width * 0.13))
                    }
                    .font(.system(size: size.width * 0.19, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? AppTheme.lilac.opacity(0.65) : AppTheme.mint.opacity(0.78))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, size.width * 0.12)
                    .padding(.bottom, size.height * 0.08)
                }

                Rectangle()
                    .fill(.white.opacity(colorScheme == .dark ? 0.20 : 0.78))
                    .frame(width: frameWidth)
                Rectangle()
                    .fill(.white.opacity(colorScheme == .dark ? 0.20 : 0.78))
                    .frame(height: frameWidth)

                RoundedRectangle(cornerRadius: size.width * 0.16, style: .continuous)
                    .stroke(.white.opacity(colorScheme == .dark ? 0.22 : 0.86), lineWidth: frameWidth)
            }
            .shadow(color: AppTheme.honey.opacity(colorScheme == .dark ? 0.15 : 0.22), radius: 16, y: 8)
        }
        .task(id: canAnimate) {
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) {
                glowing = false
                drifting = false
            }
            guard canAnimate else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                glowing = true
            }
            withAnimation(.easeInOut(duration: 7.5).repeatForever(autoreverses: true)) {
                drifting = true
            }
        }
        .accessibilityHidden(true)
    }
}

struct WarmLightSweep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.ambientMotionEnabled) private var ambientMotionEnabled
    @State private var moving = false

    private var canAnimate: Bool {
        ambientMotionEnabled && scenePhase == .active && !reduceMotion
    }

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [.clear, AppTheme.honey.opacity(0.18), .white.opacity(0.13), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: max(100, proxy.size.width * 0.52))
            .rotationEffect(.degrees(-16))
            .offset(x: canAnimate ? (moving ? proxy.size.width * 1.35 : -proxy.size.width) : -proxy.size.width)
            .opacity(canAnimate ? 1 : 0)
        }
        .clipped()
        .allowsHitTesting(false)
        .task(id: canAnimate) {
            var initialReset = Transaction()
            initialReset.disablesAnimations = true
            withTransaction(initialReset) { moving = false }
            guard canAnimate else { return }
            while !Task.isCancelled {
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) { moving = false }
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 1.15)) { moving = true }
                try? await Task.sleep(for: .seconds(7.5))
            }
        }
        .accessibilityHidden(true)
    }
}

struct PressableCardStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(reduceMotion ? nil : AppMotion.press, value: configuration.isPressed)
    }
}

/// A single, predictable day/night switch shared by the main browsing screens.
/// "Follow System" remains available in Settings, while tapping this button
/// always chooses an explicit mode so the visual response is immediate.
struct AppearanceModeButton: View {
    @AppStorage("appearance") private var appearance = AppAppearance.light.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var isNight: Bool { colorScheme == .dark }

    var body: some View {
        Button(action: toggle) {
            Label(
                isNight ? "切换到日间模式" : "切换到夜间模式",
                systemImage: isNight ? "sun.max.fill" : "moon.stars.fill"
            )
            .symbolEffect(.bounce, value: appearance)
        }
        .accessibilityIdentifier("appearance-mode-toggle")
        .accessibilityValue(isNight ? "夜间模式已开启" : "日间模式已开启")
        .sensoryFeedback(.selection, trigger: appearance)
    }

    private func toggle() {
        // A spring transaction around preferredColorScheme forces every card,
        // material and navigation surface to interpolate at once. Let the
        // system perform its optimized appearance hand-off instead.
        appearance = isNight ? AppAppearance.light.rawValue : AppAppearance.dark.rawValue
    }
}
