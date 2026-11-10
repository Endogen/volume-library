import Foundation
import Testing
@testable import VolumeCore

@Test func creationWillNotReplaceAnExistingFile() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let original = Data("existing data".utf8)
    try original.write(to: file, options: .withoutOverwriting)
    defer { try? FileManager.default.removeItem(at: file) }
    let backend = VeraCryptBackend(appURL: URL(fileURLWithPath: "/unused"))
    await #expect(throws: CocoaError(.fileWriteFileExists)) {
        try await backend.create(at: file, sizeMiB: 5, password: "fixture")
    }
    #expect(try Data(contentsOf: file) == original)
}
