import PhotosUI
import SwiftUI
import TrainingCore

/// Personal Information (MVP2-123, MVP2-132, design doc §2.3): the avatar, name, sex and age, the main
/// sport and usual venue (MVP2-151), and the two zone screens, Heart Rate Zones and Pace Zones. The name can be changed: tapping its row asks
/// for a new one. So can the avatar: tapping it picks a photo, and "Remove Photo" goes back to the
/// initials. The age is shown once a date of birth is on record, which the HealthKit merge fills
/// in (MVP2-124); sex and age come from Health and aren't edited here.
struct PersonalInformationView: View {
    let viewModel: AthleteViewModel
    let microCycleViewModel: MicroCycleViewModel
    @State private var isEditingName = false
    @State private var nameText = ""
    @State private var isShowingError = false
    /// The photo the athlete picked, consumed as soon as it's loaded (MVP2-132).
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isShowingPhotoError = false

    /// The selectable sports, plus the athlete's own when it's another.
    private var mainSports: [Sport] {
        Sport.selectable.contains(viewModel.athlete.mainSport)
            ? Sport.selectable : Sport.selectable + [viewModel.athlete.mainSport]
    }

    /// The sport and venue just chosen, shown at once while they save, so the pickers (and the venue
    /// picker that comes and goes with the sport) don't wait for the profile to reload.
    @State private var mainSport: Sport?
    @State private var mainVenue: Venue?
    /// Counts the changes made, so the shown choice is given up only when the latest save is done.
    @State private var mainSportChangeCount = 0

    private var shownMainSport: Sport { mainSport ?? viewModel.athlete.mainSport }

    private func setMainSport(_ sport: Sport, venue: Venue?) {
        let allowed = venue.flatMap { Venue.choices(for: sport).contains($0) ? $0 : nil }
        mainSport = sport
        mainVenue = allowed
        mainSportChangeCount += 1
        let change = mainSportChangeCount
        Task {
            if await !microCycleViewModel.setAthleteMainSport(sport, venue: venue) { isShowingError = true }
            guard change == mainSportChangeCount else { return }
            mainSport = nil
            mainVenue = nil
        }
    }

    var body: some View {
        List {
            // The avatar is a button: tapping it picks a photo from the library, which is cut to a
            // small square (`AvatarImageProcessor`) and kept on the profile. Without one, the
            // monogram shows (MVP2-132).
            Section {
                VStack(spacing: 8) {
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        AvatarView(initials: viewModel.initials, imageData: viewModel.avatarImageData)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose Photo")
                    Text(viewModel.avatarImageData == nil ? "Tap to choose a photo" : "Tap to change the photo")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if viewModel.avatarImageData != nil {
                        Button("Remove Photo", role: .destructive) {
                            Task {
                                if await !microCycleViewModel.setAthleteAvatar(nil) { isShowingError = true }
                            }
                        }
                        .font(.footnote)
                    }
                }
                .frame(maxWidth: .infinity)
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
                Picker("Main Sport", selection: Binding(
                    get: { mainSport ?? viewModel.athlete.mainSport },
                    set: { sport in setMainSport(sport, venue: mainSport == nil ? viewModel.athlete.mainVenue : mainVenue) }
                )) {
                    ForEach(mainSports, id: \.self) { sport in
                        Text(sport.displayName).tag(sport)
                    }
                }
                if !Venue.choices(for: shownMainSport).isEmpty {
                    Picker("Usual Venue", selection: Binding(
                        get: { mainSport == nil ? viewModel.athlete.mainVenue : mainVenue },
                        set: { venue in setMainSport(shownMainSport, venue: venue) }
                    )) {
                        Text("No Preference").tag(nil as Venue?)
                        ForEach(Venue.choices(for: shownMainSport), id: \.self) { venue in
                            Text(venue.displayName).tag(venue as Venue?)
                        }
                    }
                }
            } footer: {
                Text("New planned workouts start with this venue when the workout allows it.")
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
                    if await !microCycleViewModel.setAthleteName(name) { isShowingError = true }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                pickedPhoto = nil
                guard let data, let avatar = AvatarImageProcessor.processedAvatar(from: data) else {
                    isShowingPhotoError = true
                    return
                }
                if await !microCycleViewModel.setAthleteAvatar(avatar) { isShowingError = true }
            }
        }
        .alert("Couldn't Use That Photo", isPresented: $isShowingPhotoError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That photo couldn't be read. Try another one.")
        }
        .alert("Couldn't Save", isPresented: $isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The change couldn't be saved. Try again.")
        }
    }
}
