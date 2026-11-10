import Foundation
import Darwin

public struct CommandResult: Sendable {
    public let code: Int32
    public let output: String
    public let error: String
    public var combined: String { [output, error].filter { !$0.isEmpty }.joined(separator: "\n") }
}

/// No shell, inherited stdin, or secret logging. Each invocation owns its process and pipes.
public struct ProcessRunner: Sendable {
    public init() {}
    public func run(_ executable: URL, arguments: [String], input: Data? = nil,
                    timeout: TimeInterval = 15) async throws -> CommandResult {
        try await Task.detached {
            try Self.execute(executable, arguments: arguments, input: input, timeout: timeout)
        }.value
    }

    private static func execute(_ executable: URL, arguments: [String], input: Data?,
                                timeout: TimeInterval) throws -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin",
                               "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8",
                               "LC_ALL": "en_US.UTF-8", "LANGUAGE": "en"]
        let out = Pipe(), err = Pipe(), stdin = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = stdin
        try process.run()
        let output = CapturedOutput(), errors = CapturedOutput()
        let readers = DispatchGroup()
        drain(out.fileHandleForReading, into: output, group: readers)
        drain(err.fileHandleForReading, into: errors, group: readers)
        let timeoutState = TimeoutState()
        let deadline = DispatchWorkItem {
            guard process.isRunning else { return }
            timeoutState.mark()
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer { deadline.cancel() }
        // Prevent a child closing stdin early from sending SIGPIPE to the host app.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        if let input { try? stdin.fileHandleForWriting.write(contentsOf: input) }
        try? stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        let drained = readers.wait(timeout: .now() + 3) == .success
        guard !timeoutState.didExpire, drained else { throw BackendError.timedOut }
        guard !output.truncated, !errors.truncated else { throw BackendError.failed }
        return CommandResult(code: process.terminationStatus, output: output.text, error: errors.text)
    }

    private static func drain(_ handle: FileHandle, into output: CapturedOutput, group: DispatchGroup) {
        group.enter()
        DispatchQueue.global().async {
            defer { try? handle.close(); group.leave() }
            while let data = try? handle.read(upToCount: 8192), !data.isEmpty { output.append(data) }
        }
    }
}

private final class CapturedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var overflow = false
    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        let remaining = max(0, 524_288 - data.count)
        data.append(chunk.prefix(remaining))
        overflow = overflow || chunk.count > remaining
    }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
    var truncated: Bool { lock.lock(); defer { lock.unlock() }; return overflow }
}

private final class TimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var expired = false
    func mark() { lock.lock(); expired = true; lock.unlock() }
    var didExpire: Bool { lock.lock(); defer { lock.unlock() }; return expired }
}
