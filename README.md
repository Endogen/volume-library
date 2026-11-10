# Volume Library

Volume Library is a native menu bar app for unlocking existing VeraCrypt file containers on macOS. SwiftUI draws the library and password window. AppKit owns the menu bar icon and windows. The installed VeraCrypt executable handles all cryptography, mounting and ejection.

## Use it

Open `build/Volume Library.app`. Click the lock or drive in the menu bar and choose **Add Volume…**. Choose an existing container, click **Unlock**, and enter its volume password. Newly added volumes default to read-only. Click the folder to open the mounted filesystem in Finder, then click the eject button when finished.

**Move to Menu Bar** hides the app windows and removes its Dock icon. Click the menu bar icon and choose **Open Volume Library** to restore the window. The yellow minimize button retains its usual Dock behavior.

Right-click a saved entry to rename it, toggle its favorite status, locate a moved container, or remove its library reference. **Eject All** acts on mounts that this app opened or that you explicitly took over using **Manage**. If you quit with volumes mounted, the app offers distinct choices for ejection and leaving them mounted.

## Backend and scope

The verified combination is Apple silicon, macOS 27.0.1, VeraCrypt 1.26.31 for FUSE-T, and FUSE-T 1.2.9. The deployment target is macOS 14. The adapter accepts the official signed VeraCrypt 1.26.31 executable and looks in `/Applications/VeraCrypt.app` by default. Settings can locate another installed copy. [VeraCrypt downloads](https://veracrypt.io/en/Downloads.html)

Use a normal, password-only file container with default PIM. Read/write access requires explicitly confirming that the volume has no hidden volume to protect. The live verification covered read-only access. Use VeraCrypt itself for container creation, keyfiles, custom PIM, hidden-volume protection and operations that require administrator authorization.

The app passes the password to VeraCrypt over the subprocess's standard input. Only file references, names, favorites and preferences are saved. The local library lives at `~/Library/Application Support/VolumeLibrary/library.json`. Settings offers a separate in-memory demo with sample volumes.

## Build and test

With the Swift 6 toolchain and macOS SDK installed, run these from the project directory.

```sh
CONFIGURATION=release ./scripts/build.sh
open 'build/Volume Library.app'
swift test
```

For the opt-in integration test, install the matching VeraCrypt and FUSE-T builds and run the following. It creates a fresh 5 MB FAT container and a random password, verifies macOS mounted it read-only, then ejects it and removes the fixture.

```sh
VOLUME_LIBRARY_LIVE_TEST=1 swift test
```

The build script produces an ad-hoc-signed local app. Public distribution and notarization remain future work. To launch directly into the library or demo, quit the running copy first.

```sh
open 'build/Volume Library.app' --args --show-library
open 'build/Volume Library.app' --args --demo --show-menu
```

[Design](DESIGN.md) · [Design verification](design-qa.md) · [Implementation log](WORK_LOG.md)
