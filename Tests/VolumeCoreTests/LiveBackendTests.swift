import Foundation
import Testing
@testable import VolumeCore

/// Creates its own uniquely named container. Never accepts a user's volume or credentials.
@Test(.enabled(if: ProcessInfo.processInfo.environment["VOLUME_LIBRARY_LIVE_TEST"] == "1"))
func installedBackendPersistsFileAcrossMounts() async throws {
    let app = URL(fileURLWithPath: "/Applications/VeraCrypt.app")
    let backend = VeraCryptBackend(appURL: app)
    _ = try await backend.probe()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("volume-library-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    let path = directory.appendingPathComponent("Test with spaces.hc").path
    let secret = UUID().uuidString + " 雪"
    // Resolve the mount point again on each mount. VeraCrypt can assign a different directory.
    func mountRoot(readOnly: Bool) async throws -> URL {
        try await backend.mount(path: path, password: secret, readOnly: readOnly)
        let snapshot = try await backend.list()
        let mount = try #require(snapshot.first { $0.container == path })
        let mountPoint = try #require(mount.mountPoint)
        let root = URL(fileURLWithPath: mountPoint, isDirectory: true)
        let values = try root.resourceValues(forKeys: [.isVolumeKey, .volumeIsReadOnlyKey])
        try #require(values.isVolume == true)
        try #require(values.volumeIsReadOnly == readOnly)
        return root
    }

    func ejectAndVerify() async throws {
        try await backend.unmount(path: path)
        let remaining = try await backend.list()
        try #require(remaining.allSatisfy { $0.container != path })
    }

    do {
        let create = try await ProcessRunner().run(app.appendingPathComponent("Contents/MacOS/VeraCrypt"),
            arguments: ["--text", "--non-interactive", "--stdin", "--create", path, "--size=5M",
                        "--volume-type=normal", "--encryption=AES", "--hash=sha-512", "--filesystem=FAT",
                        "--pim=0", "--keyfiles=", "--random-source=/dev/urandom"],
            input: try BackendContract.passwordInput(secret), timeout: 60)
        try #require(create.code == 0)

        let filename = "persistence.txt"
        let contents = Data("Volume Library round trip \(UUID().uuidString)\n".utf8)
        let writableRoot = try await mountRoot(readOnly: false)
        try contents.write(to: writableRoot.appendingPathComponent(filename), options: .withoutOverwriting)
        try await ejectAndVerify()

        let readOnlyRoot = try await mountRoot(readOnly: true)
        let recovered = try Data(contentsOf: readOnlyRoot.appendingPathComponent(filename))
        try #require(recovered == contents)
        try await ejectAndVerify()
        try FileManager.default.removeItem(at: directory)
    } catch {
        if let observations = try? await backend.list() {
            if observations.contains(where: { $0.container == path }) { try? await backend.unmount(path: path) }
            if let after = try? await backend.list(), after.allSatisfy({ $0.container != path }) {
                try? FileManager.default.removeItem(at: directory)
            }
        }
        throw error
    }
}
