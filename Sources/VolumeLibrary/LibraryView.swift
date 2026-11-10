import SwiftUI
import VolumeCore

struct LibraryView: View {
    @Bindable var model: AppModel
    let controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your volumes").font(.system(size: 25, weight: .bold))
                    Text(model.state.isFresh ? "\(model.mountedCount) mounted" : "Checking mount status")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                if model.demo { DemoLabel() }
                Button("Add Volume…", systemImage: "plus", action: controller.addVolume)
            }.padding(24)
            if let message = model.setupMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Setup…", action: controller.showSettings)
                }.padding(14).background(.quaternary.opacity(0.45)).padding(.horizontal, 24).padding(.bottom, 12)
            }
            ScrollView {
                if model.volumes.isEmpty {
                    ContentUnavailableView {
                        Label("A place for your private files", systemImage: "externaldrive")
                    } description: {
                        Text("Add an existing VeraCrypt container.\nYour files stay exactly where they are.")
                    } actions: { Button("Add Volume…", action: controller.addVolume) }
                    .padding(.top, 26)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(model.volumes) { volume in
                            VolumeRow(model: model, controller: controller, volume: volume)
                            Divider()
                        }
                    }.padding(.horizontal, 24)
                }
                if !model.externalMounts.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Mounted outside this library").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(model.externalMounts, id: \.container) { mount in
                            ExternalMountRow(model: model, controller: controller, mount: mount)
                        }
                    }.padding(24)
                }
            }
            if let notice = model.notice {
                HStack {
                    Text(notice).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss message")
                }.padding(.horizontal, 24).padding(.vertical, 12)
            }
            Divider()
            HStack {
                Image(systemName: model.state.isFresh ? "checkmark.circle" : "questionmark.circle")
                    .foregroundStyle(model.state.isFresh ? Color.green : Color.secondary)
                Text(model.demo ? "Demo · Simulated volumes" : (model.backendInfo.map { "VeraCrypt \($0.version) · \($0.flavor)" } ?? "Setup required"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await model.refresh(); controller.updateStatusIcon() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh status").accessibilityLabel("Refresh status").disabled(model.busyPath != nil || model.isRefreshing)
                Button("Move to Menu Bar", systemImage: "menubar.rectangle", action: controller.moveToMenuBar)
                Button { controller.showSettings() } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls where !url.hasDirectoryPath { model.add(url) }
            return !urls.isEmpty
        }
    }
}
