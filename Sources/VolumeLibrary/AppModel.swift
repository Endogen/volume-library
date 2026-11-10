import AppKit
import Observation
import VolumeCore

@MainActor @Observable
final class AppModel {
    var volumes: [SavedVolume] = []
    var state = MountState()
    var backendInfo: BackendInfo?
    var setupMessage: String?
    var notice: String?
    var busyPath: String?
    var isRefreshing = false
    var demo = false
    var libraryLoadFailed = false
    var appPath: String {
        didSet { UserDefaults.standard.set(appPath, forKey: "veraCryptAppPath") }
    }
    private var backend: any VolumeBackend
    private let store: LibraryStore

    init() {
        let initialPath = UserDefaults.standard.string(forKey: "veraCryptAppPath") ?? "/Applications/VeraCrypt.app"
        appPath = initialPath
        backend = VeraCryptBackend(appURL: URL(fileURLWithPath: initialPath))
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = LibraryStore(url: support.appendingPathComponent("VolumeLibrary/library.json"))
        loadLibrary()
    }

    var mountedCount: Int { state.mounts.count }
    var canOperate: Bool { backendInfo != nil && state.isFresh && busyPath == nil && !isRefreshing }
    var managedMounts: [Mount] { state.ejectTargets }
    var favorites: [SavedVolume] { volumes.filter { $0.favorite && mount(for: $0) == nil } }
    var mountedVolumes: [SavedVolume] { volumes.filter { mount(for: $0) != nil } }
    var externalMounts: [Mount] { state.mounts.filter { m in !volumes.contains { $0.path == m.container } } }

    func mount(for volume: SavedVolume) -> Mount? { state.mounts.first { $0.container == volume.path } }
    func isAvailable(_ volume: SavedVolume) -> Bool {
        if demo { return volume.name != "Travel" }
        return FileManager.default.fileExists(atPath: volume.path)
    }
    func subtitle(for volume: SavedVolume) -> String {
        if busyPath == volume.path { return "Working…" }
        if !isAvailable(volume), mount(for: volume) == nil { return "Unavailable" }
        if !state.isFresh { return mount(for: volume) == nil ? "Status unknown" : "Last seen mounted" }
        if let mount = mount(for: volume) { return mount.mountPoint == nil ? "Partially attached" : "Mounted" }
        return "Locked"
    }

    func reconnect() async {
        guard busyPath == nil, !isRefreshing else { return }
        if !demo { backend = VeraCryptBackend(appURL: URL(fileURLWithPath: appPath)) }
        backendInfo = nil
        await refresh()
    }

    func refresh() async {
        guard busyPath == nil, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            if backendInfo == nil { backendInfo = try await backend.probe() }
            state.apply(try await backend.list())
            setupMessage = nil
        } catch {
            state.invalidate()
            setupMessage = readable(error)
            backendInfo = nil
        }
    }

    func setDemo(_ enabled: Bool) async {
        guard busyPath == nil, !isRefreshing else { return }
        // Do not abandon tracking of real mounts by changing backend.
        guard demo || state.managedPaths.isEmpty else {
            notice = "Eject your managed volumes before entering demo mode."
            return
        }
        demo = enabled
        notice = nil
        state = MountState()
        if enabled {
            backend = DemoBackend()
            volumes = [SavedVolume(name: "Personal", path: "/Demo/Personal.hc"),
                       SavedVolume(name: "Archive", path: "/Demo/Archive.hc"),
                       SavedVolume(name: "Travel", path: "/Demo/Travel.hc")]
        } else { loadLibrary() }
        await reconnect()
        if enabled { state.adopt("/Demo/Personal.hc") }
    }

    func unlock(_ volume: SavedVolume, password: String, readOnly: Bool, openAfter: Bool) async -> Bool {
        guard canOperate else { return false }
        busyPath = volume.path
        notice = nil
        defer { busyPath = nil }
        guard await verifyBackend() else { return false }
        do {
            state.apply(try await backend.list())
            guard mount(for: volume) == nil else {
                notice = "This volume is already mounted. Its status has been refreshed."
                return false
            }
            try await backend.mount(path: volume.path, password: password, readOnly: readOnly)
            state.apply(try await backend.list())
            guard let mounted = mount(for: volume) else { throw IntegrationError.operationFailed }
            state.adopt(volume.path)
            if mounted.mountPoint == nil {
                notice = "The encrypted volume attached, but its filesystem did not mount. Eject it before trying again."
                return false
            }
            update(volume.id) { $0.readOnly = readOnly; $0.openAfterMount = openAfter }
            if openAfter { openInFinder(volume) }
            return true
        } catch {
            notice = readable(error)
            await reconcileAfterFailure()
            return false
        }
    }

    func eject(_ mount: Mount) async -> Bool {
        guard canOperate, state.managedPaths.contains(mount.container) else { return false }
        busyPath = mount.container
        notice = nil
        defer { busyPath = nil }
        guard await verifyBackend() else { return false }
        do {
            state.apply(try await backend.list())
            guard state.mounts.contains(mount), state.managedPaths.contains(mount.container) else {
                notice = "The mount changed. Review its refreshed status before ejecting."
                return false
            }
            try await backend.unmount(path: mount.container)
            state.apply(try await backend.list())
            guard !state.mounts.contains(where: { $0.container == mount.container }) else {
                throw IntegrationError.operationFailed
            }
            return true
        } catch {
            notice = readable(error)
            await reconcileAfterFailure()
            return false
        }
    }

    func ejectAll() async -> Bool {
        let targets = managedMounts
        guard !targets.isEmpty else { return state.isFresh }
        for mount in targets {
            if !(await eject(mount)) { return false }
        }
        return state.isFresh && state.ejectTargets.isEmpty
    }

    func adopt(_ mount: Mount) { state.adopt(mount.container) }

    func add(_ url: URL, replacing id: UUID? = nil) {
        guard !libraryLoadFailed else { notice = "The saved library could not be read. Its file has been preserved."; return }
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        do {
            try BackendContract.validatePath(resolved.path)
            guard !volumes.contains(where: { $0.path == resolved.path && $0.id != id }) else {
                notice = "This volume is already in your library."
                return
            }
            let bookmark = try resolved.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            if let id {
                update(id) { $0.path = resolved.path; $0.bookmark = bookmark }
            } else {
                volumes.append(SavedVolume(name: resolved.deletingPathExtension().lastPathComponent,
                                           path: resolved.path, bookmark: bookmark))
                persist()
            }
        } catch { notice = "Couldn’t save this file reference. Choose a readable local container file." }
    }

    func update(_ id: UUID, change: (inout SavedVolume) -> Void) {
        guard let index = volumes.firstIndex(where: { $0.id == id }) else { return }
        change(&volumes[index])
        persist()
    }
    func remove(_ id: UUID) {
        guard let volume = volumes.first(where: { $0.id == id }), mount(for: volume) == nil, busyPath == nil else { return }
        volumes.removeAll { $0.id == id }
        persist()
    }
    func openInFinder(_ volume: SavedVolume) {
        guard let mount = mount(for: volume) else { return }
        openInFinder(mount)
    }
    func openInFinder(_ mount: Mount) {
        guard !demo else { notice = "This demo volume has no files."; return }
        guard state.isFresh, state.mounts.contains(mount), let path = mount.mountPoint else { return }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            notice = "The mount directory is unavailable. Refresh the volume status."
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func loadLibrary() {
        do {
            volumes = try store.load().map(resolveBookmark)
            libraryLoadFailed = false
        } catch {
            volumes = []
            libraryLoadFailed = true
            notice = "The saved library could not be read. It has been left untouched."
        }
    }
    private func resolveBookmark(_ volume: SavedVolume) -> SavedVolume {
        guard let data = volume.bookmark else { return volume }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return volume }
        var result = volume
        result.path = url.path
        if stale { result.bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) }
        return result
    }
    private func persist() {
        guard !demo, !libraryLoadFailed else { return }
        do { try store.save(volumes) }
        catch { notice = "Changes could not be saved. Check available disk space and permissions." }
    }
    private func verifyBackend() async -> Bool {
        do {
            backendInfo = try await backend.probe()
            return true
        } catch {
            backendInfo = nil
            state.invalidate()
            setupMessage = readable(error)
            notice = setupMessage
            return false
        }
    }
    private func reconcileAfterFailure() async {
        do { state.apply(try await backend.list()) }
        catch { state.invalidate() }
    }
    private func readable(_ error: Error) -> String {
        if let error = error as? IntegrationError { return error.localizedDescription }
        switch error as? BackendError {
        case .invalidPassword: return "Use a password of 1–128 UTF-8 bytes without line breaks or NUL characters."
        case .timedOut: return "VeraCrypt took too long. Check the refreshed mount status before trying again."
        case .malformedSnapshot: return "Mount status could not be read reliably. No volume will be assumed locked."
        default: return "Couldn’t communicate with VeraCrypt. Check its installation, then retry."
        }
    }
}
