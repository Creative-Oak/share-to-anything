// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SendKit",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "SendKit", targets: ["SendKit"]),
        .library(name: "SendKitUI", targets: ["SendKitUI"]),
    ],
    targets: [
        .target(name: "SendKit"),
        .target(name: "SendKitUI", dependencies: ["SendKit"]),
        .testTarget(name: "SendKitTests", dependencies: ["SendKit"]),
    ],
    swiftLanguageModes: [.v5]
)
