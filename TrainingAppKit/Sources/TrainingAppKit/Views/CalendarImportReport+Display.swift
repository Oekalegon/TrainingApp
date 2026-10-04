import TrainingCore

extension CalendarImportReport.RejectionReason {
    /// The explanation shown next to a rejected entry in the Import Calendar sheet, same reasoning
    /// as `Sport+Display.swift`: `TrainingCore` has no opinion on display strings.
    var explanation: String {
        switch self {
        case .noSteps: "No steps (the file predates steps)"
        case .invalidStep: "A step couldn't be read"
        case .invalidDate: "The date isn't valid"
        }
    }
}
