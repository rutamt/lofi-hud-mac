// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LoFiHUD",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LoFiHUD",
            path: "Sources/LoFiHUD",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("MediaPlayer"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
