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
        // Objective-C-Ausnahmen (z. B. von AVAudioEngine) abfangen – geht nur in Objective-C
        .target(name: "PaplyObjC"),
        .target(name: "PaplyKit", dependencies: ["PaplyObjC"]),
        .executableTarget(name: "paply-bench", dependencies: ["PaplyKit"]),
        .testTarget(name: "PaplyKitTests", dependencies: ["PaplyKit"]),
    ]
)
