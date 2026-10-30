// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PaplyKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PaplyKit", targets: ["PaplyKit"]),
        .executable(name: "paply-bench", targets: ["paply-bench"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "e15287985625dbf544a343df679436789ffb03fb", traits: ["Diarizer"]),
    ],
    targets: [
        // Objective-C-Ausnahmen (z. B. von AVAudioEngine) abfangen – geht nur in Objective-C
        .target(name: "PaplyObjC"),
        .target(name: "PaplyKit", dependencies: ["PaplyObjC", .product(name: "FluidAudio", package: "FluidAudio")], resources: [.copy("Resources/CAMPlus.mlpackage")]),
        .executableTarget(name: "paply-bench", dependencies: ["PaplyKit"]),
        .testTarget(name: "PaplyKitTests", dependencies: ["PaplyKit"]),
    ]
)
