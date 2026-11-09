// swift-tools-version:5.9
import PackageDescription

/// Núcleo do Driver Intelligence (iOS): leitura da oferta, cálculos e classificação.
/// Swift puro (só Foundation) — testável em macOS e Linux com `swift test`.
let package = Package(
    name: "DriverCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "DriverCore", targets: ["DriverCore"])],
    targets: [
        .target(name: "DriverCore"),
        .testTarget(name: "DriverCoreTests", dependencies: ["DriverCore"]),
    ]
)
