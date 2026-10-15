import SwiftUI

/// The plan strip above a micro-cycle's chart: "Macro › Meso › Micro", the phase and load role, and
/// the plan's edit button (MVP5-107). Shown only for a planned micro-cycle, not a plain calendar week.
struct CycleHeaderView: View {
    let context: CycleContext

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(context.breadcrumb)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Plan editing doesn't exist yet; the button holds its place in the header.
            Button("Edit Plan", systemImage: "pencil") {}
                .labelStyle(.iconOnly)
                .disabled(true)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = ["\(context.phaseTitle) phase"]
        if let role = context.loadRole { parts.append(role.rawValue.capitalized) }
        parts.append("\(context.lengthInDays) days")
        return parts.joined(separator: " · ")
    }
}
