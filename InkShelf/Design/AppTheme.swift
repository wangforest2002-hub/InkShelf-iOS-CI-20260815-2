import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.26, green: 0.56, blue: 0.98)
    static let cyan = Color(red: 0.24, green: 0.80, blue: 0.94)
    static let mint = Color(red: 0.30, green: 0.84, blue: 0.68)
    static let lilac = Color(red: 0.69, green: 0.52, blue: 0.98)
    static let coral = Color(red: 1.0, green: 0.48, blue: 0.59)
    static let midnight = Color(red: 0.035, green: 0.025, blue: 0.10)

    static let accentGradient = LinearGradient(
        colors: [cyan, accent, lilac],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct AuroraBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var animate = false

    var body: some View {
        ZStack {
            (colorScheme == .dark ? AppTheme.midnight : Color(red: 0.965, green: 0.985, blue: 1.0))

            Circle()
                .fill(AppTheme.lilac.opacity(colorScheme == .dark ? 0.26 : 0.15))
                .frame(width: 360, height: 360)
                .blur(radius: 80)
                .offset(x: animate ? 130 : -120, y: animate ? -230 : -110)

            Circle()
                .fill(AppTheme.cyan.opacity(colorScheme == .dark ? 0.18 : 0.16))
                .frame(width: 310, height: 310)
                .blur(radius: 95)
                .offset(x: animate ? -150 : 110, y: animate ? 260 : 170)

            Circle()
                .fill(AppTheme.mint.opacity(colorScheme == .dark ? 0.13 : 0.13))
                .frame(width: 220, height: 220)
                .blur(radius: 75)
                .offset(x: animate ? 90 : -90, y: 40)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                animate = true
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
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: configuration.isPressed)
    }
}
