import SwiftUI
import TrainingWatchKit

/// A run screen as the watch draws it (WATCH-138): the same ``RunScreenPage`` the watch uses, fed with sample values,
/// inside an outline of the watch with its crown and side button, like the simulator's. A screen that has an item
/// only a planned workout can show is empty in a free run, as it is left out there.
struct WatchScreenPreview: View {
    let screen: RunScreen
    let isWorkout: Bool
    let watch: PreviewWatch

    /// The size of the watch's screen in points (a 45 mm watch's), and of the bezel around it.
    private static let screenSize = CGSize(width: 198, height: 242)
    private static let bezel = 9.0

    var body: some View {
        // The crown and the side button stick out on the right; the same room on the left keeps the watch centred.
        HStack(spacing: -3) {
            Color.clear.frame(width: Self.crownWidth - 3, height: 1)
            watchCase
            crown
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the watch screen, with sample values")
    }

    private static let crownWidth = 9.0

    /// The case: a rounded body with the screen in it.
    private var watchCase: some View {
        RoundedRectangle(cornerRadius: 58, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.16)], startPoint: .top, endPoint: .bottom))
            .frame(width: Self.screenSize.width + 2 * Self.bezel, height: Self.screenSize.height + 2 * Self.bezel)
            .overlay {
                screenContent
                    .frame(width: Self.screenSize.width, height: Self.screenSize.height)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 50, style: .continuous))
            }
    }

    /// The crown and the side button on the right of the case.
    private var crown: some View {
        VStack(spacing: 22) {
            RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.3)).frame(width: Self.crownWidth, height: 34)
            RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.25)).frame(width: 6, height: 40)
        }
        .offset(y: -20)
    }

    private var screenContent: some View {
        ZStack(alignment: .topTrailing) {
            if screen.requiresSteps && !isWorkout {
                Text("A free run leaves this screen out. Switch to a planned workout to see it.")
                    .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                RunScreenPage(
                    source: isWorkout ? SampleRuns.workout : SampleRuns.free, screen: screen,
                    fittingUnits: watch.fittingUnits)
            }
            // The system's own clock, which sits at the top right of every watch screen.
            Text("10:09")
                .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                .padding(.top, 9).padding(.trailing, 20)
        }
        .environment(\.colorScheme, .dark)
    }
}
