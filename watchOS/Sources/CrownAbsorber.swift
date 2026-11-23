import SwiftUI

/// Takes the Digital Crown's rotation on a page where nothing scrolls, and does nothing with it
/// (WATCH-110). A turn of the crown that no view takes is left to watchOS, which can answer with the
/// grid of apps: the athlete would be taken out of the run. A press of the crown always goes to the
/// watch face, and no app can change that.
///
/// A placeholder: WATCH-109 turns the crown into the switch between data screens, and replaces this.
private struct CrownAbsorber: ViewModifier {
    /// Where the crown is, which nothing reads.
    @State private var position = 0.0
    @FocusState private var hasFocus: Bool

    func body(content: Content) -> some View {
        content
            // The crown only reports a turn to the view that has focus.
            .focusable()
            .focused($hasFocus)
            .digitalCrownRotation(
                $position, from: 0, through: 100, by: 1, sensitivity: .low, isContinuous: true,
                isHapticFeedbackEnabled: false)
            .onAppear { hasFocus = true }
    }
}

extension View {
    /// Takes a turn of the Digital Crown on this page and does nothing with it, so it doesn't leave the app.
    func takesCrownTurns() -> some View {
        modifier(CrownAbsorber())
    }
}
