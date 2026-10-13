import Foundation
import TrainingCore

/// What the athlete types into the heart-rate settings sheet (MVP2-132): the date the settings take
/// effect, resting and maximum heart rate, an optional lactate threshold, and the zone method. Checks
/// the values and builds the ``HeartRateZoneSettings`` to record.
struct HeartRateSettingsDraft: Equatable {
    /// The first day the settings apply.
    var effectiveDate: Date
    var restingHeartRate: Int
    var maxHeartRate: Int
    /// `nil` while no lactate threshold is set.
    var lactateThresholdHeartRate: Int?
    var zoneMethod: HeartRateZoneMethod
    /// Whether the lactate threshold in the draft is a placeholder the athlete should confirm, set when
    /// the lactate-threshold zone method is chosen with none on record; see
    /// `AthleteViewModel.zoneMethodDraft(_:asOf:)`.
    var needsLactateThresholdReview = false
    /// Whether the maximum heart rate came from a lab test (MVP2-158); the lab test's date is
    /// ``labTestDate``.
    var maxHeartRateIsLabTest: Bool
    /// Whether the lactate threshold came from a lab test (MVP2-158); only meaningful while
    /// ``lactateThresholdHeartRate`` is set. The lab test's date is ``labTestDate``.
    var lactateThresholdIsLabTest: Bool
    /// The day of the lab test, for whichever of the two values is marked as one. It is a separate date
    /// from ``effectiveDate``: a test done in March can be recorded in May, and the date says how old
    /// the measurement is, which decides whether a fresher field test may replace it.
    var labTestDate: Date
    /// What the draft started from and where it came from, so leaving a value untouched keeps its
    /// source (a workout-measured max stays one) and changing it makes it the athlete's own.
    private let originalMax: Int
    private let originalSource: MaxHeartRateSource
    private let originalLactateThreshold: Int?
    private let originalLactateSource: LactateThresholdSource

    /// Starts from `settings` (the entry in effect on the date, or the current one), or from typical
    /// values when there are none.
    ///
    /// - Parameters:
    ///   - settings: The entry to prefill from, if any.
    ///   - effectiveDate: The date the new entry would take effect.
    init(prefilling settings: HeartRateZoneSettings?, effectiveDate: Date) {
        self.effectiveDate = effectiveDate
        restingHeartRate = Int((settings?.restingHeartRateBPM ?? 55).rounded())
        maxHeartRate = Int((settings?.maxHeartRateBPM ?? 185).rounded())
        lactateThresholdHeartRate = settings?.lactateThresholdHeartRateBPM.map { Int($0.rounded()) }
        zoneMethod = settings?.zoneMethod ?? .karvonen
        originalMax = maxHeartRate
        originalSource = settings?.maxHeartRateSource ?? .manual
        originalLactateThreshold = lactateThresholdHeartRate
        originalLactateSource = settings?.lactateThresholdSource ?? .manual
        var labDate: Date?
        if case .labTest(let measuredOn) = originalSource { labDate = measuredOn }
        if case .labTest(let measuredOn) = originalLactateSource, labDate == nil { labDate = measuredOn }
        maxHeartRateIsLabTest = { if case .labTest = settings?.maxHeartRateSource { true } else { false } }()
        lactateThresholdIsLabTest = lactateThresholdHeartRate != nil
            && { if case .labTest = settings?.lactateThresholdSource { true } else { false } }()
        labTestDate = labDate ?? effectiveDate
    }

    /// Why the values can't be saved, or `nil` when they can.
    var validationMessage: String? {
        guard (25...120).contains(restingHeartRate) else { return "Resting heart rate should be between 25 and 120 bpm." }
        guard (100...230).contains(maxHeartRate) else { return "Maximum heart rate should be between 100 and 230 bpm." }
        guard maxHeartRate >= restingHeartRate + 20 else {
            return "Maximum heart rate should be at least 20 bpm above the resting heart rate."
        }
        if let lactateThresholdHeartRate {
            guard lactateThresholdHeartRate > restingHeartRate, lactateThresholdHeartRate <= maxHeartRate else {
                return "Lactate threshold should be above the resting and no higher than the maximum heart rate."
            }
        } else if zoneMethod == .lactateThreshold {
            return "Enter a lactate threshold heart rate to use this zone method."
        }
        return nil
    }

    /// The settings to record. A value marked as a lab test carries ``labTestDate``
    /// (``MaxHeartRateSource/labTest(measuredOn:)``); one the athlete changed is their own
    /// (`.manual`); one they left alone keeps its source, so saving the sheet for another reason
    /// doesn't turn a workout- or field-test-measured value into a manual one.
    func settings() -> HeartRateZoneSettings {
        let maxSource: MaxHeartRateSource
        if maxHeartRateIsLabTest {
            maxSource = .labTest(measuredOn: labTestDate)
        } else if maxHeartRate == originalMax, !originalSource.isLabTest {
            maxSource = originalSource
        } else {
            maxSource = .manual
        }
        let lactateSource: LactateThresholdSource
        if lactateThresholdHeartRate != nil, lactateThresholdIsLabTest {
            lactateSource = .labTest(measuredOn: labTestDate)
        } else if lactateThresholdHeartRate == originalLactateThreshold, !originalLactateSource.isLabTest {
            lactateSource = originalLactateSource
        } else {
            lactateSource = .manual
        }
        return HeartRateZoneSettings(
            effectiveDate: effectiveDate,
            restingHeartRateBPM: Double(restingHeartRate),
            maxHeartRateBPM: Double(maxHeartRate),
            maxHeartRateSource: maxSource,
            lactateThresholdHeartRateBPM: lactateThresholdHeartRate.map(Double.init),
            lactateThresholdSource: lactateSource,
            zoneMethod: zoneMethod
        )
    }

    /// Whether either value is marked as a lab test, so the sheet shows the date.
    var hasLabTest: Bool { maxHeartRateIsLabTest || (lactateThresholdHeartRate != nil && lactateThresholdIsLabTest) }
}

private extension MaxHeartRateSource {
    var isLabTest: Bool { if case .labTest = self { true } else { false } }
}

private extension LactateThresholdSource {
    var isLabTest: Bool { if case .labTest = self { true } else { false } }
}
