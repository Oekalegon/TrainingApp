import Foundation
import TrainingWatchKit

/// Which watch the preview stands for (WATCH-138): the largest watches fit 6 units of height, the others 5, where the
/// first items of a full screen are left out.
enum PreviewWatch: String, CaseIterable, Identifiable {
    case large, small

    var id: String { rawValue }

    var title: String {
        switch self {
        case .large: "Ultra"
        case .small: "Other Watches"
        }
    }

    /// How many units of height the watch's screen fits.
    var fittingUnits: Int {
        switch self {
        case .large: RunScreen.capacity
        case .small: RunScreen.capacity - 1
        }
    }
}
