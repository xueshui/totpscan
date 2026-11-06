// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TotpScanSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "TotpScanSDK", targets: ["TotpScanSDK"]),
    ],
    targets: [
        .target(
            name: "TotpScanSDK",
            path: "Sources/TotpScanSDK"
        ),
        .testTarget(
            name: "TotpScanSDKTests",
            dependencies: ["TotpScanSDK"],
            path: "Tests/TotpScanSDKTests"
        ),
    ]
)
