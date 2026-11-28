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
        .package(url: "https://github.com/Oekalegon/TrainingKit.git", branch: "develop"),
        .package(path: "../TrainingWatchKit"),
        // The map (MVP4-101): own vector renderer, GPX and routes. Public; a branch like TrainingKit, so a fix in the kit
        // reaches the app at the next resolve.
        .package(url: "https://github.com/Oekalegon/GeoMapKit.git", branch: "develop")
    ],
    targets: [
        .target(
            name: "TrainingAppKit",
            dependencies: [
                .product(name: "TrainingCore", package: "TrainingKit"),
                .product(name: "TrainingHealthKit", package: "TrainingKit"),
                .product(name: "TrainingPersistence", package: "TrainingKit"),
                .product(name: "TrainingWorkoutKit", package: "TrainingKit"),
                .product(name: "TrainingWatchKit", package: "TrainingWatchKit"),
                .product(name: "GeoCore", package: "GeoMapKit"),
                .product(name: "FeatureStore", package: "GeoMapKit"),
                .product(name: "MapStyle", package: "GeoMapKit"),
                .product(name: "MapBuilder", package: "GeoMapKit"),
                .product(name: "MapRender", package: "GeoMapKit"),
                .product(name: "Regions", package: "GeoMapKit"),
                .product(name: "MapUI", package: "GeoMapKit"),
                .product(name: "Tracks", package: "GeoMapKit"),
                .product(name: "TrackOverlays", package: "GeoMapKit")
            ]
        ),
        .testTarget(
            name: "TrainingAppKitTests",
            dependencies: [
                "TrainingAppKit",
                .product(name: "GeoCore", package: "GeoMapKit"),
                .product(name: "FeatureStore", package: "GeoMapKit"),
                .product(name: "Tracks", package: "GeoMapKit")
            ]
        )
    ]
)
