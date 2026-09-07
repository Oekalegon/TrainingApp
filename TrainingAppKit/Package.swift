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
        .package(url: "https://github.com/Oekalegon/TrainingKit.git", branch: "develop")
    ],
    targets: [
        .target(
            name: "TrainingAppKit",
            dependencies: [
                .product(name: "TrainingCore", package: "TrainingKit"),
                .product(name: "TrainingHealthKit", package: "TrainingKit"),
                .product(name: "TrainingPersistence", package: "TrainingKit")
            ]
        ),
        .testTarget(
            name: "TrainingAppKitTests",
            dependencies: ["TrainingAppKit"]
        )
    ]
)
