import PhotosUI
import SwiftUI

/// Personal Information (MVP2-123, MVP2-132, design doc §2.3): the avatar, name, sex and age, and the
/// two zone screens, Heart Rate Zones and Pace Zones. The name can be changed: tapping its row asks
/// for a new one. So can the avatar: tapping it picks a photo, and "Remove Photo" goes back to the
/// initials. The age is shown once a date of birth is on record, which the HealthKit merge fills
/// in (MVP2-124); sex and age come from Health and aren't edited here.
struct PersonalInformationView: View {
    let viewModel: AthleteViewModel
    let weekViewModel: WeekViewModel
    @State private var isEditingName = false
    @State private var nameText = ""
    @State private var isShowingError = false
    /// The photo the athlete picked, consumed as soon as it's loaded (MVP2-132).
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isShowingPhotoError = false

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
                                if await !weekViewModel.setAthleteAvatar(nil) { isShowingError = true }
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
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                pickedPhoto = nil
                guard let data, let avatar = AvatarImageProcessor.processedAvatar(from: data) else {
                    isShowingPhotoError = true
                    return
                }
                if await !weekViewModel.setAthleteAvatar(avatar) { isShowingError = true }
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
