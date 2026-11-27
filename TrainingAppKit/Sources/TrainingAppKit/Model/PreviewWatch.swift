import CoreGraphics
import Foundation
import TrainingWatchKit

/// Which watch the preview stands for (WATCH-138, WATCH-142): the Ultra, and a smaller watch (41 mm) for the others.
/// Each has its own screen size, so the run screens are laid out at the width and height the watch has: a row that
/// is too wide for the smaller screen shrinks or drops what gives way in the preview as it does on the watch, and the
/// units of height that fit come from the watch's own rule, ``RunScreenPage/fittingUnits(forScreenHeight:)``, so the two
/// can't disagree. A 45 mm watch is 198 × 242 points and fits the 6 units too, so the choice is the Ultra or a watch
/// small enough to lose the first item of a full screen.
enum PreviewWatch: String, CaseIterable, Identifiable {
    case large, small

    var id: String { rawValue }

    var title: String {
        switch self {
        case .large: "Ultra"
        case .small: "Other Watches"
        }
    }

    /// The size of the watch's screen in points: the Ultra's 49 mm is 205 × 251, a 41 mm watch is 176 × 215.
    var screenSize: CGSize {
        switch self {
        case .large: CGSize(width: 205, height: 251)
        case .small: CGSize(width: 176, height: 215)
        }
    }

    /// How many units of height the watch's screen fits, by the rule the watch itself uses.
    var fittingUnits: Int { RunScreenPage.fittingUnits(forScreenHeight: screenSize.height) }

    /// The width of the case around the screen, in points.
    var bezel: Double {
        switch self {
        case .large: 14
        case .small: 8
        }
    }

    /// The corner radius of the case: the Ultra's is squarer and flatter, the others' rounder.
    var caseCornerRadius: Double {
        switch self {
        case .large: 60
        case .small: 56
        }
    }

    /// The corner radius of the screen inside the case.
    var screenCornerRadius: Double {
        switch self {
        case .large: 48
        case .small: 48
        }
    }

    /// Whether the watch has the Action button, on the left of the case.
    var hasActionButton: Bool { self == .large }

    /// Whether the crown has a guard around it, a raised bar the Ultra has and the others don't.
    var hasCrownGuard: Bool { self == .large }
}
