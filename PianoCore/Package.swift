// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "PianoCore",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "PianoCore", targets: ["PianoCore"])
    ],
    targets: [
        .target(name: "PianoCore"),
        .testTarget(name: "PianoCoreTests", dependencies: ["PianoCore"]),
        .testTarget(name: "PianoCoreAPITests", dependencies: ["PianoCore"])
    ]
)
