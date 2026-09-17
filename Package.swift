// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ATBCloneSwift", platforms: [.macOS(.v14)],
    products: [.executable(name: "ATBCloneCLI", targets: ["ATBCloneCLI"]), .executable(name: "ATBCloneSwift", targets: ["ATBCloneSwift"]), .library(name: "CloneCore", targets: ["CloneCore"])],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2")],
    targets: [
        .target(name: "CloneCore", dependencies: ["Yams"], resources: [.copy("Resources")]),
        .executableTarget(name: "ATBCloneSwift", dependencies: ["CloneCore"]),
        .executableTarget(name: "ATBCloneCLI", dependencies: ["CloneCore"]),
        .testTarget(name: "CloneCoreTests", dependencies: ["CloneCore"])
    ], swiftLanguageModes: [.v5]
)
