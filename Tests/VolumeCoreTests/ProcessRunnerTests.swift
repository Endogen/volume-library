import Foundation
import Testing
@testable import VolumeCore

@Test func runnerPipesInputWithoutShellExpansion() async throws {
    let input = Data("spaces ' quotes $HOME\n".utf8)
    let result = try await ProcessRunner().run(URL(fileURLWithPath: "/bin/cat"), arguments: [], input: input)
    #expect(result.code == 0)
    #expect(result.output == String(decoding: input, as: UTF8.self))
}

@Test func runnerDrainsBothPipesWithoutDeadlocking() async throws {
    let script = "i=0; while [ $i -lt 5000 ]; do echo stdout; echo stderr >&2; i=$((i+1)); done"
    let result = try await ProcessRunner().run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script])
    #expect(result.code == 0)
    #expect(result.output.split(separator: "\n").count == 5000)
    #expect(result.error.split(separator: "\n").count == 5000)
}

@Test func runnerEnforcesTimeout() async {
    await #expect(throws: BackendError.timedOut) {
        try await ProcessRunner().run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 0.1)
    }
}

@Test func libraryRoundTripKeepsPreferencesAndRejectsCorruption() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LibraryStore(url: directory.appendingPathComponent("library.json"))
    let volume = SavedVolume(name: "Private", path: "/tmp/private.hc", readOnly: true)
    try store.save([volume])
    #expect(try store.load() == [volume])
    try Data("corrupt".utf8).write(to: store.url)
    #expect(throws: (any Error).self) { try store.load() }
    #expect(try String(contentsOf: store.url, encoding: .utf8) == "corrupt")
}
