import SwiftUI
import TrainingWatchKit

/// The temporary warning screen of a low battery (WATCH-110): the whole screen in the battery's status
/// colour (yellow, orange or red, as the bar) with the words on it. It stays until the athlete
/// dismisses it by tapping the screen. (Dismissing it with the Digital Crown or the Action button is
/// WATCH-121 and WATCH-120.)
struct BatteryWarningScreen: View {
    let warning: BatteryWarning
    let onDismiss: () -> Void
    /// When the screen appeared: a tap in its first moment is not an answer to it, but the athlete's last
    /// tap, meant for what was on screen, so it doesn't dismiss the warning.
    @State private var shownAt = Date.now

    /// How long after it appears the screen ignores taps, in seconds.
    private static let grace = 1.0

    private func dismiss() {
        guard Date.now.timeIntervalSince(shownAt) >= Self.grace else { return }
        onDismiss()
    }

    var body: some View {
        ZStack {
            warning.color.ignoresSafeArea()
            VStack(spacing: 6) {
                Image(systemName: "battery.25percent")
                    .font(.system(size: 30, weight: .semibold))
                    .accessibilityHidden(true)
                Text(warning.title)
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                Text(warning.detail)
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                Text("Tap to dismiss").font(.system(size: 11)).opacity(0.7)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(warning.textColor)
            .padding(.horizontal, 12)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(warning.spoken)
        .accessibilityHint("Double tap to dismiss")
        .accessibilityAddTraits([.isButton, .isModal])
        .onAppear {
            shownAt = .now
            AccessibilityNotification.Announcement(warning.spoken).post()
        }
    }
}
