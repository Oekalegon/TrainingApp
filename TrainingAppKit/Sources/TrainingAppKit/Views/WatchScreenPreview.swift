import SwiftUI
import TrainingWatchKit

/// A run screen as the watch draws it (WATCH-138): the same ``RunScreenPage`` the watch uses, fed with sample values,
/// inside an outline of the watch with its crown and side button, like the simulator's. The outline and the screen
/// size follow the watch chosen (WATCH-142): the Ultra's squarer case has a crown guard and the Action button, the
/// other watches' case is rounder and has a smaller screen. A screen that has an item
/// only a planned workout can show is empty in a free run, as it is left out there.
struct WatchScreenPreview: View {
    let screen: RunScreen
    let isWorkout: Bool
    let watch: PreviewWatch
    /// 1 draws the watch at full size, centred in the row; a smaller number draws a thumbnail of that fraction of the
    /// size (WATCH-143), as wide as it is, for a list row.
    var scale: CGFloat = 1

    /// The room kept on each side of the case for what sticks out of it (the crown, its guard, the buttons), so the
    /// watch stays centred.
    private static let sideRoom = 20.0

    /// The size of the whole drawing at full size: the case with the room for what sticks out on both sides.
    private var fullSize: CGSize {
        CGSize(
            width: watch.screenSize.width + 2 * watch.bezel + 2 * Self.sideRoom,
            height: watch.screenSize.height + 2 * watch.bezel)
    }

    var body: some View {
        Group {
            if scale < 1 {
                drawing
                    .fixedSize()
                    .scaleEffect(scale)
                    .frame(width: fullSize.width * scale, height: fullSize.height * scale)
            } else {
                drawing.frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the watch screen, with sample values")
    }

    /// The case with the crown and buttons that stick out of it, each in the room kept at the side.
    private var drawing: some View {
        watchCase
            // Each side is as wide as the room kept for it, and moved out so it starts 1 point inside the case.
            .overlay(alignment: .trailing) {
                rightSide.frame(width: Self.sideRoom, alignment: .leading).offset(x: Self.sideRoom - 1)
            }
            .overlay(alignment: .leading) {
                leftSide.frame(width: Self.sideRoom, alignment: .trailing).offset(x: -(Self.sideRoom - 1))
            }
            .frame(width: fullSize.width, height: fullSize.height)
    }

    /// How far the Ultra's guard stands out of its case, and how tall it is.
    private static let guardWidth = 10.0
    private static let guardHeight = 132.0

    /// The colours of the outline, like the simulator's: a nearly black body with a thin light edge, and a slightly
    /// lighter band round the screen.
    private static let edge = Color(white: 0.42)
    private static let body = Color(white: 0.11)
    private static let band = Color(white: 0.17)
    private static let actionOrange = Color(red: 0.55, green: 0.27, blue: 0.07)

    /// The case: a dark rounded body with a thin light edge, a lighter band round the screen, and the screen in it.
    private var watchCase: some View {
        let width = watch.screenSize.width + 2 * watch.bezel
        let height = watch.screenSize.height + 2 * watch.bezel
        let bandInset = watch.hasCrownGuard ? 8.0 : 4.0
        let guardWidth = watch.hasCrownGuard ? Self.guardWidth : 0
        // The case and its guard are one outline, drawn behind; the guard sticks out to the right of the case's frame.
        let outline = WatchCaseShape(
            cornerRadius: watch.caseCornerRadius, guardWidth: guardWidth,
            guardTop: height / 2 - Self.guardHeight / 2, guardBottom: height / 2 + Self.guardHeight / 2, shoulder: 6)
        return Color.clear
            .frame(width: width, height: height)
            .background(alignment: .leading) {
                ZStack {
                    outline.fill(Self.body)
                    outline.stroke(Self.edge, lineWidth: 1.2)
                }
                .frame(width: width + guardWidth, height: height, alignment: .leading)
            }
            .overlay {
                RoundedRectangle(cornerRadius: watch.caseCornerRadius - bandInset, style: .continuous)
                    .fill(Self.band)
                    .padding(bandInset)
            }
            .frame(width: width, height: height)
            .overlay {
                screenContent
                    .frame(width: watch.screenSize.width, height: watch.screenSize.height)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: watch.screenCornerRadius, style: .continuous))
            }
    }

    /// A part that sticks out of the case, in the same body colour and thin light edge.
    private func part(width: Double, height: Double, radius: Double) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Self.body)
            .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Self.edge, lineWidth: 1.2) }
            .frame(width: width, height: height)
    }

    /// The crown, ridged, and the side button. The Ultra's guard is a bulge of its case, as tall as the crown and
    /// the button together, with the crown standing out of it and the button a tall narrow outline below the crown;
    /// the others' crown stands alone.
    private var rightSide: some View {
        ZStack(alignment: .leading) {
            if watch.hasCrownGuard {
                part(width: 7, height: 58, radius: 3).offset(x: Self.guardWidth + 0.5, y: 22)
                crown(width: 16, height: 47).offset(y: -35)
            } else {
                crown(width: 11, height: 40).offset(y: -30)
                part(width: 7, height: 44, radius: 3).offset(y: 28)
            }
        }
    }

    /// A crown: a dark outline with fine ridges along its outer edge.
    private func crown(width: Double, height: Double) -> some View {
        part(width: width, height: height, radius: min(8, width / 2))
            .overlay(alignment: .trailing) {
                VStack(spacing: 1.5) {
                    ForEach(0..<Int((height - 14) / 2.5), id: \.self) { _ in
                        Rectangle().fill(Color(white: 0.6)).frame(width: 5, height: 1)
                    }
                }
                .padding(.trailing, 1.5)
            }
    }

    /// The Action button, a dark orange strip on the Ultra's left side.
    @ViewBuilder
    private var leftSide: some View {
        if watch.hasActionButton {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(Self.actionOrange).frame(width: 5, height: 73)
                .offset(y: 19)
        }
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
                .padding(.top, watch.hasCrownGuard ? 25 : 9).padding(.trailing, 20)
        }
        .environment(\.colorScheme, .dark)
    }
}
