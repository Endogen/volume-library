import Foundation

public struct BackendInfo: Equatable, Sendable {
    public let version: String
    public let flavor: String
}

public enum IntegrationError: Error, LocalizedError, Equatable {
    case missingApp, wrongBuild, missingLibrary, untrustedApp, unsupportedVersion
    case authorization, credentials, busy, operationFailed

    public var errorDescription: String? {
        switch self {
        case .missingApp: "VeraCrypt isn’t installed. Install the FUSE-T version, or locate your copy."
        case .wrongBuild: "FUSE-T is installed, but this VeraCrypt build needs macFUSE. Install the FUSE-T version of VeraCrypt."
        case .missingLibrary: "VeraCrypt can’t load its filesystem library. Check that VeraCrypt and FUSE-T are installed as a matching pair."
        case .untrustedApp: "This copy of VeraCrypt could not be verified. Choose an official signed VeraCrypt app."
        case .unsupportedVersion: "This release has been tested with VeraCrypt 1.26.31. Choose that version to continue."
        case .authorization: "VeraCrypt needs administrator authorization. Open VeraCrypt to authorize this operation, then refresh here."
        case .credentials: "Couldn’t unlock this volume. Check the password. This release supports default PIM and no keyfiles."
        case .busy: "This volume is in use. Close files using it, then try ejecting again."
        case .operationFailed: "VeraCrypt couldn’t complete this operation. Refresh its status or open VeraCrypt for more details."
        }
    }
}

public protocol VolumeBackend: Sendable {
    func probe() async throws -> BackendInfo
    func list() async throws -> [Mount]
    func mount(path: String, password: String, readOnly: Bool) async throws
    func unmount(path: String) async throws
}

public struct VeraCryptBackend: VolumeBackend {
    public let appURL: URL
    private let runner = ProcessRunner()
    public init(appURL: URL) { self.appURL = appURL }
    private var executable: URL { appURL.appendingPathComponent("Contents/MacOS/VeraCrypt") }

    private func verifySignature() async throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw IntegrationError.missingApp }
        let signature = try await runner.run(URL(fileURLWithPath: "/usr/bin/codesign"), arguments: [
            "--verify", "--deep", "--strict", "-R=identifier \"org.idrix.VeraCrypt\" and anchor apple generic and certificate leaf[subject.OU] = \"HLTN5GLG99\"", appURL.path
        ])
        guard signature.code == 0 else { throw IntegrationError.untrustedApp }
    }

    public func probe() async throws -> BackendInfo {
        try await verifySignature()
        let result = try await runner.run(executable, arguments: ["--text", "--version"])
        if result.combined.contains("Library not loaded") {
            if result.combined.contains("libfuse.2.dylib"),
               FileManager.default.fileExists(atPath: "/usr/local/lib/libfuse-t.dylib") {
                throw IntegrationError.wrongBuild
            }
            throw IntegrationError.missingLibrary
        }
        guard result.code == 0 else { throw IntegrationError.operationFailed }
        guard result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "VeraCrypt 1.26.31" else {
            throw IntegrationError.unsupportedVersion
        }
        let linkage = try await runner.run(URL(fileURLWithPath: "/usr/bin/otool"), arguments: ["-L", executable.path])
        let flavor = linkage.output.contains("libfuse-t") ? "FUSE-T" : "macFUSE"
        return BackendInfo(version: "1.26.31", flavor: flavor)
    }

    public func list() async throws -> [Mount] {
        try await verifySignature()
        let result = try await runner.run(executable, arguments: ["--text", "--non-interactive", "--list", "--verbose"])
        return try BackendContract.parseMounts(result.combined, exitCode: result.code)
    }

    public func mount(path: String, password: String, readOnly: Bool) async throws {
        let arguments = try BackendContract.mountArguments(path: path, readOnly: readOnly)
        let input = try BackendContract.passwordInput(password)
        let result = try await runner.run(executable, arguments: arguments, input: input, timeout: 120)
        try check(result)
    }

    public func unmount(path: String) async throws {
        try BackendContract.validatePath(path)
        let result = try await runner.run(executable, arguments: ["--text", "--non-interactive", "--unmount", path], timeout: 30)
        try check(result)
    }

    private func check(_ result: CommandResult) throws {
        guard result.code != 0 else { return }
        let message = result.combined.lowercased()
        if message.contains("incorrect") && message.contains("password") { throw IntegrationError.credentials }
        if message.contains("administrator") || message.contains("sudo") { throw IntegrationError.authorization }
        if message.contains("busy") || message.contains("in use") { throw IntegrationError.busy }
        throw IntegrationError.operationFailed
    }
}

public actor DemoBackend: VolumeBackend {
    private var mounts = [Mount(slot: 1, container: "/Demo/Personal.hc", mountPoint: "/Volumes/Personal")]
    public init() {}
    public func probe() async throws -> BackendInfo { BackendInfo(version: "Demo", flavor: "Simulated volumes") }
    public func list() async throws -> [Mount] { mounts }
    public func mount(path: String, password: String, readOnly: Bool) async throws {
        _ = try BackendContract.passwordInput(password)
        try await Task.sleep(for: .milliseconds(650))
        if password == "wrong" { throw IntegrationError.credentials }
        guard !mounts.contains(where: { $0.container == path }) else { return }
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        mounts.append(Mount(slot: (mounts.map(\.slot).max() ?? 0) + 1, container: path, mountPoint: "/Volumes/" + name))
    }
    public func unmount(path: String) async throws {
        try await Task.sleep(for: .milliseconds(350))
        mounts.removeAll { $0.container == path }
    }
}
