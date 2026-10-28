// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cell",
    platforms: [.macOS("26.4")],
    products: [.executable(name: "Cell", targets: ["Cell"])],
    targets: [
        .target(name: "CellCore", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "ChargeControl", publicHeadersPath: "include", linkerSettings: [.linkedFramework("Foundation")]),
        .executableTarget(name: "Cell", dependencies: ["CellCore", "ChargeControl"]),
        .executableTarget(name: "CellChecks", dependencies: ["CellCore"], path: "Tests/CellChecks")
    ]
)
