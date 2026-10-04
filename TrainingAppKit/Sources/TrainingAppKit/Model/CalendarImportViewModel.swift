import Foundation
import TrainingCore

/// Drives the week view's "Import Calendar" sheet (MVP2-103): read a Training Calendar JSON file
/// written by Export Calendar, show what importing it would do, then import it.
///
/// Nothing is saved until ``performImport()``. ``load(from:)`` only reads the file and previews the
/// import, so the athlete can see how many plans would be added, how many are already in the
/// calendar, and which entries can't be imported before confirming.
@Observable
@MainActor
public final class CalendarImportViewModel {
    /// Where the sheet is in the flow.
    public enum State: Equatable {
        /// No file chosen yet.
        case idle
        /// Reading the file and previewing the import.
        case loading
        /// A file was read; this is what importing it would do.
        case preview(fileName: String, report: CalendarImportReport)
        /// The import is being saved.
        case importing
        /// The import finished with this result.
        case imported(CalendarImportReport)
        /// Reading or importing failed; the message is for the athlete.
        case failed(String)
    }

    /// The current step.
    public private(set) var state: State = .idle
    /// Set when ``performImport()`` failed. The preview stays, so the athlete can try again without
    /// choosing the file again; cleared by the next attempt or file.
    public private(set) var importError: String?

    private let model: TrainingModel
    /// Called after an import succeeds, so the Watch sync puts imported plans that are due soon on
    /// the Watch (MVP2-55).
    @ObservationIgnored
    public var onPlansChanged: (@MainActor () -> Void)?
    private let today: Date
    /// The file read by ``load(from:)``, kept so the import saves exactly what was previewed.
    private var export: CalendarExport?

    /// Creates the view model.
    ///
    /// - Parameters:
    ///   - model: The model the plans are imported into.
    ///   - today: Plans before this day are skipped, as in the export.
    public init(model: TrainingModel, today: Date = .now) {
        self.model = model
        self.today = today
    }

    /// Whether the confirm button is enabled: a file is previewed and would add at least one plan.
    public var canImport: Bool {
        if case .preview(_, let report) = state { return report.added > 0 }
        return false
    }

    /// Reads the file at `url` and previews importing it, setting ``state`` to
    /// ``State/preview(fileName:report:)`` or ``State/failed(_:)``.
    ///
    /// A new file replaces a previous preview. Does nothing while a load or import is running.
    ///
    /// - Parameter url: The file the athlete picked. Security-scoped access, which a file picker's
    ///   URL needs, is requested here and released again.
    public func load(from url: URL) async {
        guard !isBusy else { return }
        state = .loading
        export = nil
        importError = nil
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            // Off the main actor: a season-long export with its steps can be a megabyte or more.
            let export = try await Task.detached { try CalendarExport.decode(from: Data(contentsOf: url)) }.value
            let report = try await model.calendarImportPreview(export, asOf: today)
            self.export = export
            state = .preview(fileName: url.lastPathComponent, report: report)
        } catch let error as CalendarImportError {
            state = .failed(Self.message(for: error))
        } catch {
            state = .failed("The file couldn't be read. Please try again.")
        }
    }

    /// Imports the previewed file, setting ``state`` to ``State/imported(_:)``. On failure the
    /// preview stays and ``importError`` is set. Does nothing unless ``canImport``.
    public func performImport() async {
        guard canImport, let export else { return }
        let preview = state
        importError = nil
        state = .importing
        do {
            state = .imported(try await model.importCalendar(export, asOf: today))
            onPlansChanged?()
        } catch {
            state = preview
            importError = "The calendar couldn't be imported. Please try again."
        }
    }

    /// Returns to choosing a file, e.g. after a failure.
    public func reset() {
        guard !isBusy else { return }
        export = nil
        importError = nil
        state = .idle
    }

    private var isBusy: Bool {
        switch state {
        case .loading, .importing: true
        default: false
        }
    }

    private static func message(for error: CalendarImportError) -> String {
        switch error {
        case .unreadable:
            "This file isn't a Training Calendar export."
        case .unsupportedSchemaVersion:
            "This file was made by a newer version of the app. Update the app to import it."
        }
    }
}
