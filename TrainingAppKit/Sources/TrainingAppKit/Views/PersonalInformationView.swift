import SwiftUI

/// Personal Information (MVP2-123, design doc §2.3): the avatar, name, sex and age, and the two zone
/// screens, Heart Rate Zones and Pace Zones. The age is shown once a date of birth is on record, which
/// the HealthKit merge fills in (MVP2-124).
struct PersonalInformationView: View {
    let viewModel: AthleteViewModel

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    AvatarView(initials: viewModel.initials)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("Name", value: viewModel.displayName)
                LabeledContent("Sex", value: viewModel.athlete.sex.displayName)
                if let age = viewModel.ageText() {
                    LabeledContent("Age", value: age)
                }
            }

            Section {
                AthleteRouteRow(route: .heartRateZones)
                AthleteRouteRow(route: .paceZones)
            }
        }
        .navigationTitle(AthleteRoute.personalInformation.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
