// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TrainingWatchKit",
    // Shared by the iOS app (which sends) and the watchOS app (which receives). macOS is declared
    // so `swift build`/`swift test` work on the CI runner and locally without a simulator.
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "TrainingWatchKit", targets: ["TrainingWatchKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/Oekalegon/TrainingKit.git", branch: "develop")
    ],
    targets: [
        .target(
            name: "TrainingWatchKit",
            dependencies: [.product(name: "TrainingCore", package: "TrainingKit")]
        ),
        .testTarget(
            name: "TrainingWatchKitTests",
            dependencies: ["TrainingWatchKit"]
        )
    ]
)
