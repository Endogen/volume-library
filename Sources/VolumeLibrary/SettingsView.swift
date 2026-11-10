import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var model: AppModel
    let controller: AppController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginMessage: String?
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("VeraCrypt").font(.headline)
                        Spacer()
                        if model.setupMessage == nil, let info = model.backendInfo {
                            Label("\(info.version) · \(info.flavor)", systemImage: "checkmark.circle")
                                .font(.callout).foregroundStyle(.secondary)
                                .accessibilityLabel("Connected to VeraCrypt \(info.version), \(info.flavor)")
                        }
                    }
                    if let message = model.setupMessage {
                        Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                    } else if model.backendInfo == nil {
                        Text("Checking installation…").font(.callout).foregroundStyle(.secondary)
                    }
                    Text(model.appPath).font(.callout).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    HStack {
                        Button("Locate…", action: controller.locateVeraCrypt)
                        Button("Retry") { Task { await model.reconnect(); controller.updateStatusIcon() } }
                        if model.setupMessage != nil { Button("Downloads", action: controller.openDownloads) }
                        Spacer()
                        Button("Open VeraCrypt", action: controller.openVeraCrypt)
                    }.disabled(model.busyPath != nil)
                }
                Divider()
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }.pickerStyle(.segmented)
                    .onChange(of: appearance) { _, value in controller.applyAppearance(value) }
                Toggle("Launch in the menu bar at login", isOn: Binding(
                    get: { launchAtLogin }, set: updateLogin
                ))
                if let loginMessage {
                    Text(loginMessage).font(.callout).foregroundStyle(.secondary)
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            .padding(24)
        }
    }

    private func updateLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginMessage = SMAppService.mainApp.status == .requiresApproval ? "Allow Volume Library in System Settings to complete setup." : nil
        } catch { loginMessage = "macOS couldn’t update this login item. Check Login Items in System Settings." }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
