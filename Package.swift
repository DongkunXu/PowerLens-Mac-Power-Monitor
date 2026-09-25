// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PowerLens",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PowerLens", targets: ["PowerLens"]),
        .executable(name: "powerlens-cli", targets: ["powerlens-cli"]),
    ],
    targets: [
        // Thin C layer over private / awkward-from-Swift kernel and SMC interfaces.
        .target(
            name: "CProbes",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "PowerLensCore",
            dependencies: ["CProbes"]
        ),
        .target(
            name: "PowerLensUI",
            dependencies: ["PowerLensCore"]
        ),
        .executableTarget(
            name: "PowerLens",
            dependencies: ["PowerLensUI"]
        ),
        // Renders the real panel off-screen to PNG (layout checks without driving the menu bar).
        .executableTarget(
            name: "powerlens-snapshot",
            dependencies: ["PowerLensUI", "PowerLensCore"]
        ),
        .executableTarget(
            name: "powerlens-cli",
            dependencies: ["PowerLensCore"]
        ),
        .testTarget(
            name: "PowerLensCoreTests",
            dependencies: ["PowerLensCore"]
        ),
        .testTarget(
            name: "PowerLensUITests",
            dependencies: ["PowerLensUI"]
        ),
    ]
)
