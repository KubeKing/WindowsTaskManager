// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TaskManager",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "TaskManager", targets: ["TaskManager"]), .library(name: "TaskManagerCore", targets: ["TaskManagerCore"])],
    targets: [
        .target(name: "TaskManagerCore"),
        .executableTarget(name: "TaskManager", dependencies: ["TaskManagerCore"]),
        .testTarget(name: "TaskManagerCoreTests", dependencies: ["TaskManagerCore"],
                    swiftSettings: [.unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks", "-load-plugin-library", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"])],
                    linkerSettings: [.unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks", "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"])])
    ],
    swiftLanguageModes: [.v5]
)
