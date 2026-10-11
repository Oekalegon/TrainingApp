import SwiftUI

/// The first-run introduction (MVP2-147, design doc §2.1a): what the app reads from Health and what
/// iCloud is used for, each with its own button, and "Continue" at the bottom, which leaves it
/// whether or not anything was connected. Nothing is required: skipping Health leaves the empty
/// state, and no iCloud account leaves a warning banner.
///
/// Shown once, as a full-screen cover over the tabs (see ``AppTabView``), and not to anyone who has
/// already connected Health.
struct OnboardingView: View {
    let viewModel: OnboardingViewModel
    let isConnecting: Bool
    let onConnectHealth: () async -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to TrainingApp")
                        .font(.largeTitle.bold())
                    Text("Two things make it work best. You can do either now or later.")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 32)

                stepCard(
                    symbolName: "heart.text.square",
                    title: "Apple Health",
                    text: "TrainingApp reads your workouts, heart rate, resting heart rate, sex and date of birth to work out your training load and fitness. It never writes to Health, and your workouts never leave this device.",
                    status: healthStatus
                ) {
                    if !viewModel.isHealthConnected {
                        Button {
                            Task { await viewModel.connectHealth(onConnectHealth) }
                        } label: {
                            HStack {
                                Text(viewModel.hasAskedForHealth ? "Try Again" : "Connect Apple Health")
                                if isConnecting || viewModel.isConnecting {
                                    ProgressView().accessibilityLabel("Connecting")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isConnecting || viewModel.isConnecting)
                    }
                }

                stepCard(
                    symbolName: "icloud",
                    title: "iCloud",
                    text: "Your plans, workout templates, races and goals sync between your devices through iCloud.",
                    status: iCloudStatus
                ) {
                    if viewModel.isICloudUnavailable {
                        Button("Open Settings", action: onOpenSettings)
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                    }
                }

                Button {
                    viewModel.finish()
                } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .task { await viewModel.refreshICloudStatus() }
    }

    /// What the Health step has to say, in words that don't claim more than can be known: HealthKit
    /// doesn't say whether access was granted, only that an import completed.
    private var healthStatus: String? {
        if viewModel.isHealthConnected { return "Connected" }
        if viewModel.hasAskedForHealth {
            return "Nothing was imported. If you didn't allow access, you can turn it on in Settings ▸ Health ▸ Data Access & Devices."
        }
        return nil
    }

    private var iCloudStatus: String? {
        switch viewModel.iCloudStatus {
        case .available: "Signed in"
        case .noAccount: "Not signed in. Everything still works; your data stays on this device."
        case .restricted: "Restricted on this device. Everything still works; your data stays on this device."
        case .unknown: nil
        }
    }

    private func stepCard<Actions: View>(
        symbolName: String, title: String, text: String, status: String?,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbolName)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let status {
                Text(status)
                    .font(.subheadline.weight(.semibold))
            }
            actions()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// Presents the first-run introduction over the app: a full-screen cover on iOS, a sheet elsewhere.
/// It can't be swiped away, so leaving it is always "Continue" (which records that it was seen).
struct OnboardingPresentation<Content: View>: ViewModifier {
    let isPresented: Bool
    @ViewBuilder let content: () -> Content

    func body(content base: Self.Content) -> some View {
        #if os(iOS)
        base.fullScreenCover(isPresented: .constant(isPresented), content: content)
        #else
        base.sheet(isPresented: .constant(isPresented), content: content).interactiveDismissDisabled()
        #endif
    }
}
