import SwiftUI

/// A dismissible banner at the bottom of the week view about a permission or an account the app needs
/// (MVP2-117, MVP2-147): an icon, a title, a sentence, a text button for the main action and a close
/// button.
///
/// Yellow with black content in both light and dark mode, so it stands out from the grey week
/// background behind it. ``WatchPermissionBanner``, ``HealthConnectBanner`` and
/// ``ICloudUnavailableBanner`` are this with their own words.
struct PermissionBanner: View {
    let symbolName: String
    let title: String
    let message: String
    /// The main action's label, e.g. "Open Watch Settings".
    let actionTitle: String
    let onAction: () -> Void
    /// The close button's accessibility label, e.g. "Dismiss Watch Permission Notice".
    let dismissLabel: LocalizedStringKey
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.black.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                // A 44 pt tall hit area: the banner's main action, in small text.
                Button(actionTitle, action: onAction)
                    .font(.footnote.weight(.semibold))
                    .underline()
                    .buttonStyle(.plain)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            Spacer(minLength: 0)
            // A 44 pt hit area around the small glyph, pulled into the banner's padding so the
            // banner doesn't grow to fit it.
            Button(dismissLabel, systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.black.opacity(0.6))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .padding(.top, -12)
                .padding(.trailing, -12)
        }
        .foregroundStyle(.black)
        .padding()
        .background(.yellow, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
