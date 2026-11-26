import SwiftUI
import Testing
import TrainingWatchKit
@testable import TrainingAppKit

#if canImport(AppKit)
@MainActor
@Suite("WatchScreenPreview renders (WATCH-138)")
struct WatchScreenPreviewRenderTests {
    @Test("every standard screen draws, as a planned workout and as a free run, on both watches")
    func rendersEveryStandardScreen() throws {
        for template in StandardScreens.all {
            let screen = RunScreen(id: template.id, items: template.items)
            for isWorkout in [true, false] {
                for watch in PreviewWatch.allCases {
                    let renderer = ImageRenderer(content: WatchScreenPreview(screen: screen, isWorkout: isWorkout, watch: watch))
                    let image = try #require(renderer.nsImage, "\(template.title) didn't render")
                    #expect(image.size.width > 150 && image.size.height > 200, "\(template.title) is too small")
                }
            }
        }
    }
}
#endif
