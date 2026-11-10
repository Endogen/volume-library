import Foundation
import Observation
import Testing
@testable import VolumeCore
@testable import VolumeLibrary

private actor CheckBackend: VolumeBackend {
    var mounts: [Mount] = []
    var pauseNext = false
    var waiting: CheckedContinuation<[Mount], Error>?
    func pause() { pauseNext = true }
    func waitForCheck() async {
        while waiting == nil { await Task.yield() }
    }
    func finish(_ result: Result<[Mount], Error>) {
        waiting?.resume(with: result)
        waiting = nil
    }
    func probe() -> BackendInfo { BackendInfo(version: "test", flavor: "test") }
    func list() async throws -> [Mount] {
        if pauseNext {
            pauseNext = false
            return try await withCheckedThrowingContinuation { waiting = $0 }
        }
        return mounts
    }
    func mount(path: String, password: String, readOnly: Bool) {
        mounts = [Mount(slot: 1, container: path, mountPoint: "/Volumes/Test")]
    }
    func unmount(path: String) { mounts = [] }
}

@MainActor @Test func routineCheckIsSilentAndCannotUndoAnUnlock() async {
    let backend = CheckBackend()
    let model = AppModel(backend: backend, store: LibraryStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
    await model.refresh()
    await backend.pause()
    let check = Task { await model.refresh() }
    await backend.waitForCheck()
    #expect(model.canOperate)
    let volume = SavedVolume(name: "Test", path: "/test.hc")
    #expect(await model.unlock(volume, password: "test", readOnly: true, openAfter: false))
    await backend.finish(.success([]))
    await check.value
    #expect(model.managedMounts.count == 1)

    withObservationTracking {
        _ = (model.state, model.canOperate, model.backendInfo, model.setupMessage)
    } onChange: {
        Issue.record("An unchanged poll published a UI change")
    }
    await model.refresh()
}

@MainActor @Test func failedCheckReportsUnknownAndRecovers() async {
    let backend = CheckBackend()
    let model = AppModel(backend: backend, store: LibraryStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
    await model.refresh()
    await backend.pause()
    let check = Task { await model.refresh() }
    await backend.waitForCheck()
    await backend.finish(.failure(BackendError.failed))
    await check.value
    #expect(!model.canOperate)
    #expect(model.setupMessage != nil)
    await model.refresh()
    #expect(model.canOperate)
    #expect(model.setupMessage == nil)
}
