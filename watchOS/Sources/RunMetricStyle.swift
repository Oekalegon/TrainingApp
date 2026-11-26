import SwiftUI

extension View {
    /// The simulator can't put the wrist down: with `-fakeDimmed` the view and what is in it see
    /// `isLuminanceReduced` as true (WATCH-125, WATCH-129). Does nothing on a real watch. The run's pages
    /// need it on themselves too, since the pager hands them the system's own value.
    @ViewBuilder
    func fakeDimmable() -> some View {
        #if targetEnvironment(simulator)
        if CommandLine.arguments.contains("-fakeDimmed") {
            environment(\.isLuminanceReduced, true)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
