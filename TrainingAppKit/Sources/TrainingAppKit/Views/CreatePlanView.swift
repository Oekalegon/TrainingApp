import SwiftUI
import TrainingCore

/// The Create Plan wizard (MVP5-146), a sheet opened from the Plans tab's New Plan action. Six steps
/// (start date, races, training approach, availability, peak volume, review) driven by
/// ``CreatePlanViewModel``; Back and Next sit in the bottom bar and the sheet closes only when the draft
/// plan has been stored, handing it to `onCreated`.
struct CreatePlanView: View {
    @State private var viewModel: CreatePlanViewModel
    /// Called with the stored draft just before the sheet closes.
    let onCreated: (TrainingPlan) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newRace: NewRaceSheet?
    @State private var availabilityEditor: RunAvailabilityEditor

    /// A new-race sheet being shown; identifiable so the sheet can be presented by item.
    struct NewRaceSheet: Identifiable {
        let id = UUID()
        let viewModel: RaceSheetViewModel
    }

    init(viewModel: CreatePlanViewModel, onCreated: @escaping (TrainingPlan) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onCreated = onCreated
        _availabilityEditor = State(initialValue: RunAvailabilityEditor(
            saved: { viewModel.preferences.runAvailability },
            save: { viewModel.setAvailability($0); return true }
        ))
    }

    private static var footerPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .bottomBar
        #else
        .automatic
        #endif
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .startDate: StartDateStep(viewModel: viewModel)
                case .races: RacesStep(viewModel: viewModel) { newRace = NewRaceSheet(viewModel: viewModel.newRaceViewModel()) }
                case .paradigm: ParadigmStep(viewModel: viewModel)
                case .preferences: PreferencesStep(viewModel: viewModel, editor: availabilityEditor)
                case .peakVolume: PeakVolumeStep(viewModel: viewModel)
                case .review: ReviewStep(viewModel: viewModel)
                }
            }
            .navigationTitle(viewModel.step.title)
            #if os(iOS)
            .contentMargins(.bottom, 72, for: .scrollContent)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                        .disabled(viewModel.isBusy)
                }
                ToolbarItem(placement: Self.footerPlacement) {
                    Button("Back") { viewModel.back() }
                        .disabled(!viewModel.canGoBack)
                }
                ToolbarItem(placement: .status) {
                    Text("Step \(viewModel.step.rawValue + 1) of \(CreatePlanStep.allCases.count)")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ToolbarItem(placement: Self.footerPlacement) {
                    if viewModel.step == .review {
                        Button("Create Draft") {
                            Task {
                                if let plan = await viewModel.commit() {
                                    onCreated(plan)
                                    dismiss()
                                }
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(viewModel.proposal == nil || viewModel.isBusy || viewModel.problem(in: .review) != nil)
                    } else {
                        Button("Next") { viewModel.next() }
                            .fontWeight(.semibold)
                            .disabled(!viewModel.canAdvance)
                    }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isBusy)
        .task { await viewModel.load() }
        .sheet(item: $newRace, onDismiss: nil) { sheet in
            AddRaceSheet(viewModel: sheet.viewModel)
                .onDisappear { Task { await viewModel.raceWasAdded(sheet.viewModel.lastSavedRace) } }
        }
    }
}

// MARK: - Steps

private struct StartDateStep: View {
    @Bindable var viewModel: CreatePlanViewModel

    var body: some View {
        Form {
            Section {
                DatePicker(
                    "Start date", selection: $viewModel.startDate, in: viewModel.earliestStart..., displayedComponents: .date
                )
                .datePickerStyle(.graphical)
            } footer: {
                Text("The first day of the plan. It runs from here to your target race.")
            }
            ProblemRow(text: viewModel.problem(in: .startDate))
        }
    }
}

private struct RacesStep: View {
    @Bindable var viewModel: CreatePlanViewModel
    let addRace: () -> Void

    var body: some View {
        Form {
            Section {
                if viewModel.upcomingRaces.isEmpty {
                    Text("You have no upcoming races yet. Add the race you are training for.")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.upcomingRaces) { race in
                    RaceRow(viewModel: viewModel, race: race)
                }
                Button("Add a New Race…", systemImage: "plus", action: addRace)
            } header: {
                Text("Upcoming Races")
            } footer: {
                Text("Tick the race the plan builds towards (primary) and any others on the way. A secondary race gets a short taper and recovery, a tertiary one counts as training. A priority chosen here applies to this plan only.")
            }
            if let error = viewModel.loadError { ProblemRow(text: error) }
            ProblemRow(text: viewModel.problem(in: .races))
        }
    }
}

private struct RaceRow: View {
    @Bindable var viewModel: CreatePlanViewModel
    let race: Race
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let isSelected = viewModel.selectedRaceIDs.contains(race.id)
        let state = viewModel.windowState(of: race)
        let isBlocked = !isSelected && (state == .beforeStart || state == .afterTarget)
        VStack(alignment: .leading, spacing: 6) {
            Button { viewModel.toggle(race) } label: {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(race.name).foregroundStyle(.primary)
                        Text("\(race.date.formatted(date: .abbreviated, time: .omitted)) · \(WorkoutBlockCard.distanceText(race.distanceMeters, in: .deviceDefault))")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Label(windowText(state), systemImage: windowSymbol(state))
                            .font(.footnote).foregroundStyle(state == .inWindow ? Color.secondary : Color.orange)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBlocked)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(race.name), \(race.date.formatted(date: .long, time: .omitted)), \(windowText(state))")
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            if isSelected {
                Picker("Priority in this plan", selection: Binding(
                    get: { viewModel.priority(of: race) }, set: { viewModel.setPriority($0, of: race) }
                )) {
                    ForEach(RacePriority.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private func windowText(_ state: RaceWindowState) -> String {
        switch state {
        case .inWindow: "In the plan"
        case .beforeStart: "Before the start date"
        case .afterTarget: "After the target race, not in the plan"
        case .noTarget: "Not in the plan until a primary race is chosen"
        }
    }

    private func windowSymbol(_ state: RaceWindowState) -> String {
        state == .inWindow ? "calendar.badge.checkmark" : "calendar.badge.exclamationmark"
    }
}

private struct ParadigmStep: View {
    @Bindable var viewModel: CreatePlanViewModel

    var body: some View {
        Form {
            Section {
                ForEach(viewModel.paradigms, id: \.name) { paradigm in
                    Button {
                        viewModel.paradigm = paradigm
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(paradigm.name).foregroundStyle(.primary)
                                Text(Self.blurb(for: paradigm)).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.paradigm.name == paradigm.name {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor).accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(viewModel.paradigm.name == paradigm.name ? .isSelected : [])
                }
            } header: {
                Text("Approach")
            }
            if let warning = viewModel.calibrationWarning {
                Section {
                    Label {
                        Text("The \(viewModel.paradigm.name) percentages are calibrated for a marathon (\(WorkoutBlockCard.distanceText(warning.calibratedDistanceMeters, in: .deviceDefault))). Your target race is \(WorkoutBlockCard.distanceText(warning.raceDistanceMeters, in: .deviceDefault)), so the paces will be less accurate.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Warning. The approach is calibrated for a marathon, your race is a different distance.")
                }
            }
            Section {
                Picker("Micro-cycle length", selection: $viewModel.microLength) {
                    ForEach(CreatePlanViewModel.microLengths, id: \.self) { Text("\($0) days").tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Micro-cycle")
            } footer: {
                Text("The length of one training cycle, usually a week. The triphasic structural and specific phases are 6 weeks, so 10-day micro-cycles round them to 4.")
            }
        }
    }

    static func blurb(for paradigm: TrainingParadigm) -> String {
        if paradigm.phases.contains(.structural) {
            "Triphasic (Run Elite): base, structural and specific phases with sprints and race-pace work."
        } else {
            "About 80% easy and 20% hard running, in base, build, peak and taper phases."
        }
    }
}

private struct PreferencesStep: View {
    @Bindable var viewModel: CreatePlanViewModel
    let editor: RunAvailabilityEditor

    var body: some View {
        Form {
            Section {
                ForEach(viewModel.weekdays, id: \.self) { weekday in
                    NavigationLink {
                        RunAvailabilityDayView(editor: editor, weekday: weekday)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(weekday.displayName)
                            Text(editor.shown.summary(on: weekday)).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                if viewModel.hasAvailabilityOverride {
                    Button("Use My Athlete Settings Again", systemImage: "arrow.uturn.backward") { viewModel.resetAvailability() }
                }
            } header: {
                Text("Running Availability")
            } footer: {
                Text(viewModel.hasAvailabilityOverride
                    ? "Changed for this plan only. Your Athlete settings are not touched."
                    : "Taken from your Athlete settings. Changes here apply to this plan only.")
            }
            if viewModel.offersConditioning {
                Section {
                    Toggle("Start with a conditioning phase", isOn: $viewModel.preferences.includeConditioning)
                } footer: {
                    Text("For returning from illness or injury: easy running only, ramping up gently before base. It is left out when there isn't time for it.")
                }
            }
            ProblemRow(text: viewModel.problem(in: .preferences))
        }
    }
}

private struct PeakVolumeStep: View {
    @Bindable var viewModel: CreatePlanViewModel

    var body: some View {
        Form {
            PeakVolumeSection(draft: $viewModel.peak)
            if let note = viewModel.peakVolumeNote {
                Section { Label(note, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }
}

private struct ReviewStep: View {
    @Bindable var viewModel: CreatePlanViewModel

    var body: some View {
        Form {
            Section {
                TextField(viewModel.reviewName.isEmpty ? "Name" : viewModel.reviewName, text: $viewModel.name)
                    .accessibilityLabel("Plan name")
            } header: {
                Text("Name")
            }
            Section("Your Choices") {
                LabeledContent("Starts", value: viewModel.startDate.formatted(date: .abbreviated, time: .omitted))
                if let target = viewModel.targetRace {
                    LabeledContent("Target race", value: "\(target.name), \(target.date.formatted(date: .abbreviated, time: .omitted))")
                }
                let others = viewModel.includedRaces.filter { $0.id != viewModel.targetRace?.id }
                if !others.isEmpty {
                    LabeledContent("Other races", value: others.map(\.name).joined(separator: ", "))
                }
                LabeledContent("Approach", value: viewModel.paradigm.name)
                LabeledContent("Micro-cycle", value: "\(viewModel.microLength) days")
            }
            Section {
                Button {
                    Task { await viewModel.generate() }
                } label: {
                    HStack {
                        Text(viewModel.proposal == nil ? "Generate Plan" : "Generate Again")
                        if viewModel.isGenerating { Spacer(); ProgressView() }
                    }
                }
                .disabled(viewModel.isBusy || !viewModel.isReadyToGenerate)
                if let failure = viewModel.failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline).foregroundStyle(.red)
                        .accessibilityLabel("Error. \(failure)")
                }
            } footer: {
                Text("The plan is saved as a draft in the Plans tab. Nothing changes in your calendar until you activate it.")
            }
            if let summary = viewModel.summary { SummarySections(summary: summary) }
            ProblemRow(text: viewModel.problem(in: .review))
        }
    }
}

private struct SummarySections: View {
    let summary: PlanProposalSummary

    var body: some View {
        Section("Layout") {
            if let dates = summary.dates {
                LabeledContent("Runs", value: "\(dates.lowerBound.formatted(date: .abbreviated, time: .omitted)) to \(dates.upperBound.formatted(date: .abbreviated, time: .omitted))")
            }
            LabeledContent("Micro-cycles", value: "\(summary.microCount) × \(summary.microLengthDays) days")
            LabeledContent("Planned workouts", value: "\(summary.workoutCount)")
            ForEach(summary.phases) { phase in
                LabeledContent(phase.name, value: "\(phase.microCount) micro-cycle\(phase.microCount == 1 ? "" : "s")")
            }
        }
        if let note = summary.calibrationNote {
            Section { Label(note, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.orange) }
        }
        if !summary.compromises.isEmpty {
            Section("Compromises") {
                ForEach(summary.compromises, id: \.self) { Text($0).font(.subheadline) }
            }
        }
        if !summary.risks.isEmpty {
            Section("Risks") {
                ForEach(summary.risks, id: \.self) { Label($0, systemImage: "exclamationmark.octagon.fill").font(.subheadline).foregroundStyle(.red) }
            }
        }
        if !summary.warnings.isEmpty {
            Section("Warnings") {
                ForEach(summary.warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(.orange) }
            }
        }
        if summary.compromises.isEmpty, summary.risks.isEmpty, summary.warnings.isEmpty {
            Section { Label("The guardrails found nothing to flag.", systemImage: "checkmark.circle").font(.subheadline) }
        }
    }
}

/// A step's problem as a red row; nothing when there is none.
private struct ProblemRow: View {
    let text: String?

    var body: some View {
        if let text {
            Section {
                Label(text, systemImage: "exclamationmark.circle")
                    .font(.subheadline).foregroundStyle(.red)
                    .accessibilityLabel("Needs attention. \(text)")
            }
        }
    }
}
