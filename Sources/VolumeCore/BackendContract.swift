import Foundation

public struct Mount: Equatable, Sendable {
    public let slot: Int
    public let container: String
    public let mountPoint: String?
    public init(slot: Int, container: String, mountPoint: String?) {
        self.slot = slot
        self.container = container
        self.mountPoint = mountPoint
    }
}

public enum BackendError: Error, Equatable {
    case invalidPassword, invalidPath, malformedSnapshot, failed, timedOut
}

public enum BackendContract {
    public static func passwordInput(_ password: String) throws -> Data {
        guard !password.isEmpty, password.utf8.count <= 128,
              !password.utf8.contains(where: { $0 == 10 || $0 == 13 || $0 == 0 })
        else { throw BackendError.invalidPassword }
        return Data((password + "\n").utf8)
    }

    public static func mountArguments(path: String, readOnly: Bool) throws -> [String] {
        try validatePath(path)
        var args = ["--text", "--non-interactive", "--stdin", "--pim=0", "--keyfiles=", "--protect-hidden=no"]
        if readOnly { args.append("--mount-options=ro") }
        return args + ["--mount", path]
    }

    public static func validatePath(_ path: String) throws {
        guard path.hasPrefix("/"), !path.contains(where: { $0.isNewline || $0 == "\0" })
        else { throw BackendError.invalidPath }
    }

    public static func parseMounts(_ text: String, exitCode: Int32) throws -> [Mount] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "Error: No volumes mounted.", exitCode == 1 { return [] }
        guard exitCode == 0 else { throw BackendError.failed }
        guard !trimmed.isEmpty else { throw BackendError.malformedSnapshot }
        let blocks = trimmed.components(separatedBy: "\n\n").filter { !$0.isEmpty }
        let mounts = try blocks.map(parseBlock)
        guard Set(mounts.map(\.slot)).count == mounts.count,
              Set(mounts.map(\.container)).count == mounts.count
        else { throw BackendError.malformedSnapshot }
        return mounts
    }

    private static func parseBlock(_ block: String) throws -> Mount {
        var fields: [String: String] = [:]
        for line in block.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { throw BackendError.malformedSnapshot }
            let key = String(line[..<colon])
            guard fields[key] == nil else { throw BackendError.malformedSnapshot }
            // Remove only the separator space. Paths may themselves end in spaces.
            var value = String(line[line.index(after: colon)...])
            if value.hasPrefix(" ") { value.removeFirst() }
            fields[key] = value
        }
        guard let slotText = fields["Slot"], let slot = Int(slotText), (1...64).contains(slot),
              let path = fields["Volume"], path.hasPrefix("/"),
              let directory = fields["Mount Directory"], directory.isEmpty || directory.hasPrefix("/")
        else { throw BackendError.malformedSnapshot }
        return Mount(slot: slot, container: path, mountPoint: directory.isEmpty ? nil : directory)
    }
}
