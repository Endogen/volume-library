import AppKit
import SwiftUI
import ServiceManagement
import VolumeCore

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var libraryWindow: NSWindow?
    private var unlockWindow: NSWindow?
    private var creationWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var polling: Task<Void, Never>?
    private var terminationApproved = false
    private var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system"
        applyAppearance(appearance)
        configureMenu()
        installStatusItem()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 352, height: 520)
        popover.contentViewController = NSHostingController(rootView: MenuPanel(model: model, controller: self))
        Task {
            if CommandLine.arguments.contains("--demo") { await model.setDemo(true) }
            else { await model.refresh() }
            if CommandLine.arguments.contains("--show-library") { showLibrary() }
            else if !UserDefaults.standard.bool(forKey: "hasLaunched") || CommandLine.arguments.contains("--show-menu") { showMenu() }
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            updateStatusIcon()
        }
        polling = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                await model.refresh()
                updateStatusIcon()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refreshState), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func applyAppearance(_ preference: String) {
        let appearance: NSAppearance? = preference == "system" ? nil : NSAppearance(named: preference == "dark" ? .darkAqua : .aqua)
        NSApp.appearance = appearance
        popover.appearance = appearance
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        item.button?.target = self
        item.button?.action = #selector(toggleMenu)
        updateStatusIcon()
    }

    func updateStatusIcon() {
        let symbol = model.state.isFresh ? (model.mountedCount > 0 ? "externaldrive.fill" : "lock") : "exclamationmark.triangle"
        let description = "Volume Library, \(model.state.isFresh ? "\(model.mountedCount) mounted" : "status unknown")"
        guard let button = statusItem?.button, button.toolTip != description else { return }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        button.image?.isTemplate = true
        button.toolTip = description
        button.setAccessibilityLabel(description)
    }

    @objc private func toggleMenu() {
        if popover.isShown { popover.performClose(nil) } else { showMenu() }
    }
    func showMenu() {
        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        Task { await model.refresh(); updateStatusIcon() }
    }
    func closeMenu() { popover.performClose(nil) }

    @objc func showLibrary() {
        closeMenu()
        if libraryWindow == nil {
            libraryWindow = makeWindow(title: "Volume Library", width: 720, height: 520,
                                       root: LibraryView(model: model, controller: self), resizable: true)
            libraryWindow?.minSize = NSSize(width: 620, height: 420)
        }
        present(libraryWindow)
    }
    @objc func moveToMenuBar() {
        guard model.busyPath == nil else { return }
        libraryWindow?.orderOut(nil)
        settingsWindow?.orderOut(nil)
        creationWindow?.close()
        unlockWindow?.close()
        closeMenu()
        NSApp.setActivationPolicy(.accessory)
    }
    func showUnlock(_ volume: SavedVolume) {
        guard model.busyPath == nil else { return }
        closeMenu()
        model.notice = nil
        unlockWindow?.close()
        unlockWindow = makeWindow(title: "Unlock \(volume.name)", width: 440, height: model.demo ? 326 : 300,
                                  root: UnlockView(model: model, controller: self, volume: volume), resizable: false)
        unlockWindow?.identifier = NSUserInterfaceItemIdentifier("unlock")
        present(unlockWindow)
    }
    func resizeUnlock(expanded: Bool) {
        unlockWindow?.setContentSize(NSSize(width: 440, height: (expanded ? 470 : 300) + (model.demo ? 26 : 0)))
    }
    func finishUnlock() {
        unlockWindow?.close()
        unlockWindow = nil
        updateStatusIcon()
        if libraryWindow?.isVisible != true { NSApp.setActivationPolicy(.accessory) }
    }
    @objc func showSettings() {
        closeMenu()
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Settings", width: 468, height: 240,
                                        root: SettingsView(model: model, controller: self), resizable: false)
        }
        present(settingsWindow)
    }

    @objc func newVolume() {
        guard model.canCreate else { return }
        closeMenu()
        if creationWindow == nil {
            creationWindow = makeWindow(title: "New Volume", width: 450, height: 328,
                                        root: NewVolumeView(model: model, controller: self), resizable: false)
        }
        present(creationWindow)
    }

    func destinationForNewVolume() -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save New Volume"
        panel.nameFieldStringValue = "Untitled.hc"
        panel.canCreateDirectories = true
        panel.prompt = "Create"
        return panel.runModal() == .OK ? panel.url : nil
    }

    func closeCreation() { creationWindow?.close() }

    @objc func addVolume() { chooseVolume(replacing: nil) }
    func chooseVolume(replacing id: UUID?) {
        closeMenu()
        let picker = NSOpenPanel()
        picker.title = id == nil ? "Add an existing VeraCrypt container" : "Locate your container"
        picker.prompt = id == nil ? "Add Volume" : "Locate"
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if picker.runModal() == .OK, let url = picker.url { model.add(url, replacing: id) }
        showLibrary()
    }
    func locateVeraCrypt() {
        guard model.busyPath == nil else { return }
        let picker = NSOpenPanel()
        picker.title = "Locate VeraCrypt.app"
        picker.allowedContentTypes = [.applicationBundle]
        picker.canChooseDirectories = false
        picker.prompt = "Use VeraCrypt"
        if picker.runModal() == .OK, let url = picker.url {
            model.appPath = url.path
            Task { await model.reconnect(); updateStatusIcon() }
        }
    }
    func openVeraCrypt() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: model.appPath), configuration: .init())
    }
    func openDownloads() {
        if let url = URL(string: "https://veracrypt.io/en/Downloads.html") { NSWorkspace.shared.open(url) }
    }

    func confirmEjectAll() {
        closeMenu()
        let alert = NSAlert()
        alert.messageText = "Eject all managed volumes?"
        alert.informativeText = "\(model.managedMounts.count) volumes will be ejected. Volumes mounted outside this app are left alone."
        alert.addButton(withTitle: "Eject All")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { _ = await model.ejectAll(); updateStatusIcon(); showMenu() }
    }
    func adopt(_ mount: Mount) {
        closeMenu()
        let alert = NSAlert()
        alert.messageText = "Manage this mounted volume?"
        alert.informativeText = "It will be included in Eject All and Eject and Quit for this session."
        alert.addButton(withTitle: "Manage Volume")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { model.adopt(mount) }
    }

    func rename(_ volume: SavedVolume) {
        closeMenu()
        let alert = NSAlert()
        alert.messageText = "Rename volume"
        alert.informativeText = "Only the name in your library changes."
        let field = NSTextField(string: volume.name)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { model.update(volume.id) { $0.name = name } }
    }

    func remove(_ volume: SavedVolume) {
        closeMenu()
        let alert = NSAlert()
        alert.messageText = "Remove \(volume.name) from the library?"
        alert.informativeText = "The container and its files will stay exactly where they are."
        alert.addButton(withTitle: "Remove Reference")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { model.remove(volume.id) }
    }

    @objc private func refreshState() { Task { await model.refresh(); updateStatusIcon() } }
    @objc func requestQuit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationApproved { return .terminateNow }
        guard !quitting else { return .terminateCancel }
        guard model.busyPath == nil else {
            model.notice = "Wait for the current operation to finish before quitting."
            showLibrary()
            return .terminateCancel
        }
        if model.state.isFresh && model.mountedCount == 0 { return .terminateNow }
        closeMenu()
        let alert = NSAlert()
        alert.messageText = model.state.isFresh ? (model.mountedCount == 1 ? "1 volume is still mounted" : "\(model.mountedCount) volumes are still mounted") : "Mount status is unknown"
        alert.informativeText = "Quitting alone leaves mounted files accessible. Eject and Quit applies only to the \(model.managedMounts.count) volumes managed by this app."
        if !model.managedMounts.isEmpty { alert.addButton(withTitle: "Eject and Quit") }
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit Without Ejecting")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        let hasTargets = !model.managedMounts.isEmpty
        if response.rawValue == (hasTargets ? 1002 : 1001) { return .terminateNow }
        if hasTargets && response == .alertFirstButtonReturn {
            quitting = true
            Task {
                if await model.ejectAll() { terminationApproved = true; NSApp.terminate(nil) }
                else { showLibrary() }
                quitting = false
            }
        }
        return .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) { polling?.cancel() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if popover.isShown { return false }
        showLibrary(); return false
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if (sender === unlockWindow || sender === creationWindow) && model.busyPath != nil { return false }
        return true
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === creationWindow {
            window.contentView = nil
            creationWindow = nil
        } else if window === unlockWindow {
            window.contentView = nil
            unlockWindow = nil
        }
    }

    private func makeWindow<Content: View>(title: String, width: CGFloat, height: CGFloat,
                                           root: Content, resizable: Bool) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: style, backing: .buffered, defer: false)
        window.title = title
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        window.setContentSize(NSSize(width: width, height: height))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }
    private func present(_ window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    private func configureMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Volume Library", action: #selector(requestQuit), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; main.addItem(appItem)
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "New Volume…", action: #selector(newVolume), keyEquivalent: "n")
        file.addItem(withTitle: "Add Volume…", action: #selector(addVolume), keyEquivalent: "o")
        file.addItem(withTitle: "Open Volume Library", action: #selector(showLibrary), keyEquivalent: "1")
        file.addItem(withTitle: "Move to Menu Bar", action: #selector(moveToMenuBar), keyEquivalent: "")
        let fileItem = NSMenuItem(); fileItem.submenu = file; main.addItem(fileItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(); editItem.submenu = edit; main.addItem(editItem)
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let windowItem = NSMenuItem(); windowItem.submenu = window; main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }
}
