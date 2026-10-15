import CloudKit
import Foundation

/// Whether the athlete's iCloud account can sync the app's data (MVP2-147).
public enum ICloudAccountStatus: Equatable, Sendable {
    /// Signed in and allowed to use iCloud: plans, templates, races and goals sync.
    case available
    /// Not signed in to iCloud.
    case noAccount
    /// iCloud is restricted on this device (parental controls or a management profile).
    case restricted
    /// Not known yet, or iCloud can't say right now (a temporary failure, or no network).
    case unknown
}

/// Looks up the iCloud account status.
///
/// A seam, like ``ActivityRefreshing``, so the view models are tested without CloudKit.
@MainActor
public protocol ICloudAccountChecking {
    /// The account's current status. Never throws: an error is ``ICloudAccountStatus/unknown``, so a
    /// momentary failure doesn't warn the athlete about something that may be fine.
    func accountStatus() async -> ICloudAccountStatus
}

/// ``ICloudAccountChecking`` on a real CloudKit container.
public struct CloudKitAccountChecker: ICloudAccountChecking {
    private let containerIdentifier: String

    /// - Parameter containerIdentifier: The app's CloudKit container, as in its iCloud entitlement.
    public init(containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
    }

    public func accountStatus() async -> ICloudAccountStatus {
        do {
            switch try await CKContainer(identifier: containerIdentifier).accountStatus() {
            case .available: return .available
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            case .couldNotDetermine, .temporarilyUnavailable: return .unknown
            @unknown default: return .unknown
            }
        } catch {
            return .unknown
        }
    }
}
