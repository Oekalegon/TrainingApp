// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TrainingAppKit",
    // App is iOS-only, but macOS is declared too so `swift build`/`swift test` work on the CI
    // runner and locally without an iOS destination.
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "TrainingAppKit", targets: ["TrainingAppKit"])
    ],
    dependencies: [
        // Temporarily the MVP2-35/111 TrainingKit branch; back to `develop` once that PR merges.
        .package(url: "https://github.com/Oekalegon/TrainingKit.git", branch: "claude/vibrant-pascal-tk8z7m")
    ],
    targets: [
        .target(
            name: "TrainingAppKit",
            dependencies: [
                .product(name: "TrainingCore", package: "TrainingKit"),
                .product(name: "TrainingHealthKit", package: "TrainingKit"),
                .product(name: "TrainingPersistence", package: "TrainingKit"),
                .product(name: "TrainingWorkoutKit", package: "TrainingKit")
            ]
        ),
        .testTarget(
            name: "TrainingAppKitTests",
            dependencies: ["TrainingAppKit"]
        )
    ]
)
