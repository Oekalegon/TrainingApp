import Foundation

/// A screen the Athlete tab can push (MVP2-123, design doc §2.3). The tab's `NavigationStack` keeps
/// its path as `[AthleteRoute]`, so `AppTabView` can open a screen from elsewhere, as the week view's
/// Watch permission banner does.
enum AthleteRoute: Hashable {
    case personalInformation
    case heartRateZones
    case paceZones
    case connectedServices
    case appleHealth
    case appleWatch
    case synchronisation
    case calendar
    case developer

    /// The path to the Apple Watch synchronisation settings, where the permission lives: what the
    /// week view's Watch permission banner opens (MVP2-117).
    static let watchSettings: [AthleteRoute] = [.connectedServices, .appleWatch, .synchronisation]

    /// The screen's navigation title, also its row title in the list that opens it.
    var title: String {
        switch self {
        case .personalInformation: "Personal Information"
        case .heartRateZones: "Heart Rate Zones"
        case .paceZones: "Pace Zones"
        case .connectedServices: "Connected Services"
        case .appleHealth: "Apple Health"
        case .appleWatch: "Apple Watch"
        case .synchronisation: "Synchronisation"
        case .calendar: "Calendar"
        case .developer: "Developer"
        }
    }

    /// The row's SF Symbol.
    var systemImage: String {
        switch self {
        case .personalInformation: "person.crop.circle"
        case .heartRateZones: "heart.fill"
        case .paceZones: "figure.run"
        case .connectedServices: "link"
        case .appleHealth: "heart.text.square"
        case .appleWatch: "applewatch"
        case .synchronisation: "arrow.triangle.2.circlepath"
        case .calendar: "calendar"
        case .developer: "wrench.and.screwdriver"
        }
    }
}
