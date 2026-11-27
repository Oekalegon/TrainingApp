import SwiftUI

/// A label whose icon sits at the top, level with the first line of the title, in a fixed-width column so the
/// texts of a list line up. The default style centres the icon on the whole label, which looks off beside a title
/// with a few lines of detail under it. The icon is as tall as that first line. The icon is in the primary colour: the catalogue's rows are not actions.
struct TopAlignedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            configuration.icon
                // As tall as the title's line (the default scale draws a symbol smaller than the text beside it).
                .imageScale(.large)
                .foregroundStyle(.primary)
                .frame(width: 34)
            configuration.title
        }
    }
}
