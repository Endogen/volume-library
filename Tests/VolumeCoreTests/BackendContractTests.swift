import Foundation
import Testing
@testable import VolumeCore

@Test func passwordPreservesWhitespaceAndUnicode() throws {
    #expect(try BackendContract.passwordInput("  päss word  ") == Data("  päss word  \n".utf8))
}

@Test func rejectsUnrepresentablePasswords() {
    for password in ["", "first\nsecond", "first\r\nsecond", "nul\0byte", String(repeating: "a", count: 129)] {
        #expect(throws: BackendError.invalidPassword) { try BackendContract.passwordInput(password) }
    }
}

@Test func argumentsKeepPathsSeparateAndNeverIncludeSecrets() throws {
    let path = "/tmp/notes $(touch nope) '雪'.hc"
    let args = try BackendContract.mountArguments(path: path, readOnly: true)
    #expect(args.first == "--text")
    #expect(args.contains("--stdin"))
    #expect(args.contains("--non-interactive"))
    #expect(args.contains("--mount-options=ro"))
    #expect(args.last == path)
    #expect(!args.contains { $0.hasPrefix("--password") })
    #expect(throws: BackendError.invalidPath) { try BackendContract.mountArguments(path: "--help", readOnly: true) }
}

@Test func parsesVerboseMountsAndPartialMounts() throws {
    let text = """
    Slot: 1
    Volume: /tmp/Personal Files.hc
    Virtual Device: /dev/disk9
    Mount Directory: /Volumes/Personal Files
    Size: 10 MB

    Slot: 2
    Volume: /tmp/Archive.hc
    Virtual Device: /dev/disk10
    Mount Directory:

    """
    #expect(try BackendContract.parseMounts(text, exitCode: 0) == [
        Mount(slot: 1, container: "/tmp/Personal Files.hc", mountPoint: "/Volumes/Personal Files"),
        Mount(slot: 2, container: "/tmp/Archive.hc", mountPoint: nil)
    ])
}

@Test func parserNeverConvertsUnknownOutputToAllLocked() {
    for text in ["", "backend unavailable", "Slot: 1\nVolume: /tmp/test.hc", "Slot: 1\nVolume: /tmp/test.hc\nMount Directory: /Volumes/test\nUnexpected junk"] {
        #expect(throws: BackendError.malformedSnapshot) { try BackendContract.parseMounts(text, exitCode: 0) }
    }
    #expect(throws: BackendError.failed) { try BackendContract.parseMounts("Slot: 1", exitCode: 1) }
}

@Test func recognizesOnlyExplicitNoVolumesResult() throws {
    #expect(try BackendContract.parseMounts("Error: No volumes mounted.\n", exitCode: 1).isEmpty)
    #expect(throws: BackendError.failed) {
        try BackendContract.parseMounts("Error: No volumes mounted.\nSomething failed", exitCode: 1)
    }
}
