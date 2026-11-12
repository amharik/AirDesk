// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirDeskCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AirDeskCore", targets: ["AirDeskCore"])
    ],
    targets: [
        .binaryTarget(
            name: "airdesk_ffiFFI",
            path: "Artifacts/airdesk_ffiFFI.xcframework"
        ),
        .target(
            name: "AirDeskCore",
            dependencies: ["airdesk_ffiFFI"],
            path: "Sources/AirDeskCore"
        )
    ]
)
