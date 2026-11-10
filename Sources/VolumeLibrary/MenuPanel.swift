import SwiftUI
import VolumeCore

struct MenuPanel: View {
    @Bindable var model: AppModel
    let controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Volumes").font(.system(size: 26, weight: .bold))
                    Text(model.state.isFresh ? "\(model.mountedCount) mounted" : "Status unavailable")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                if model.demo { DemoLabel() }
            }.padding(.bottom, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let message = model.setupMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Setup needs attention", systemImage: "info.circle")
                                .font(.system(size: 13, weight: .semibold))
                            Text(message).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button("Check Setup…", action: controller.showSettings)
                        }
                    }
                    if !model.mountedVolumes.isEmpty || !model.externalMounts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionTitle("Mounted")
                            ForEach(model.mountedVolumes) { volume in
                                VolumeRow(model: model, controller: controller, volume: volume, compact: true)
                            }
                            ForEach(model.externalMounts, id: \.container) { mount in
                                ExternalMountRow(model: model, controller: controller, mount: mount)
                            }
                        }
                    }
                    if !model.favorites.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionTitle("Favorites")
                            ForEach(model.favorites) { volume in
                                VolumeRow(model: model, controller: controller, volume: volume, compact: true)
                            }
                        }
                    }
                    if model.volumes.isEmpty && model.externalMounts.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No saved volumes").font(.system(size: 14, weight: .medium))
                            Text("Create a volume or add an existing container.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                    if let notice = model.notice {
                        Text(notice).font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.trailing, 2)
            }.scrollIndicators(.hidden)

            Divider().padding(.vertical, 14)
            VStack(alignment: .leading, spacing: 2) {
                action("New Volume…", symbol: "doc.badge.plus", run: controller.newVolume)
                    .disabled(!model.canCreate)
                action("Add Volume…", symbol: "plus", run: controller.addVolume)
                action("Open Volume Library", symbol: "rectangle.on.rectangle", run: controller.showLibrary)
                action("Eject All…", symbol: "eject", run: controller.confirmEjectAll)
                    .disabled(model.managedMounts.isEmpty || !model.canOperate)
                action("Settings…", symbol: "gearshape", run: controller.showSettings)
                action("Quit…", symbol: "power", run: controller.requestQuit)
            }
        }
        .padding(22)
        .frame(width: 352, height: 520)
        .background(.regularMaterial)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
    }
    private func action(_ title: String, symbol: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 29).contentShape(Rectangle())
        }
        .buttonStyle(MenuCommandStyle())
        .font(.system(size: 14))
        .padding(.horizontal, -7)
    }
}

private struct MenuCommandStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let highlighted = enabled && hovered
        return configuration.label
            .padding(.horizontal, 7)
            .background(.primary.opacity(enabled && configuration.isPressed ? 0.16 : highlighted ? 0.09 : 0),
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.45)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: highlighted)
    }
}

struct DemoLabel: View {
    var body: some View {
        Text("DEMO").font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.6).padding(.horizontal, 7).padding(.vertical, 4)
            .foregroundStyle(.secondary).background(.quaternary, in: Capsule())
            .accessibilityLabel("Demo mode. No real volumes are changed.")
    }
}

struct ExternalMountRow: View {
    @Bindable var model: AppModel
    let controller: AppController
    let mount: Mount

    var body: some View {
        let name = URL(fileURLWithPath: mount.container).deletingPathExtension().lastPathComponent
        HStack {
            Image(systemName: "externaldrive").foregroundStyle(.secondary)
            Text(name).lineLimit(1).help(mount.container)
            Spacer()
            Button { model.openInFinder(mount) } label: { Image(systemName: "folder") }
                .disabled(!model.state.isFresh || mount.mountPoint == nil)
                .accessibilityLabel("Open \(name) in Finder")
            if model.state.managedPaths.contains(mount.container) {
                Button { Task { _ = await model.eject(mount); controller.updateStatusIcon() } }
                    label: { Image(systemName: "eject") }
                    .disabled(!model.canOperate).accessibilityLabel("Eject \(name)")
            } else {
                Button("Manage…") { controller.adopt(mount) }.disabled(!model.canOperate)
            }
        }.font(.system(size: 13))
    }
}

struct VolumeRow: View {
    @Bindable var model: AppModel
    let controller: AppController
    let volume: SavedVolume
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.mount(for: volume) == nil ? "externaldrive" : "externaldrive.fill")
                .font(.system(size: compact ? 19 : 25))
                .foregroundStyle(model.mount(for: volume) != nil && model.state.isFresh ? Color.green : Color.secondary)
                .frame(width: compact ? 24 : 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(volume.name).font(.system(size: compact ? 15 : 14, weight: compact ? .regular : .medium)).lineLimit(1)
                if !compact { Text(model.subtitle(for: volume)).font(.system(size: 12)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 4)
            rowAction
        }
        .padding(.vertical, compact ? 9 : 12)
        .contentShape(Rectangle())
        .help(volume.path)
        .contextMenu {
            Button(volume.favorite ? "Remove from Favorites" : "Add to Favorites") {
                model.update(volume.id) { $0.favorite.toggle() }
            }
            Button("Rename…") { controller.rename(volume) }
            Button("Locate…") { controller.chooseVolume(replacing: volume.id) }
                .disabled(model.mount(for: volume) != nil || model.busyPath != nil)
            Divider()
            Button("Remove from Library…") { controller.remove(volume) }
                .disabled(model.mount(for: volume) != nil || model.busyPath != nil)
        }
    }

    @ViewBuilder private var rowAction: some View {
        if model.busyPath == volume.path {
            ProgressView().controlSize(.small).frame(width: 28).accessibilityLabel("Working on \(volume.name)")
        } else if let mount = model.mount(for: volume) {
            Button { model.openInFinder(volume) } label: { Image(systemName: "folder") }
                .help("Open \(volume.name) in Finder").accessibilityLabel("Open \(volume.name) in Finder")
                .disabled(!model.state.isFresh || mount.mountPoint == nil)
            if model.state.managedPaths.contains(volume.path) {
                Button {
                    Task { _ = await model.eject(mount); controller.updateStatusIcon() }
                } label: { Image(systemName: "eject") }
                .help("Eject \(volume.name)").accessibilityLabel("Eject \(volume.name)")
                .disabled(!model.canOperate)
            } else {
                Button("Manage…") { controller.adopt(mount) }.disabled(!model.canOperate)
            }
        } else if !model.isAvailable(volume) {
            if compact { Text("Unavailable").font(.system(size: 12)).foregroundStyle(.secondary) }
            else { Button("Locate…") { controller.chooseVolume(replacing: volume.id) } }
        } else {
            Button("Unlock") { controller.showUnlock(volume) }
                .buttonStyle(.borderedProminent).disabled(!model.canOperate)
                .accessibilityLabel("Unlock \(volume.name)")
        }
    }
}
