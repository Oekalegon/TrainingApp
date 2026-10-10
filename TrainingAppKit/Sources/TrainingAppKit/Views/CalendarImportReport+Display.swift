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

extension CalendarImportReport {
    /// One line of the import summary about templates (MVP2-141).
    struct TemplateRow: Equatable {
        /// What the count counts, e.g. "Templates added to your library".
        let title: String
        /// How many.
        let count: Int
    }

    /// The template lines of the preview or result (MVP2-141): only those that aren't zero, so a file
    /// without custom templates shows none. `future` words them for the preview ("will be").
    ///
    /// - Parameter future: `true` for the preview, `false` for the result of an import.
    func templateRows(future: Bool) -> [TemplateRow] {
        [
            TemplateRow(title: future ? "Templates that will be added" : "Templates added", count: templatesAdded),
            TemplateRow(
                title: future ? "Templates that will be added as copies (the id is taken)" : "Templates added as copies (the id is taken)",
                count: templatesCopied
            ),
            TemplateRow(title: "Templates already in your library", count: templatesLinked),
            TemplateRow(title: "Templates that can't be used (workouts keep their steps)", count: templatesRejected),
        ].filter { $0.count > 0 }
    }
}
