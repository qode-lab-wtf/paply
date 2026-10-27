// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PaplyKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PaplyKit", targets: ["PaplyKit"]),
        .executable(name: "paply-bench", targets: ["paply-bench"]),
    ],
    targets: [
        .target(name: "PaplyKit"),
        .executableTarget(name: "paply-bench", dependencies: ["PaplyKit"]),
        .testTarget(name: "PaplyKitTests", dependencies: ["PaplyKit"]),
    ]
)
