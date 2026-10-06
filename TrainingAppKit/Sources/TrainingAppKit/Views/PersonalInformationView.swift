import SwiftUI

/// Personal Information (MVP2-123, MVP2-132, design doc §2.3): the avatar, name, sex and age, and the
/// two zone screens, Heart Rate Zones and Pace Zones. The name can be changed: tapping its row asks
/// for a new one. The age is shown once a date of birth is on record, which the HealthKit merge fills
/// in (MVP2-124); sex and age come from Health and aren't edited here.
struct PersonalInformationView: View {
    let viewModel: AthleteViewModel
    let weekViewModel: WeekViewModel
    @State private var isEditingName = false
    @State private var nameText = ""
    @State private var isShowingError = false

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
                Button {
                    nameText = viewModel.athlete.name
                    isEditingName = true
                } label: {
                    LabeledContent("Name", value: viewModel.displayName)
                }
                .foregroundStyle(.primary)
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
        .alert("Name", isPresented: $isEditingName) {
            TextField("Name", text: $nameText)
            Button("Save") {
                let name = nameText
                Task {
                    if await !weekViewModel.setAthleteName(name) { isShowingError = true }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn't Save", isPresented: $isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The name couldn't be saved. Try again.")
        }
    }
}
