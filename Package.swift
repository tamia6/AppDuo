// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "AppDuo", platforms: [.macOS(.v14)],
    products: [.executable(name: "AppDuoCLI", targets: ["AppDuoCLI"]), .executable(name: "AppDuo", targets: ["AppDuo"]), .library(name: "CloneCore", targets: ["CloneCore"])],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2")],
    targets: [
        .target(name: "CloneCore", dependencies: ["Yams"], resources: [.copy("Resources")]),
        .executableTarget(name: "AppDuo", dependencies: ["CloneCore"]),
        .executableTarget(name: "AppDuoCLI", dependencies: ["CloneCore"]),
        .testTarget(name: "CloneCoreTests", dependencies: ["CloneCore"])
    ], swiftLanguageModes: [.v5]
)
