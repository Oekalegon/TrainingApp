import SwiftUI
import TrainingWatchKit

/// The temporary warning screen of a low battery (WATCH-110): the whole screen in the battery's status
/// colour (yellow, orange or red, as the bar) with the words on it. It stays until the athlete
/// dismisses it, by tapping the screen or turning the Digital Crown.
struct BatteryWarningScreen: View {
    let warning: BatteryWarning
    let onDismiss: () -> Void
    /// The Digital Crown's position: any turn of it dismisses the screen.
    @State private var crown = 0.0
    @FocusState private var hasFocus: Bool

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
                Text("Tap or turn the crown to dismiss").font(.system(size: 11)).opacity(0.7)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(warning.textColor)
            .padding(.horizontal, 12)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        // The crown only reports a turn to the view that has focus.
        .focusable()
        .focused($hasFocus)
        .digitalCrownRotation(
            $crown, from: -100, through: 100, by: 0.5, sensitivity: .medium, isContinuous: true,
            isHapticFeedbackEnabled: false)
        .onChange(of: crown) { _, _ in onDismiss() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(warning.spoken)
        .accessibilityHint("Double tap, or turn the Digital Crown, to dismiss")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            hasFocus = true
            AccessibilityNotification.Announcement(warning.spoken).post()
        }
    }
}
