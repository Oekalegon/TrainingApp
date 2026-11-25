import SwiftUI
import TrainingWatchKit

/// The temporary warning screen of a low battery (WATCH-110): the whole screen in the battery's status
/// colour (yellow, orange or red, as the bar) with the words on it. It stays until the athlete
/// dismisses it by tapping the screen or turning the Digital Crown (WATCH-121). (The Action button is
/// WATCH-120.) The screen takes the crown itself, so a turn dismisses the warning and doesn't also
/// switch the data screen underneath.
struct BatteryWarningScreen: View {
    let warning: BatteryWarning
    let onDismiss: () -> Void
    /// When the screen appeared: a tap in its first moment is not an answer to it, but the athlete's last
    /// tap, meant for what was on screen, so it doesn't dismiss the warning.
    @State private var shownAt = Date.now
    /// True with the wrist down (WATCH-129): the colours are reversed, the warning's colour on black, so
    /// the screen isn't a field of lit pixels while the warning waits to be tapped.
    @Environment(\.isLuminanceReduced) private var dimmed
    /// The crown's position; any change is a turn. The range is wide and continuous, so a long turn
    /// never reaches an end where it would stop reporting.
    @State private var crown = 0.0
    @FocusState private var hasCrown: Bool

    /// How long after it appears the screen ignores taps, in seconds.
    private static let grace = 1.0

    private func dismiss() {
        guard Date.now.timeIntervalSince(shownAt) >= Self.grace else { return }
        onDismiss()
    }

    var body: some View {
        ZStack {
            (dimmed ? Color.black : warning.color).ignoresSafeArea()
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
                Text("Tap or turn the crown to dismiss").font(.system(size: 11)).opacity(0.7)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(dimmed ? warning.color : warning.textColor)
            .padding(.horizontal, 12)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        // Focus is what sends the crown to this view. A turn in the first moment is the athlete's last
        // turn, meant for the screen before, so it is ignored like a tap (see `dismiss()`).
        .focusable()
        .focused($hasCrown)
        .digitalCrownRotation(
            $crown, from: -10_000, through: 10_000, sensitivity: .medium, isContinuous: true,
            isHapticFeedbackEnabled: false)
        .onChange(of: crown) { dismiss() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(warning.spoken)
        .accessibilityHint("Double tap, or turn the Digital Crown, to dismiss")
        .accessibilityAddTraits([.isButton, .isModal])
        .onAppear {
            shownAt = .now
            hasCrown = true
            AccessibilityNotification.Announcement(warning.spoken).post()
        }
    }
}
