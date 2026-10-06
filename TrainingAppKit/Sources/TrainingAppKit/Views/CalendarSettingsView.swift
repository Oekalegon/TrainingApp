import SwiftUI

/// Calendar (MVP2-123, design doc §2.3): the week's first day and the time zone, which confirm the app
/// buckets days and weeks the way the athlete expects.
struct CalendarSettingsView: View {
    let viewModel: AthleteViewModel

    var body: some View {
        List {
            Section {
                LabeledContent("Week Starts On", value: viewModel.athlete.weekStartsOn.displayName)
                LabeledContent("Time Zone", value: viewModel.athlete.timeZone.identifier)
            }
        }
        .navigationTitle(AthleteRoute.calendar.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
