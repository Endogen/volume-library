import Foundation

public struct SavedVolume: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var path: String
    public var bookmark: Data?
    public var favorite: Bool
    public var readOnly: Bool
    public var openAfterMount: Bool

    public init(id: UUID = UUID(), name: String, path: String, bookmark: Data? = nil,
                favorite: Bool = true, readOnly: Bool = true, openAfterMount: Bool = false) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmark = bookmark
        self.favorite = favorite
        self.readOnly = readOnly
        self.openAfterMount = openAfterMount
    }
}

public struct MountState: Sendable {
    public private(set) var mounts: [Mount] = []
    public private(set) var isFresh = false
    public private(set) var managedPaths: Set<String> = []

    public init() {}
    public mutating func apply(_ mounts: [Mount]) {
        let continuous = mounts.filter { isFresh && self.mounts.contains($0) }
        managedPaths.formIntersection(Set(continuous.map(\.container)))
        self.mounts = mounts
        isFresh = true
    }
    public mutating func invalidate() { isFresh = false }
    public mutating func adopt(_ path: String) {
        guard isFresh, mounts.contains(where: { $0.container == path }) else { return }
        managedPaths.insert(path)
    }
    public var ejectTargets: [Mount] {
        guard isFresh else { return [] }
        return mounts.filter { managedPaths.contains($0.container) }
    }
}

public struct LibraryStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    private struct Document: Codable { let version: Int; let volumes: [SavedVolume] }

    public func load() throws -> [SavedVolume] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let doc = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        guard doc.version == 1, Set(doc.volumes.map(\.id)).count == doc.volumes.count else {
            throw BackendError.failed
        }
        for volume in doc.volumes { try BackendContract.validatePath(volume.path) }
        return doc.volumes
    }
    public func save(_ volumes: [SavedVolume]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Document(version: 1, volumes: volumes))
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
