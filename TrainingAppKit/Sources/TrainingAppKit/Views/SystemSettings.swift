import SwiftUI

/// Opening the system Settings app, from the permission banners and the introduction (MVP2-147).
enum SystemSettings {
    /// The URL of this app's page in Settings; `nil` where there is none (macOS).
    static var url: URL? {
        #if os(iOS)
        URL(string: UIApplication.openSettingsURLString)
        #else
        nil
        #endif
    }
}
