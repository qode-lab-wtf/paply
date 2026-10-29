// swift-tools-version: 6.2
import PackageDescription
import Foundation
let package = Package(name: "FluidBench", platforms: [.macOS(.v14)], dependencies: [
    .package(path: NSHomeDirectory() + "/paply-gsp-bench/FluidAudio", traits: [.trait(name: "Diarizer")])
], targets: [.executableTarget(name: "FluidBench", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")])])
