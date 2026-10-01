import Foundation
import TrainingCore

/// Drives the "Export Calendar" sheet (MVP2-100): pick a period, write it as JSON via
/// `TrainingModel.calendarExport(from:through:templates:asOf:)`, then hand the file to the share
/// sheet.
///
/// The file goes to the temporary directory, named after the period. The share sheet copies or
/// sends it from there, so the app never keeps exports around.
@Observable
@MainActor
public final class CalendarExportViewModel {
    /// A quick way to set the period.
    public enum Preset: Hashable, Identifiable, Sendable {
        /// Today through four weeks from today.
        case nextFourWeeks
        /// Twelve weeks ago through today.
        case lastTwelveWeeks
        /// Today through the next primary race (the season plan), if one is planned.
        case untilRace(name: String, date: Date)

        public var id: String {
            switch self {
            case .nextFourWeeks: "nextFourWeeks"
            case .lastTwelveWeeks: "lastTwelveWeeks"
            case .untilRace(let name, let date): "untilRace-\(name)-\(date.timeIntervalSince1970)"
            }
        }

        /// The button title.
        public var title: String {
            switch self {
            case .nextFourWeeks: "Next 4 Weeks"
            case .lastTwelveWeeks: "Last 12 Weeks"
            case .untilRace(let name, _): "Until \(name)"
            }
        }
    }

    /// The first day of the period. Changing it discards a previously written file.
    public var firstDay: Date { didSet { exportedFile = nil } }
    /// The last day of the period, inclusive. Changing it discards a previously written file.
    public var lastDay: Date { didSet { exportedFile = nil } }
    /// The quick periods on offer: the fixed ones, plus "Until <race>" once
    /// ``loadUpcomingRace()`` found a primary race.
    public private(set) var presets: [Preset] = [.nextFourWeeks, .lastTwelveWeeks]
    /// `true` while the export is being built and written.
    public private(set) var isExporting = false
    /// The written JSON file, ready to share, or `nil` before an export (or after the period
    /// changed).
    public private(set) var exportedFile: URL?
    /// Set when building or writing the export failed.
    public private(set) var exportFailed = false

    private let model: TrainingModel
    private let calendar: Calendar
    private let today: Date

    /// Creates the view model with the next four weeks selected.
    ///
    /// - Parameters:
    ///   - model: Supplies the calendar data and the athlete's time zone.
    ///   - today: Anchors the presets and separates actual from expected load.
    public init(model: TrainingModel, today: Date = .now) {
        self.model = model
        self.today = today
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.athlete.timeZone
        self.calendar = calendar
        let start = calendar.startOfDay(for: today)
        self.firstDay = start
        self.lastDay = calendar.date(byAdding: .day, value: 27, to: start) ?? start
    }

    /// Whether the period runs forwards. The Export button is disabled otherwise.
    public var isPeriodValid: Bool {
        calendar.startOfDay(for: firstDay) <= calendar.startOfDay(for: lastDay)
    }

    /// Sets the period to `preset`'s.
    public func apply(_ preset: Preset) {
        let start = calendar.startOfDay(for: today)
        switch preset {
        case .nextFourWeeks:
            firstDay = start
            lastDay = calendar.date(byAdding: .day, value: 27, to: start) ?? start
        case .lastTwelveWeeks:
            firstDay = calendar.date(byAdding: .day, value: -83, to: start) ?? start
            lastDay = start
        case .untilRace(_, let date):
            firstDay = start
            lastDay = calendar.startOfDay(for: date)
        }
    }

    /// Looks up the next primary race (from today on) and, if there is one, offers an
    /// "Until <race>" preset. A failed lookup just leaves that preset out.
    public func loadUpcomingRace() async {
        let start = calendar.startOfDay(for: today)
        let horizon = calendar.date(byAdding: .year, value: 2, to: start) ?? start
        guard let races = try? await model.stores.raceStore.races(in: start...horizon),
              let race = races.filter({ $0.priority == .primary }).min(by: { $0.date < $1.date })
        else { return }
        presets = [.untilRace(name: race.name, date: race.date), .nextFourWeeks, .lastTwelveWeeks]
    }

    /// Builds the export for the period and writes it to a temporary JSON file, setting
    /// ``exportedFile`` on success or ``exportFailed`` on failure.
    ///
    /// If the period changes while the export is being built, the result is dropped rather than
    /// offered for a period the athlete no longer has selected.
    public func export() async {
        guard isPeriodValid, !isExporting else { return }
        isExporting = true
        exportFailed = false
        defer { isExporting = false }
        let (first, last) = (firstDay, lastDay)
        do {
            let export = try await model.calendarExport(from: first, through: last, asOf: today)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Training Calendar \(export.firstDay) to \(export.lastDay)")
                .appendingPathExtension("json")
            try export.jsonData().write(to: url, options: .atomic)
            guard firstDay == first, lastDay == last else { return }
            exportedFile = url
        } catch {
            exportFailed = true
        }
    }
}
