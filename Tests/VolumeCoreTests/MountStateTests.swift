import Testing
@testable import VolumeCore

@Test func replacedMountNeedsExplicitAdoption() {
    var state = MountState()
    let original = Mount(slot: 1, container: "/tmp/notes.hc", mountPoint: "/Volumes/Notes")
    let replacement = Mount(slot: 2, container: original.container, mountPoint: "/Volumes/Notes 1")
    state.apply([original])
    state.adopt(original.container)
    state.apply([replacement])
    #expect(state.ejectTargets.isEmpty)
}

@Test func failedRefreshPreservesLastMountButDisablesEjection() {
    var state = MountState()
    let mount = Mount(slot: 1, container: "/tmp/a.hc", mountPoint: "/Volumes/a")
    state.apply([mount])
    state.adopt(mount.container)
    #expect(state.ejectTargets == [mount])
    state.invalidate()
    #expect(state.mounts == [mount])
    #expect(!state.isFresh)
    #expect(state.ejectTargets.isEmpty)
}

@Test func externalMountsAreNeverImplicitlyOwned() {
    var state = MountState()
    let own = Mount(slot: 1, container: "/tmp/a.hc", mountPoint: "/Volumes/a")
    let other = Mount(slot: 2, container: "/tmp/b.hc", mountPoint: "/Volumes/b")
    state.apply([own, other])
    #expect(state.ejectTargets.isEmpty)
    state.adopt(own.container)
    #expect(state.ejectTargets == [own])
    state.apply([other])
    state.apply([own, other])
    #expect(state.ejectTargets.isEmpty)
}
