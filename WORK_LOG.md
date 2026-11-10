# Implementation log

## 5 November 2026

- Selected concept 3, Menu Bar First. Use SwiftUI and AppKit rather than a web prototype because the requested deliverable is a native macOS application.
- Read ub-mode and the Product Design implementation/QA guidance. Checked Xcode 27.2 and Swift 6.4.2 availability.
- Inspected installed VeraCrypt 1.26.31: signed by HLTN5GLG99, linked to macFUSE, and unable to start because libfuse.2.dylib is absent. User reports replacing macFUSE with FUSE-T; confirmed libfuse-t.dylib exists. Do not modify the user's existing installation or containers.
- Started a dependency-free Swift package with a native executable and separately testable core. Begin with tests for credential transport, mount parsing, and state ownership before implementing the backend.


- Implemented the native menu bar panel, compact library, unlock window and settings. Used a shared model with a simulated backend for interaction testing and a file-backed bookmarked library for live use.
- Added the signed executable probe, bounded subprocess I/O, UTF-8 stdin transport, mount-list parsing, mount ownership and tests before enabling the live controls. The first FUSE-T fixture attempt on 5 November did not complete. Live mutation remained disabled pending a successful round trip.
- Exercised the native demo flow, including an incorrect password, unlock, eject and quit choices. Corrected unsupported SF Symbols and excessive settings window height.

## 10 November 2026

- Verified the installed VeraCrypt executable now starts, reports 1.26.31 and links to FUSE-T. No test mount remained from the earlier run.
- Used a disposable 5 MB normal FAT container to test the installed CLI. The volume mounted read-only and ejected successfully. Added an opt-in Swift integration test that creates a unique container and Unicode password, reads the mounted filesystem's read-only flag, ejects and verifies disappearance. Observed the test fail against the disabled backend, then pass after implementing live mount and eject.
- Added a failing replacement-mount regression test and fixed ownership reconciliation. A changed slot or mount point requires explicit adoption. Rechecking an unchanged mount after a routine operation error preserves its ownership. Failed status reads leave the stale snapshot ineligible for ejection.
- Improved controls for external mounts, Finder directory checks, setup error reporting, login item state and popover appearance. Rechecked the backend signature during status refresh and before mutation.
- Used the release app's actual open panel and secure field to add, unlock and eject the disposable container. Removed the test reference. An unintended picker reference was also removed without opening its file. The library was empty at handoff.
- Verified menu bar hiding, status-button activation, popover visibility and reopening using an instrumented copy of the native app. Compared the reference with the actual controls in light and dark appearances. See the design QA report.
- Ran the ub-mode companion tools. Their analyzers do not support these Swift sources, so they supplied no Swift complexity, duplication or mutation scores. The Swift tests and native checks provide the verification here.
- Final checks passed for 14 tests including the opt-in live round trip, the optimized app build, Info.plist validation and strict signature verification. The local build uses ad-hoc signing. Local Git history records the work on main. No remote is configured.

### Read/write persistence and app icon

- Extended the opt-in integration test with a fresh 5 MB normal FAT container. Required a writable volume root, wrote a unique payload to `persistence.txt`, verified ejection, resolved the new read-only mount, and compared the recovered bytes. Verified final ejection and removed the fixture. All 14 tests passed with the installed FUSE-T backend. The ub-mode companion tools reported no supported changed sources to analyze.
- Created the app icon from the supplied faceted blue and green monogram and packaged it as an ICNS from a transparent 1024 px master. The original bundle had no icon entry. Rebuilt the release, decoded all ten 1× and 2× representations, verified the bundle signature, and visually checked the artwork that macOS Icon Services returned at 32 and 128 points.
