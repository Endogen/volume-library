// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VolumeLibrary",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "VolumeLibrary", targets: ["VolumeLibrary"])],
    targets: [
        .target(name: "VolumeCore"),
        .executableTarget(name: "VolumeLibrary", dependencies: ["VolumeCore"]),
        .testTarget(name: "VolumeCoreTests", dependencies: ["VolumeCore"])
    ],
    swiftLanguageModes: [.v5]
)
