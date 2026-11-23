import SwiftUI
import TrainingWatchKit

/// The temporary warning screen of a low battery (WATCH-110): the whole screen in the battery's status
/// colour (yellow, orange or red, as the bar) with the words on it. It goes by itself after a few
/// seconds, or when it is tapped.
struct BatteryWarningScreen: View {
    let warning: BatteryWarning
    let onDismiss: () -> Void

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
            }
            .foregroundStyle(warning.textColor)
            .padding(.horizontal, 12)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(warning.spoken)
        .accessibilityHint("Double tap to dismiss")
        .accessibilityAddTraits(.isButton)
        .onAppear { AccessibilityNotification.Announcement(warning.spoken).post() }
    }
}
