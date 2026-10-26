import Foundation
import TrainingCore

/// A plain-language reading of a ``PlanProposal`` for the Create Plan review step (MVP5-146): the
/// layout, what was given up and what the guardrails found. The full preview and commit screen
/// (MVP5-121) is separate.
public struct PlanProposalSummary: Equatable, Sendable {
    /// One phase of the layout.
    public struct Phase: Equatable, Sendable, Identifiable {
        public let name: String
        public let microCount: Int
        public let dates: ClosedRange<Date>
        public var id: Date { dates.lowerBound }
    }

    /// The phases in order, one row per run of the same phase.
    public let phases: [Phase]
    /// The number of micro-cycles in the plan.
    public let microCount: Int
    /// The days in each micro-cycle.
    public let microLengthDays: Int
    /// The number of planned workouts.
    public let workoutCount: Int
    /// The first and last day of the plan.
    public let dates: ClosedRange<Date>?
    /// What was cut or changed to make the plan fit, one line each.
    public let compromises: [String]
    /// Guardrail findings of severity risk, one line each.
    public let risks: [String]
    /// Guardrail findings of severity warning, one line each.
    public let warnings: [String]
    /// The note that triphasic is calibrated to the marathon, when the target race is another distance.
    public let calibrationNote: String?
    /// Whether the guardrails are satisfied.
    public let isAcceptable: Bool

    init(_ proposal: PlanProposal, calendar: Calendar) {
        let cycles = proposal.candidate.cycles
        let micros = cycles.filter { $0.level == .micro }.sorted { $0.dateRange.lowerBound < $1.dateRange.lowerBound }
        var runs: [Phase] = []
        for micro in micros {
            let name = micro.phase.displayName
            if let last = runs.last, last.name == name {
                runs[runs.count - 1] = Phase(name: name, microCount: last.microCount + 1, dates: last.dates.lowerBound...micro.dateRange.upperBound)
            } else {
                runs.append(Phase(name: name, microCount: 1, dates: micro.dateRange))
            }
        }
        phases = runs
        microCount = micros.count
        microLengthDays = micros.first.map { (calendar.dateComponents([.day], from: $0.dateRange.lowerBound, to: $0.dateRange.upperBound).day ?? 0) + 1 } ?? 0
        workoutCount = proposal.candidate.plannedActivities.count
        dates = micros.first.flatMap { first in micros.last.map { first.dateRange.lowerBound...$0.dateRange.upperBound } }
        compromises = proposal.compromises.map(Self.describe)
        func line(_ finding: PlanFinding) -> String {
            let day = finding.day.formatted(.dateTime.day().month(.abbreviated))
            return "\(day): \(finding.rule.displayName)" + (finding.subject.map { " (\($0))" } ?? "")
        }
        risks = proposal.risks.map(line)
        warnings = proposal.warnings.map(line)
        calibrationNote = proposal.calibrationWarning.map {
            "\(proposal.candidate.cycles.first?.name ?? "This paradigm")'s percentages are calibrated to a marathon (\(Self.kilometres($0.calibratedDistanceMeters))), and the target race is \(Self.kilometres($0.raceDistanceMeters)). Paces will be less accurate."
        }
        isAcceptable = proposal.isAcceptable
    }

    private static func kilometres(_ meters: Double) -> String {
        let value = meters / 1000
        return (value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)) + " km"
    }

    private static func describe(_ compromise: PlanCompromise) -> String {
        switch compromise {
        case .leadTime(let leadTime):
            switch leadTime.action {
            case .phaseDropped(let phase): return "\(phase.displayName) phase left out: not enough time before the race."
            case .phaseShortened(let phase, let from, let to): return "\(phase.displayName) phase shortened from \(from) to \(to) micro-cycles."
            case .oldestPhaseTrimmed(let phase, let from, let to): return "\(phase.displayName) phase trimmed from \(from) to \(to) micro-cycles."
            }
        case .unplacedSession(let microStart, let session):
            let kind: String
            switch session.kind {
            case .long: kind = "long run"
            case .hard: kind = "hard session"
            @unknown default: kind = "session"
            }
            return "A \(kind) in the micro-cycle of \(microStart.formatted(.dateTime.day().month(.abbreviated))) found no place (\(describe(session.reason)))."
        case .missingTemplate(let microStart, _):
            return "No workout in the library fits one session in the micro-cycle of \(microStart.formatted(.dateTime.day().month(.abbreviated))); an easy run replaces it."
        case .overriddenPreference(let preference):
            switch preference {
            case .includeConditioning: return "The conditioning phase you asked for was left out."
            case .maxWeeklyVolume: return "Your peak weekly volume was not enough for the plan's sessions, so it was exceeded."
            case .maxLongRun: return "Your longest run limit was exceeded."
            @unknown default: return "A preference was overridden."
            }
        case .adjusted(let adjustment, let rule):
            return "Adjusted for \(rule.displayName.lowercased()): \(describe(adjustment))."
        }
    }

    private static func describe(_ reason: DropReason) -> String {
        switch reason {
        case .noFreeDay: "no free day"
        case .runTypeNotAllowed: "run type not allowed on the free days"
        case .noLongRunSlot: "no day with room for a long run"
        case .spacing: "too close to another hard session"
        case .hardLimit: "too many hard sessions"
        }
    }

    private static func describe(_ adjustment: PlanAdjustment) -> String {
        switch adjustment {
        case .lowerVolume(let start, _): "volume lowered in the micro-cycle of \(start.formatted(.dateTime.day().month(.abbreviated)))"
        case .downWeek(let start): "a recovery micro-cycle at \(start.formatted(.dateTime.day().month(.abbreviated)))"
        case .easeSession(let day): "a session eased on \(day.formatted(.dateTime.day().month(.abbreviated)))"
        case .dropSession(let day): "a session dropped on \(day.formatted(.dateTime.day().month(.abbreviated)))"
        }
    }
}

extension CyclePhase {
    /// The phase's name as shown to the athlete.
    var displayName: String {
        String(describing: self).prefix(1).uppercased() + String(describing: self).dropFirst()
    }
}
