import Foundation
import Testing
@testable import VolumeCore

/// Creates its own uniquely named container. Never accepts a user's volume or credentials.
@Test(.enabled(if: ProcessInfo.processInfo.environment["VOLUME_LIBRARY_LIVE_TEST"] == "1"))
func installedBackendMountsAndEjectsDisposableVolume() async throws {
    let app = URL(fileURLWithPath: "/Applications/VeraCrypt.app")
    let backend = VeraCryptBackend(appURL: app)
    _ = try await backend.probe()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("volume-library-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    let path = directory.appendingPathComponent("Test with spaces.hc").path
    let secret = UUID().uuidString + " 雪"
    let create = try await ProcessRunner().run(app.appendingPathComponent("Contents/MacOS/VeraCrypt"),
        arguments: ["--text", "--non-interactive", "--stdin", "--create", path, "--size=5M",
                    "--volume-type=normal", "--encryption=AES", "--hash=sha-512", "--filesystem=FAT",
                    "--pim=0", "--keyfiles=", "--random-source=/dev/urandom"],
        input: try BackendContract.passwordInput(secret), timeout: 60)
    try #require(create.code == 0)
    do {
        try await backend.mount(path: path, password: secret, readOnly: true)
        let snapshot = try await backend.list()
        let mount = try #require(snapshot.first { $0.container == path })
        let directory = try #require(mount.mountPoint)
        let values = try URL(fileURLWithPath: directory).resourceValues(forKeys: [.volumeIsReadOnlyKey])
        #expect(values.volumeIsReadOnly == true)
        try await backend.unmount(path: path)
        #expect(try await backend.list().allSatisfy { $0.container != path })
        try FileManager.default.removeItem(at: URL(fileURLWithPath: path).deletingLastPathComponent())
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
