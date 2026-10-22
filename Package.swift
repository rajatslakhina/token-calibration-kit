// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TokenCalibrationKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "TokenCalibrationKit", targets: ["TokenCalibrationKit"]),
        .executable(name: "TokenCalibrationDemo", targets: ["TokenCalibrationDemo"])
    ],
    targets: [
        .target(name: "TokenCalibrationKit"),
        .executableTarget(
            name: "TokenCalibrationDemo",
            dependencies: ["TokenCalibrationKit"]
        ),
        .testTarget(
            name: "TokenCalibrationKitTests",
            dependencies: ["TokenCalibrationKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
