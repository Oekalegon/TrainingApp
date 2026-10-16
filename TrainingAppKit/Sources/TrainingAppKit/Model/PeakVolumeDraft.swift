import Foundation
import TrainingCore

/// How the athlete states a plan's peak weekly volume (MVP5-112, MVP5 design doc §4a and §6.2): as a
/// distance, a time or a TRIMP load, the measure chosen per plan.
enum PeakVolumeMeasure: String, CaseIterable, Identifiable {
    case distance, duration, trimp

    var id: String { rawValue }

    /// The segment title.
    var title: String {
        switch self {
        case .distance: "Distance"
        case .duration: "Time"
        case .trimp: "TRIMP"
        }
    }
}

/// The peak weekly volume field's state: the text being typed, its measure and whether it is a
/// valid volume (MVP5-112).
///
/// The peak is per 7 days, so it means the same for micros of 7, 10 and 14 days; the generator scales it for the micro length.
/// The text is in the athlete's display unit (kilometres or miles, hours, TRIMP points), and ``value``
/// converts it to the base unit the rest of the app holds: meters, seconds, TRIMP. An empty field is
/// valid and means no peak is set, so the generator chooses.
///
/// - Note: TrainingKit has no peak volume type yet (`PlanPreferences` has no `maxWeeklyVolume`, despite MVP5-110), so this
///   only holds and validates the value until it does (see ``value``).
struct PeakVolumeDraft: Equatable {
    /// The state of the text.
    enum Validation: Equatable {
        /// Nothing typed: no peak is set.
        case empty
        /// A usable volume.
        case valid
        /// Not a positive number.
        case invalid
        /// Above what a week can hold; see ``PeakVolumeDraft/maximum``.
        case tooLarge
    }

    var measure: PeakVolumeMeasure
    var text: String
    var distanceSystem: DistanceSystem

    /// - Parameters:
    ///   - measure: The measure, TRIMP by default as in the design doc.
    ///   - text: The initial text.
    ///   - distanceSystem: Whether distances are in kilometres or miles.
    init(measure: PeakVolumeMeasure = .trimp, text: String = "", distanceSystem: DistanceSystem = .deviceDefault) {
        self.measure = measure
        self.text = text
        self.distanceSystem = distanceSystem
    }

    /// The unit written after the field: "km", "mi", "h" or "TRIMP".
    var unitLabel: String {
        switch measure {
        case .distance: distanceSystem == .metric ? "km" : "mi"
        case .duration: "h"
        case .trimp: "TRIMP"
        }
    }

    /// The most a week can hold, in the display unit: 500 km (310 mi), 40 h or 5000 TRIMP. Provisional until
    /// TrainingKit defines the peak volume (MVP5-133).
    var maximum: Double {
        switch measure {
        case .distance: distanceSystem == .metric ? 500 : 310
        case .duration: 40
        case .trimp: 5000
        }
    }

    /// The typed number: a decimal comma is read as a point; `nil` when the text is not a finite number.
    private var number: Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        // Plain decimals only: `Double` would also take hex ("0x10"), exponents ("1e3"), "inf" and "nan".
        guard trimmed.wholeMatch(of: /[0-9]*\.?[0-9]+|[0-9]+\./) != nil, let number = Double(trimmed), number.isFinite else { return nil }
        return number
    }

    /// Whether the text is empty, a usable volume or not.
    var validation: Validation {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return .empty }
        guard let number, number > 0 else { return .invalid }
        return number > maximum ? .tooLarge : .valid
    }

    /// A message for the field when the text is not valid; `nil` when it is valid or empty.
    var message: String? {
        switch validation {
        case .empty, .valid: nil
        case .invalid: "Enter a number above zero."
        case .tooLarge: "That is more than a week can hold. The most is \(Int(maximum)) \(unitLabel)."
        }
    }

    /// The peak in base units (meters, seconds or TRIMP points, by ``measure``); `nil` when the field is empty or invalid.
    var value: Double? {
        guard validation == .valid, let number else { return nil }
        switch measure {
        case .distance: return number * (distanceSystem == .metric ? 1000 : 1609.344)
        case .duration: return number * 3600
        case .trimp: return number
        }
    }

    /// Changes the measure and clears the text, since a number in one measure means nothing in another.
    mutating func setMeasure(_ new: PeakVolumeMeasure) {
        guard new != measure else { return }
        measure = new
        text = ""
    }
}
