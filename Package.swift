// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VolumeLibrary",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "VolumeLibrary", targets: ["VolumeLibrary"])],
    targets: [
        .target(name: "VolumeCore"),
        .executableTarget(name: "VolumeLibrary", dependencies: ["VolumeCore"]),
        .testTarget(name: "VolumeCoreTests", dependencies: ["VolumeCore"]),
        .testTarget(name: "VolumeLibraryTests", dependencies: ["VolumeLibrary", "VolumeCore"])
    ],
    swiftLanguageModes: [.v5]
)
